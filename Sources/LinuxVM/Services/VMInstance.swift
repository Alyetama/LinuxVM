import Foundation
import Virtualization

/// Wraps one `VZVirtualMachine`: builds its configuration, starts/stops it,
/// and polls live stats over SSH. Main-actor isolated because
/// Virtualization.framework requires VM access on the queue it was created on.
@MainActor
final class VMInstance: NSObject, ObservableObject, VZVirtualMachineDelegate {
    enum RunState: Equatable {
        case stopped, starting, running, stopping
        case error(String)

        var isActive: Bool {
            switch self { case .starting, .running, .stopping: return true; default: return false }
        }
        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case .running: return "Running"
            case .stopping: return "Stopping…"
            case .error(let m): return "Error: \(m)"
            }
        }
    }

    let record: VMRecord
    @Published private(set) var runState: RunState = .stopped
    @Published private(set) var vm: VZVirtualMachine?
    @Published private(set) var stats: GuestSample?
    @Published private(set) var ipAddress: String?
    @Published private(set) var startedAt: Date?

    private var statsTask: Task<Void, Never>?

    init(record: VMRecord) {
        self.record = record
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard !runState.isActive else { return }
        runState = .starting
        do {
            let config = try buildConfiguration()
            let machine = VZVirtualMachine(configuration: config)
            machine.delegate = self
            self.vm = machine
            machine.start { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.runState = .running
                        self.startedAt = Date()
                        self.startStatsPolling()
                    case .failure(let error):
                        self.runState = .error(error.localizedDescription)
                    }
                }
            }
        } catch {
            runState = .error(error.localizedDescription)
            vm = nil
        }
    }

    func requestStop() {
        guard let vm, runState == .running else { return }
        runState = .stopping
        if vm.canRequestStop, (try? vm.requestStop()) != nil { return }
        forceStop()
    }

    func forceStop() {
        guard let vm, runState.isActive else { return }
        runState = .stopping
        vm.stop { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.runState = error.map { .error($0.localizedDescription) } ?? .stopped
                self.teardown()
            }
        }
    }

    func forceStopForDeletion() {
        statsTask?.cancel()
        vm?.stop(completionHandler: { _ in })
        vm = nil
        runState = .stopped
    }

    private func teardown() {
        statsTask?.cancel(); statsTask = nil
        vm = nil
        stats = nil
        ipAddress = nil
        startedAt = nil
    }

    // MARK: - VZVirtualMachineDelegate

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        runState = .stopped
        teardown()
    }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        runState = .error(error.localizedDescription)
        teardown()
    }

    // MARK: - Live stats

    private func startStatsPolling() {
        statsTask?.cancel()
        let mac = record.macAddress
        let user = record.username
        let key = CredentialsStore.sshPrivateKeyPath
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let sample = await Task.detached(priority: .utility) { () -> GuestSample? in
                    guard let ip = GuestStats.discoverIP(mac: mac) else { return nil }
                    return GuestStats.sample(ip: ip, user: user, keyPath: key)
                }.value
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    guard let self, self.runState == .running else { return }
                    if let sample { self.stats = sample; self.ipAddress = sample.ip }
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    // MARK: - Configuration

    private func buildConfiguration() throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        config.cpuCount = record.cpuCount
        config.memorySize = record.memoryBytes
        config.platform = try buildPlatform()
        config.bootLoader = try buildBootLoader()
        config.graphicsDevices = [makeGraphics()]
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        config.storageDevices = try buildStorage()
        config.networkDevices = [makeNetwork()]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        // No serial console: a virtio console makes some installers/gettys grab
        // it; the graphical display is the only console we want.
        if let fs = try makeSharedFolder() { config.directorySharingDevices = [fs] }

        do { try config.validate() }
        catch { throw VMError.configurationInvalid(error.localizedDescription) }
        return config
    }

    private func buildPlatform() throws -> VZGenericPlatformConfiguration {
        let platform = VZGenericPlatformConfiguration()
        if let data = try? Data(contentsOf: record.machineIdentifierURL),
           let id = VZGenericMachineIdentifier(dataRepresentation: data) {
            platform.machineIdentifier = id
        } else {
            let id = VZGenericMachineIdentifier()
            try? id.dataRepresentation.write(to: record.machineIdentifierURL)
            platform.machineIdentifier = id
        }
        return platform
    }

    private func buildBootLoader() throws -> VZEFIBootLoader {
        let loader = VZEFIBootLoader()
        if FileManager.default.fileExists(atPath: record.efiVariableStoreURL.path) {
            loader.variableStore = VZEFIVariableStore(url: record.efiVariableStoreURL)
        } else {
            loader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: record.efiVariableStoreURL)
        }
        return loader
    }

    private func makeGraphics() -> VZVirtioGraphicsDeviceConfiguration {
        let gpu = VZVirtioGraphicsDeviceConfiguration()
        gpu.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 800)]
        return gpu
    }

    private func buildStorage() throws -> [VZStorageDeviceConfiguration] {
        var devices: [VZStorageDeviceConfiguration] = []
        let disk = try VZDiskImageStorageDeviceAttachment(url: record.diskImageURL, readOnly: false)
        devices.append(VZVirtioBlockDeviceConfiguration(attachment: disk))
        if FileManager.default.fileExists(atPath: record.seedISOURL.path) {
            let seed = try VZDiskImageStorageDeviceAttachment(url: record.seedISOURL, readOnly: true)
            devices.append(VZVirtioBlockDeviceConfiguration(attachment: seed))
        }
        return devices
    }

    private func makeNetwork() -> VZVirtioNetworkDeviceConfiguration {
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        if let mac = VZMACAddress(string: record.macAddress) { net.macAddress = mac }
        return net
    }

    private func makeSharedFolder() throws -> VZVirtioFileSystemDeviceConfiguration? {
        try? FileManager.default.createDirectory(at: record.sharedFolderURL, withIntermediateDirectories: true)
        let tag = "share"
        guard (try? VZVirtioFileSystemDeviceConfiguration.validateTag(tag)) != nil else { return nil }
        let device = VZVirtioFileSystemDeviceConfiguration(tag: tag)
        device.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: record.sharedFolderURL, readOnly: false))
        return device
    }
}
