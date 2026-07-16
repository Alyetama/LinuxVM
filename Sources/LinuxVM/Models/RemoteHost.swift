import Foundation

/// A remote Linux machine running libvirt + QEMU-KVM, reached over SSH. VMs
/// created "on" this host live there; the Mac only drives them via `virsh`.
struct RemoteHost: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var user: String
    var host: String
    var port: Int

    init(id: String = UUID().uuidString, name: String, user: String, host: String, port: Int = 22) {
        self.id = id
        self.name = name
        self.user = user
        self.host = host
        self.port = port
    }

    var sshTarget: String { "\(user)@\(host)" }
    var label: String { name.isEmpty ? sshTarget : "\(name) (\(sshTarget))" }
}
