import Foundation

/// Drives a remote libvirt + QEMU-KVM host over SSH: provision, lifecycle, and
/// stats via `virsh`/`virt-install`. Authenticates with the app's SSH key
/// (add its public key to the host's authorized_keys — Settings has "Copy
/// Public Key"). Remote VMs use x86_64 cloud images the host downloads itself.
enum RemoteBackend {

    /// Runs a bash script on the host over SSH, script fed on stdin.
    static func run(_ host: RemoteHost, _ script: String) -> Shell.Result {
        Shell.run(Shell.ssh, [
            "-i", CredentialsStore.sshPrivateKeyPath,
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=8",
            "-o", "LogLevel=ERROR",
            "-p", "\(host.port)",
            host.sshTarget, "bash -s"
        ], stdin: script)
    }

    /// Checks the host is reachable and has the needed tooling.
    static func test(_ host: RemoteHost) -> (ok: Bool, message: String) {
        let r = run(host, """
        for t in virsh virt-install qemu-img curl; do command -v $t >/dev/null || { echo "MISSING $t"; exit 0; }; done
        virsh version 2>/dev/null | head -1 || echo "virsh-fail"
        """)
        if !r.ok {
            let e = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, e.isEmpty ? "SSH connection failed. Is the key authorized?" : e)
        }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("MISSING") {
            let tool = out.split(separator: " ").last.map(String.init) ?? "tools"
            return (false, "Host is missing `\(tool)`. Install libvirt, virtinst, qemu-utils.")
        }
        return (true, out.isEmpty ? "Connected." : out)
    }

    // MARK: - Provision

    static func provision(host: RemoteHost, record: VMRecord, distro: Distro,
                          username: String, password: String, publicKey: String?) throws {
        let name = record.hostname
        let memMB = record.memoryBytes / (1024 * 1024)
        let diskGB = record.diskSizeBytes / (1024 * 1024 * 1024)
        let userData = buildUserData(username: username, password: password,
                                     publicKey: publicKey, hostname: name)

        let script = """
        set -e
        NAME="\(name)"
        ROOT="$HOME/linuxvm"
        DIR="$ROOT/$NAME"
        IMAGES="$ROOT/images"
        BASE="$IMAGES/\(distro.id).qcow2"
        mkdir -p "$DIR" "$IMAGES"
        if [ ! -f "$BASE" ]; then
          curl -fSL "\(distro.amd64Image)" -o "$BASE.part"
          mv "$BASE.part" "$BASE"
        fi
        cp --reflink=auto "$BASE" "$DIR/disk.qcow2" 2>/dev/null || cp "$BASE" "$DIR/disk.qcow2"
        qemu-img resize "$DIR/disk.qcow2" \(diskGB)G
        cat > "$DIR/user-data" <<'CIEOF'
        \(userData)
        CIEOF
        virsh destroy "$NAME" 2>/dev/null || true
        virsh undefine "$NAME" --nvram 2>/dev/null || true
        virt-install --name "$NAME" --memory \(memMB) --vcpus \(record.cpuCount) \\
          --disk "$DIR/disk.qcow2",format=qcow2,bus=virtio --import \\
          --os-variant linux2022 \\
          --cloud-init user-data="$DIR/user-data" \\
          --network network=default,model=virtio \\
          --graphics none --noautoconsole
        echo PROVISION_OK
        """
        let r = run(host, script)
        guard r.ok, r.stdout.contains("PROVISION_OK") else {
            let err = [r.stdout, r.stderr].joined(separator: "\n")
                .split(separator: "\n").suffix(4).joined(separator: " ")
            throw VMError.configurationInvalid("Remote provisioning failed: \(err)")
        }
    }

    private static func buildUserData(username: String, password: String,
                                      publicKey: String?, hostname: String) -> String {
        let key = publicKey.map { "    ssh_authorized_keys:\n      - \($0)\n" } ?? ""
        let pw = password.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        #cloud-config
        hostname: \(hostname)
        ssh_pwauth: true
        users:
          - name: \(username)
            plain_text_passwd: "\(pw)"
            lock_passwd: false
            sudo: ALL=(ALL) NOPASSWD:ALL
            groups: [sudo, adm, wheel]
            shell: /bin/bash
        \(key)chpasswd:
          expire: false
        """
    }

    // MARK: - Lifecycle

    @discardableResult
    static func start(_ host: RemoteHost, _ name: String) -> Bool {
        run(host, "virsh start \"\(name)\" 2>/dev/null || virsh domstate \"\(name)\" | grep -q running").ok
    }

    static func shutdown(_ host: RemoteHost, _ name: String) {
        _ = run(host, "virsh shutdown \"\(name)\"")
    }

    static func destroy(_ host: RemoteHost, _ name: String) {
        _ = run(host, "virsh destroy \"\(name)\"")
    }

    /// Stops and deletes the domain and its disk on the host.
    static func delete(_ host: RemoteHost, _ name: String) {
        _ = run(host, """
        virsh destroy "\(name)" 2>/dev/null || true
        virsh undefine "\(name)" --nvram --remove-all-storage 2>/dev/null || virsh undefine "\(name)" 2>/dev/null || true
        rm -rf "$HOME/linuxvm/\(name)"
        """)
    }

    // MARK: - Stats

    static func sample(host: RemoteHost, name: String) -> GuestSample? {
        let script = """
        N="\(name)"
        DEV=$(virsh domblklist "$N" 2>/dev/null | awk 'NR>2 && $1!="" {print $1; exit}')
        a=$(virsh domstats "$N" --cpu-total 2>/dev/null | awk -F= '/cpu\\.time/{print $2}')
        sleep 1
        b=$(virsh domstats "$N" --cpu-total 2>/dev/null | awk -F= '/cpu\\.time/{print $2}')
        v=$(virsh dominfo "$N" 2>/dev/null | awk -F: '/CPU\\(s\\)/{gsub(/ /,"",$2);print $2}')
        mu=$(virsh dominfo "$N" 2>/dev/null | awk -F: '/Used memory/{print $2}' | grep -oE '[0-9]+' | head -1)
        mx=$(virsh dominfo "$N" 2>/dev/null | awk -F: '/Max memory/{print $2}' | grep -oE '[0-9]+' | head -1)
        al=$(virsh domblkinfo "$N" "$DEV" 2>/dev/null | awk '/Allocation/{print $2}')
        cap=$(virsh domblkinfo "$N" "$DEV" 2>/dev/null | awk '/Capacity/{print $2}')
        echo "CPU ${a:-0} ${b:-0} ${v:-1}"
        echo "MEM ${mu:-0} ${mx:-0}"
        echo "DISK ${al:-0} ${cap:-0}"
        """
        let r = run(host, script)
        guard r.ok else { return nil }
        var cpu = 0.0, memU: UInt64 = 0, memT: UInt64 = 0, diskU: UInt64 = 0, diskT: UInt64 = 0
        var gotMem = false
        for line in r.stdout.split(separator: "\n") {
            let f = line.split(separator: " ")
            guard let tag = f.first else { continue }
            switch tag {
            case "CPU" where f.count == 4:
                let a = Double(f[1]) ?? 0, b = Double(f[2]) ?? 0, v = max(Double(f[3]) ?? 1, 1)
                cpu = max(0, min(100, (b - a) / 1_000_000_000.0 / v * 100))
            case "MEM" where f.count == 3:
                memU = (UInt64(f[1]) ?? 0) * 1024
                memT = (UInt64(f[2]) ?? 0) * 1024
                gotMem = memT > 0
            case "DISK" where f.count == 3:
                diskU = UInt64(f[1]) ?? 0
                diskT = UInt64(f[2]) ?? 0
            default: break
            }
        }
        guard gotMem else { return nil }
        return GuestSample(ip: host.host, cpuPercent: cpu,
                           memUsedBytes: memU, memTotalBytes: memT,
                           diskUsedBytes: diskU, diskTotalBytes: diskT,
                           diskReadBytesPerSec: 0, diskWriteBytesPerSec: 0)
    }

    static func isRunning(host: RemoteHost, name: String) -> Bool {
        run(host, "virsh domstate \"\(name)\" 2>/dev/null").stdout.contains("running")
    }
}
