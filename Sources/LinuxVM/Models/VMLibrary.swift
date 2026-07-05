import Foundation
import Combine

/// Owns every VM on disk plus the live `VMInstance` for any that are running.
/// VMs live either in the default base directory or in custom locations the
/// user picks; custom locations are tracked in an index so they can be found
/// again on the next launch.
@MainActor
final class VMLibrary: ObservableObject {
    @Published private(set) var vms: [VMRecord] = []
    /// Live instances keyed by VM id. Deliberately *not* @Published: it is
    /// populated lazily from inside `body`, and publishing there would trigger
    /// "modifying state during view update". Views observe each `VMInstance`.
    private var instances: [UUID: VMInstance] = [:]

    /// Directories of VMs stored outside the default base.
    private var externalLocations: [URL] = []

    static let baseDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("LinuxVM", isDirectory: true)
            .appendingPathComponent("VMs", isDirectory: true)
    }()

    private static var indexURL: URL {
        baseDirectory.deletingLastPathComponent().appendingPathComponent("locations.json")
    }

    init() {
        try? FileManager.default.createDirectory(at: Self.baseDirectory, withIntermediateDirectories: true)
        load()
    }

    func load() {
        var loaded: [VMRecord] = []
        // Default base directory.
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: Self.baseDirectory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for dir in entries where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let r = loadRecord(at: dir) { loaded.append(r) }
            }
        }
        // Custom locations (may be on unmounted drives — skip silently if absent).
        externalLocations = readIndex()
        for dir in externalLocations {
            if let r = loadRecord(at: dir) { loaded.append(r) }
        }
        // De-dupe by id, keep first seen.
        var seen = Set<UUID>()
        vms = loaded.filter { seen.insert($0.id).inserted }.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadRecord(at dir: URL) -> VMRecord? {
        let configURL = dir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let record = try? JSONDecoder().decode(VMRecord.self, from: data) else { return nil }
        record.directoryURL = dir
        return record
    }

    /// Allocate a fresh VM folder, optionally under a custom parent directory.
    func makeDirectory(for id: UUID, in parent: URL? = nil) throws -> URL {
        let parentDir = parent ?? Self.baseDirectory
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let dir = parentDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Persist a fully-prepared record and add it to the library.
    func register(_ record: VMRecord) throws {
        try FileManager.default.createDirectory(at: record.sharedFolderURL, withIntermediateDirectories: true)
        try record.save()
        if !isUnderDefaultBase(record.directoryURL),
           !externalLocations.contains(where: { $0.standardizedFileURL == record.directoryURL.standardizedFileURL }) {
            externalLocations.append(record.directoryURL)
            writeIndex()
        }
        vms.append(record)
        vms.sort { $0.createdAt < $1.createdAt }
    }

    func instance(for record: VMRecord) -> VMInstance {
        if let existing = instances[record.id] { return existing }
        let inst = VMInstance(record: record)
        instances[record.id] = inst
        return inst
    }

    func isRunning(_ record: VMRecord) -> Bool {
        instances[record.id]?.runState.isActive ?? false
    }

    func delete(_ record: VMRecord) {
        if let inst = instances[record.id] {
            inst.forceStopForDeletion()
            instances[record.id] = nil
        }
        try? FileManager.default.removeItem(at: record.directoryURL)
        externalLocations.removeAll { $0.standardizedFileURL == record.directoryURL.standardizedFileURL }
        writeIndex()
        vms.removeAll { $0.id == record.id }
    }

    func persist(_ record: VMRecord) {
        try? record.save()
        objectWillChange.send()
    }

    // MARK: - Helpers

    private func isUnderDefaultBase(_ dir: URL) -> Bool {
        dir.deletingLastPathComponent().standardizedFileURL == Self.baseDirectory.standardizedFileURL
    }

    private func readIndex() -> [URL] {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private func writeIndex() {
        let paths = externalLocations.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }
}
