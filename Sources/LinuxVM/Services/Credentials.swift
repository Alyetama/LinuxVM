import Foundation

/// Default login (username/password, in Keychain) applied to every new VM, plus
/// the app's SSH keypair used to read live stats from inside running VMs.
/// The user picks the username/password on first launch — nothing is defaulted.
@MainActor
final class CredentialsStore: ObservableObject {
    @Published var username: String
    @Published var password: String
    /// True once the user has chosen a username and password.
    @Published private(set) var isConfigured: Bool

    static let appRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LinuxVM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Deterministic path to the app's SSH private key (used by stats polling
    /// and remote-host SSH from nonisolated/detached contexts).
    nonisolated static var sshPrivateKeyPath: String {
        appRoot.appendingPathComponent("id_ed25519").path
    }

    private var privateKeyURL: URL { Self.appRoot.appendingPathComponent("id_ed25519") }
    private var publicKeyURL: URL { Self.appRoot.appendingPathComponent("id_ed25519.pub") }

    init() {
        let u = Keychain.get(account: "username")
        let p = Keychain.get(account: "password")
        username = u ?? ""
        password = p ?? ""
        isConfigured = !(u ?? "").isEmpty && !(p ?? "").isEmpty
        _ = ensureSSHKey()   // the stats keypair is infrastructure, not a credential
    }

    /// A valid Linux username: lowercase, starts with a letter/underscore, no
    /// shell/YAML metacharacters. Enforcing this prevents the username from
    /// being able to inject into the guest's cloud-init YAML, the (root) setup
    /// script, or the `user@ip` SSH argument.
    static func isValidUsername(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard (1...32).contains(t.count) else { return false }
        return t.range(of: "^[a-z_][a-z0-9_-]*$", options: .regularExpression) != nil
    }

    /// Persists the chosen credentials. Returns false if invalid.
    @discardableResult
    func save() -> Bool {
        let u = username.trimmingCharacters(in: .whitespaces)
        username = u
        guard Self.isValidUsername(u), !password.isEmpty else { isConfigured = false; return false }
        Keychain.set(u, account: "username")
        Keychain.set(password, account: "password")
        isConfigured = true
        return true
    }

    var publicKey: String? {
        (try? String(contentsOf: publicKeyURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the SSH public key, generating the keypair if needed.
    @discardableResult
    func ensureSSHKey() -> String? {
        if let existing = publicKey { return existing }
        try? FileManager.default.removeItem(at: privateKeyURL)
        let r = Shell.run(Shell.sshKeygen,
                          ["-t", "ed25519", "-N", "", "-C", "linuxvm-stats", "-f", privateKeyURL.path])
        return r.ok ? publicKey : nil
    }
}
