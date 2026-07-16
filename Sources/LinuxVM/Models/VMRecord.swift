import Foundation

/// One Linux VM. Self-contained in a folder under
/// ~/Library/Application Support/LinuxVM/VMs/<uuid>/. A local VM boots via
/// Virtualization.framework on this Mac; a VM with a `hostID` lives on a remote
/// libvirt host and the folder holds only metadata.
final class VMRecord: Identifiable, ObservableObject, Codable {
    let id: UUID
    @Published var name: String
    let distroID: String
    let distroName: String

    @Published var cpuCount: Int
    @Published var memoryBytes: UInt64
    let diskSizeBytes: UInt64

    let macAddress: String
    /// DHCP/cloud-init hostname; also how we find the VM's IP for local stats
    /// and the libvirt domain name for remote VMs.
    let hostname: String
    /// The login user provisioned into this VM (used for SSH stats).
    let username: String
    /// Whether the enhanced developer toolchain was provisioned.
    let enhanced: Bool
    /// nil = local (this Mac); otherwise the id of a remote libvirt host.
    let hostID: String?
    let createdAt: Date

    var directoryURL: URL = URL(fileURLWithPath: "/")   // set on load; not persisted

    var isRemote: Bool { hostID != nil }

    init(id: UUID = UUID(), name: String, distroID: String, distroName: String,
         cpuCount: Int, memoryBytes: UInt64, diskSizeBytes: UInt64,
         macAddress: String, hostname: String, username: String,
         enhanced: Bool = false, hostID: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.distroID = distroID
        self.distroName = distroName
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.diskSizeBytes = diskSizeBytes
        self.macAddress = macAddress
        self.hostname = hostname
        self.username = username
        self.enhanced = enhanced
        self.hostID = hostID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, distroID, distroName, cpuCount, memoryBytes
        case diskSizeBytes, macAddress, hostname, username, enhanced, hostID, createdAt
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            distroID: try c.decode(String.self, forKey: .distroID),
            distroName: try c.decode(String.self, forKey: .distroName),
            cpuCount: try c.decode(Int.self, forKey: .cpuCount),
            memoryBytes: try c.decode(UInt64.self, forKey: .memoryBytes),
            diskSizeBytes: try c.decode(UInt64.self, forKey: .diskSizeBytes),
            macAddress: try c.decode(String.self, forKey: .macAddress),
            hostname: try c.decode(String.self, forKey: .hostname),
            username: try c.decode(String.self, forKey: .username),
            enhanced: try c.decodeIfPresent(Bool.self, forKey: .enhanced) ?? false,
            hostID: try c.decodeIfPresent(String.self, forKey: .hostID),
            createdAt: try c.decode(Date.self, forKey: .createdAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(distroID, forKey: .distroID)
        try c.encode(distroName, forKey: .distroName)
        try c.encode(cpuCount, forKey: .cpuCount)
        try c.encode(memoryBytes, forKey: .memoryBytes)
        try c.encode(diskSizeBytes, forKey: .diskSizeBytes)
        try c.encode(macAddress, forKey: .macAddress)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(username, forKey: .username)
        try c.encode(enhanced, forKey: .enhanced)
        try c.encodeIfPresent(hostID, forKey: .hostID)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // On-disk layout.
    var configURL: URL { directoryURL.appendingPathComponent("config.json") }
    var diskImageURL: URL { directoryURL.appendingPathComponent("disk.img") }
    var seedISOURL: URL { directoryURL.appendingPathComponent("seed.iso") }
    var efiVariableStoreURL: URL { directoryURL.appendingPathComponent("efivars.fd") }
    var machineIdentifierURL: URL { directoryURL.appendingPathComponent("machineid.dat") }
    var sharedFolderURL: URL { directoryURL.appendingPathComponent("shared") }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: configURL, options: .atomic)
    }

    // UI helpers.
    var memoryGB: Double { Double(memoryBytes) / 1_073_741_824.0 }
    var diskGB: Double { Double(diskSizeBytes) / 1_073_741_824.0 }

    /// Actual space the sparse disk image occupies on the Mac right now (local only).
    var diskAllocatedBytes: UInt64 {
        let values = try? diskImageURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return UInt64(values?.totalFileAllocatedSize ?? 0)
    }
}
