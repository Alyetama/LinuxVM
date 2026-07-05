import Foundation

struct GuestSample: Equatable {
    var ip: String
    var cpuPercent: Double
    var memUsedBytes: UInt64
    var memTotalBytes: UInt64
    var diskUsedBytes: UInt64
    var diskTotalBytes: UInt64
    var diskReadBytesPerSec: UInt64
    var diskWriteBytesPerSec: UInt64
}

/// Reads real CPU/memory/disk usage from inside a running VM over SSH, after
/// discovering its NAT IP from the host's ARP table.
enum GuestStats {

    // MARK: IP discovery

    /// Finds the guest IP whose link-layer MAC matches `mac` (our VZ MAC).
    static func discoverIP(mac: String) -> String? {
        let target = normalize(mac)
        if let ip = arpLookup(target) { return ip }
        // Nudge the ARP cache by pinging IPs that hold DHCP leases, then retry.
        for ip in leaseIPs() {
            _ = Shell.run(Shell.ping, ["-c", "1", "-t", "1", ip])
        }
        return arpLookup(target)
    }

    private static func arpLookup(_ normalizedMAC: String) -> String? {
        let r = Shell.run(Shell.arp, ["-an"])
        for line in r.stdout.split(separator: "\n") {
            // ? (192.168.64.5) at 1a:ff:d:3d:94:61 on bridge100 ...
            guard let lp = line.firstIndex(of: "("),
                  let rp = line.firstIndex(of: ")"),
                  let atRange = line.range(of: " at ") else { continue }
            let ip = String(line[line.index(after: lp)..<rp])
            let rest = line[atRange.upperBound...]
            let mac = rest.split(separator: " ").first.map(String.init) ?? ""
            if normalize(mac) == normalizedMAC { return ip }
        }
        return nil
    }

    private static func leaseIPs() -> [String] {
        guard let text = try? String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("ip_address=") ? String(t.dropFirst("ip_address=".count)) : nil
        }
    }

    /// Lowercase, strip leading zero of each octet (macOS `arp` does this).
    private static func normalize(_ mac: String) -> String {
        mac.lowercased().split(separator: ":").map { octet -> String in
            String(Int(octet, radix: 16) ?? 0, radix: 16)
        }.joined(separator: ":")
    }

    // MARK: SSH sampling

    private static let script = """
    dev=$(awk '$2=="/"{print $1}' /proc/mounts | head -1)
    base=$(basename "$dev" 2>/dev/null | sed 's/[0-9]*$//; s/p$//')
    [ -z "$base" ] && base=vda
    rd() { awk -v d="$base" '$3==d{print $6}' /proc/diskstats; }
    wr() { awk -v d="$base" '$3==d{print $10}' /proc/diskstats; }
    busy1=$(awk '/^cpu /{print $2+$3+$4+$6+$7+$8}' /proc/stat); idle1=$(awk '/^cpu /{print $5}' /proc/stat)
    r1=$(rd); w1=$(wr)
    sleep 1
    busy2=$(awk '/^cpu /{print $2+$3+$4+$6+$7+$8}' /proc/stat); idle2=$(awk '/^cpu /{print $5}' /proc/stat)
    r2=$(rd); w2=$(wr)
    echo "CPU $busy1 $idle1 $busy2 $idle2"
    echo "IO ${r1:-0} ${w1:-0} ${r2:-0} ${w2:-0}"
    awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print "MEM",t,a}' /proc/meminfo
    df -kP / | awk 'NR==2{print "DISK",$2,$3}'
    """

    static func sample(ip: String, user: String, keyPath: String) -> GuestSample? {
        let r = Shell.run(Shell.ssh, [
            "-i", keyPath,
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=4",
            "-o", "LogLevel=ERROR",
            "\(user)@\(ip)", "bash -s"
        ], stdin: script)
        guard r.ok else { return nil }

        var cpu = 0.0
        var memTotal: UInt64 = 0, memUsed: UInt64 = 0
        var diskTotal: UInt64 = 0, diskUsed: UInt64 = 0
        var ioRead: UInt64 = 0, ioWrite: UInt64 = 0
        for line in r.stdout.split(separator: "\n") {
            let f = line.split(separator: " ")
            guard let tag = f.first else { continue }
            switch tag {
            case "CPU" where f.count == 5:
                let b1 = Double(f[1]) ?? 0, i1 = Double(f[2]) ?? 0
                let b2 = Double(f[3]) ?? 0, i2 = Double(f[4]) ?? 0
                let db = b2 - b1, di = i2 - i1
                if db + di > 0 { cpu = max(0, min(100, 100 * db / (db + di))) }
            case "IO" where f.count == 5:
                // Sectors (512 B) read/written over the 1 s window → bytes/s.
                let dr = (UInt64(f[3]) ?? 0) &- (UInt64(f[1]) ?? 0)
                let dw = (UInt64(f[4]) ?? 0) &- (UInt64(f[2]) ?? 0)
                ioRead = dr &* 512
                ioWrite = dw &* 512
            case "MEM" where f.count == 3:
                let t = (UInt64(f[1]) ?? 0) * 1024
                let a = (UInt64(f[2]) ?? 0) * 1024
                memTotal = t
                memUsed = t > a ? t - a : 0
            case "DISK" where f.count == 3:
                diskTotal = (UInt64(f[1]) ?? 0) * 1024
                diskUsed = (UInt64(f[2]) ?? 0) * 1024
            default: break
            }
        }
        guard memTotal > 0 else { return nil }
        return GuestSample(ip: ip, cpuPercent: cpu,
                           memUsedBytes: memUsed, memTotalBytes: memTotal,
                           diskUsedBytes: diskUsed, diskTotalBytes: diskTotal,
                           diskReadBytesPerSec: ioRead, diskWriteBytesPerSec: ioWrite)
    }
}
