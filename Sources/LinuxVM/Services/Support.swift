import Foundation

enum VMError: LocalizedError {
    case diskCreationFailed(String)
    case missingISO
    case configurationInvalid(String)

    var errorDescription: String? {
        switch self {
        case .diskCreationFailed(let m): return "Could not create the disk image: \(m)"
        case .missingISO: return "The installer ISO for this VM is missing."
        case .configurationInvalid(let m): return "Invalid VM configuration: \(m)"
        }
    }
}

/// Creates a sparse raw disk image. The file reports the full size but only
/// consumes blocks as the guest writes to them.
enum DiskImage {
    static func create(at url: URL, sizeBytes: UInt64) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw VMError.diskCreationFailed("could not create \(url.lastPathComponent)")
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: sizeBytes)
        } catch {
            throw VMError.diskCreationFailed(error.localizedDescription)
        }
    }
}

extension ByteCountFormatter {
    static func human(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        // .binary (1024-base) so a 4 GiB allocation reads "4 GB", not "4.29 GB".
        f.countStyle = .binary
        return f.string(fromByteCount: bytes)
    }
}
