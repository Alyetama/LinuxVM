import Foundation

/// Turns a downloaded cloud image into a ready-to-boot raw disk of the requested
/// size: download → (convert qcow2→raw) → grow (cloud-init expands the FS on boot).
enum ImagePreparer {
    enum Phase: Equatable { case downloading, converting, finalizing }

    static func prepare(distro: Distro, diskURL: URL, sizeBytes: UInt64,
                        downloader: ISODownloader,
                        onPhase: @escaping (Phase) -> Void) async throws {
        let fm = FileManager.default
        let workDir = diskURL.deletingLastPathComponent()
        let download = workDir.appendingPathComponent("image.download")

        onPhase(.downloading)
        try await downloader.download(from: distro.imageURL, to: download)

        switch distro.format {
        case .raw:
            try? fm.removeItem(at: diskURL)
            try fm.moveItem(at: download, to: diskURL)
        case .qcow2:
            onPhase(.converting)
            guard let qemu = Shell.qemuImg else {
                try? fm.removeItem(at: download)
                throw VMError.configurationInvalid(
                    "\(distro.name) needs qemu-img. Install it once with: brew install qemu")
            }
            try? fm.removeItem(at: diskURL)
            let r = Shell.run(qemu, ["convert", "-O", "raw", download.path, diskURL.path])
            try? fm.removeItem(at: download)
            guard r.ok else {
                throw VMError.diskCreationFailed("qemu-img convert failed: \(r.stderr)")
            }
        }

        onPhase(.finalizing)
        try grow(diskURL, to: sizeBytes)
    }

    /// Grows the raw image to `target` (never shrinks below the image's own size).
    private static func grow(_ url: URL, to target: UInt64) throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let current = (attrs?[.size] as? UInt64) ?? 0
        let final = max(target, current)
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: final)
        } catch {
            throw VMError.diskCreationFailed(error.localizedDescription)
        }
    }
}
