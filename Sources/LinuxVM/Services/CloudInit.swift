import Foundation

/// Builds a cloud-init NoCloud "seed" ISO. Attached to a cloud image, it makes
/// the guest configure itself on first boot — create the user, set the
/// password, authorize our SSH key — with no installer and no interaction.
/// Optionally provisions an enhanced developer toolchain.
enum CloudInit {
    /// DNS-safe hostname derived from a VM name.
    static func hostname(for name: String, id: UUID) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let cleaned = String(slug).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = cleaned.isEmpty ? "vm" : String(cleaned.prefix(20))
        return "\(base)-\(id.uuidString.prefix(6).lowercased())"
    }

    /// Escapes a value for a double-quoted YAML scalar (backslash and quote),
    /// dropping control characters. Prevents a password from breaking out of the
    /// `plain_text_passwd: "..."` field in the cloud-config.
    private static func yamlEscaped(_ s: String) -> String {
        var out = ""
        for ch in s where !ch.isNewline && ch != "\0" {
            if ch == "\\" || ch == "\"" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func buildSeed(at destination: URL,
                          username: String, password: String, publicKey: String?,
                          hostname: String, instanceID: UUID, enhanced: Bool) -> Bool {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("linuxvm-seed-\(instanceID.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        do { try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true) }
        catch { return false }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let keyLine = publicKey.map { "    ssh_authorized_keys:\n      - \($0)\n" } ?? ""
        var userData = """
        #cloud-config
        hostname: \(hostname)
        preserve_hostname: false
        ssh_pwauth: true
        disable_root: false
        users:
          - name: \(username)
            plain_text_passwd: "\(yamlEscaped(password))"
            lock_passwd: false
            sudo: ALL=(ALL) NOPASSWD:ALL
            groups: [sudo, adm, wheel]
            shell: /bin/bash
        \(keyLine)chpasswd:
          expire: false

        """
        if enhanced {
            let script = enhancedScript.replacingOccurrences(of: "__USERNAME__", with: username)
            let b64 = Data(script.utf8).base64EncodedString()
            userData += """
            write_files:
              - path: /opt/linuxvm-setup.sh
                permissions: '0755'
                encoding: b64
                content: \(b64)
            runcmd:
              - [bash, /opt/linuxvm-setup.sh]
            """
        }

        let metaData = "instance-id: \(instanceID.uuidString)\nlocal-hostname: \(hostname)"
        do {
            try userData.write(to: tmp.appendingPathComponent("user-data"), atomically: true, encoding: .utf8)
            try metaData.write(to: tmp.appendingPathComponent("meta-data"), atomically: true, encoding: .utf8)
        } catch { return false }

        try? FileManager.default.removeItem(at: destination)
        let r = Shell.run(Shell.hdiutil,
                          ["makehybrid", "-iso", "-joliet", "-default-volume-name", "CIDATA",
                           "-o", destination.path, tmp.path])
        return r.ok && FileManager.default.fileExists(atPath: destination.path)
    }

    /// Best-effort first-boot provisioner for the "enhanced" option. Works on
    /// apt (Debian/Ubuntu) and dnf (Fedora). Logs to /var/log/linuxvm-setup.log
    /// and touches /var/lib/linuxvm-setup-done when finished.
    private static let enhancedScript = """
    #!/bin/bash
    exec >/var/log/linuxvm-setup.log 2>&1
    set -x
    USER_NAME="__USERNAME__"
    export DEBIAN_FRONTEND=noninteractive
    echo "linuxvm enhanced setup starting $(date)"

    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      apt-get install -y zsh tmux git curl wget zip unzip ripgrep fd-find bat build-essential ca-certificates gnupg
    elif command -v dnf >/dev/null 2>&1; then
      dnf -y install zsh tmux git curl wget zip unzip ripgrep fd-find bat gcc gcc-c++ make ca-certificates
      dnf -y group install "Development Tools" || dnf -y groupinstall "Development Tools" || true
    fi

    # Docker (official convenience script supports apt & dnf families)
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && sh /tmp/get-docker.sh || true
    usermod -aG docker "$USER_NAME" || true
    systemctl enable --now docker || true
    if command -v apt-get >/dev/null 2>&1; then apt-get install -y docker-compose-plugin || true
    else dnf -y install docker-compose-plugin || true; fi

    # Per-user setup (oh-my-zsh, oh-my-tmux, miniforge) as the login user.
    cat > /tmp/usersetup.sh <<'USEREOF'
    #!/bin/bash
    set -x
    cd "$HOME"
    # oh-my-zsh
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true
    ZC="$HOME/.oh-my-zsh/custom"
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZC/plugins/zsh-autosuggestions" || true
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZC/plugins/zsh-syntax-highlighting" || true
    git clone --depth=1 https://github.com/agkozak/zsh-z "$ZC/plugins/zsh-z" || true
    # Spaceship prompt
    git clone --depth=1 https://github.com/spaceship-prompt/spaceship-prompt.git "$ZC/themes/spaceship-prompt" || true
    ln -sf "$ZC/themes/spaceship-prompt/spaceship.zsh-theme" "$ZC/themes/spaceship.zsh-theme" || true
    # oh-my-tmux
    git clone --depth=1 https://github.com/gpakosz/.tmux.git "$HOME/.tmux" || true
    ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf" || true
    cp "$HOME/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local" 2>/dev/null || true
    # beautiful zshrc
    cat > "$HOME/.zshrc" <<'ZRC'
    export ZSH="$HOME/.oh-my-zsh"
    ZSH_THEME="spaceship"
    plugins=(git docker zsh-z zsh-autosuggestions zsh-syntax-highlighting)
    source "$ZSH/oh-my-zsh.sh"
    # Spaceship: keep it quick and tidy
    SPACESHIP_PROMPT_ADD_NEWLINE=true
    SPACESHIP_CHAR_SYMBOL="➜ "
    SPACESHIP_PROMPT_DEFAULT_PREFIX="via "
    command -v batcat >/dev/null && alias bat=batcat
    command -v fdfind >/dev/null && alias fd=fdfind
    command -v fd-find >/dev/null && alias fd=fd-find
    alias ll='ls -lah'
    ZRC
    # miniforge (conda)
    curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh" -o /tmp/mf.sh && bash /tmp/mf.sh -b -p "$HOME/miniforge3" || true
    "$HOME/miniforge3/bin/conda" init bash zsh || true
    "$HOME/miniforge3/bin/conda" config --set auto_activate_base false || true
    USEREOF
    chmod 0755 /tmp/usersetup.sh
    runuser -l "$USER_NAME" -c 'bash /tmp/usersetup.sh' || sudo -u "$USER_NAME" -H bash /tmp/usersetup.sh

    chsh -s "$(command -v zsh)" "$USER_NAME" || usermod -s "$(command -v zsh)" "$USER_NAME" || true
    touch /var/lib/linuxvm-setup-done
    echo "linuxvm enhanced setup done $(date)"
    """
}
