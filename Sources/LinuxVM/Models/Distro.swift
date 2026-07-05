import Foundation

enum DiskFormat: String, Codable { case raw, qcow2 }

/// A selectable Linux distribution, as a cloud image that self-configures via
/// cloud-init on first boot (no installer). ARM64/aarch64 to match Apple Silicon.
struct Distro: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let imageURL: URL
    let format: DiskFormat
    let approxSizeMB: Int

    /// qcow2 images require qemu-img to convert to the raw format VZ needs.
    var needsQemu: Bool { format == .qcow2 }

    init(id: String, name: String, blurb: String, image: String, format: DiskFormat, approxSizeMB: Int) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.imageURL = URL(string: image)!
        self.format = format
        self.approxSizeMB = approxSizeMB
    }
}

enum DistroCatalog {
    /// ARM64 cloud images, verified June 2026. Debian ships raw (zero setup);
    /// Ubuntu/Fedora ship qcow2 (need a one-time `brew install qemu`).
    static let all: [Distro] = [
        Distro(id: "debian-13", name: "Debian 13 (Trixie)",
               blurb: "Recommended — works with zero setup. Boots in seconds, self-configures.",
               image: "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.raw",
               format: .raw, approxSizeMB: 350),
        Distro(id: "debian-12", name: "Debian 12 (Bookworm)",
               blurb: "Previous stable. Zero setup (raw image).",
               image: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.raw",
               format: .raw, approxSizeMB: 320),
        Distro(id: "ubuntu-24.04", name: "Ubuntu Server 24.04 LTS",
               blurb: "Most popular. qcow2 image — needs a one-time `brew install qemu`.",
               image: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img",
               format: .qcow2, approxSizeMB: 600),
        Distro(id: "fedora-42", name: "Fedora 42",
               blurb: "Red Hat family. qcow2 image — needs a one-time `brew install qemu`.",
               image: "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-42-1.1.aarch64.qcow2",
               format: .qcow2, approxSizeMB: 550)
    ]

    static func distro(withID id: String) -> Distro? { all.first { $0.id == id } }
}
