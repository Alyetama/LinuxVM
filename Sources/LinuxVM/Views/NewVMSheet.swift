import SwiftUI
import Virtualization
import UniformTypeIdentifiers

struct NewVMSheet: View {
    @EnvironmentObject var library: VMLibrary
    @EnvironmentObject var creds: CredentialsStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DefaultsKey.cpu) private var defaultCPU = 2
    @AppStorage(DefaultsKey.memGB) private var defaultMemGB = 4
    @AppStorage(DefaultsKey.diskGB) private var defaultDiskGB = 32
    @AppStorage(DefaultsKey.location) private var defaultLocation = ""

    @State private var name = ""
    @State private var distroID = DistroCatalog.all.first!.id
    @State private var cpu = 2
    @State private var memoryGB = 4
    @State private var diskGB = 32
    @State private var enhanced = false
    @State private var customLocation: URL?
    @State private var showingFolderPicker = false
    @State private var seeded = false

    @StateObject private var downloader = ISODownloader()
    @State private var creating = false
    @State private var statusText = ""
    @State private var errorText: String?

    private var distro: Distro { DistroCatalog.distro(withID: distroID) ?? DistroCatalog.all[0] }
    private var qemuMissing: Bool { distro.needsQemu && !Shell.hasQemuImg }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name") {
                        TextField("e.g. dev-box", text: $name).textFieldStyle(.roundedBorder)
                    }
                    field("Distribution") {
                        Picker("", selection: $distroID) {
                            ForEach(DistroCatalog.all) { Text($0.name).tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu)
                        Text(distro.blurb).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if qemuMissing { qemuWarning }
                    }
                    field("Resources") {
                        Stepper("CPU cores: \(cpu)", value: $cpu, in: VMLimits.minCPU...VMLimits.maxCPU)
                        Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...VMLimits.maxMemoryGB)
                        Stepper("Disk: \(diskGB) GB", value: $diskGB, in: 8...512, step: 8)
                    }
                    enhancedSection
                    storageSection
                    credInfo
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 620)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            cpu = VMLimits.clampCPU(defaultCPU)
            memoryGB = VMLimits.clampMemoryGB(defaultMemGB)
            diskGB = max(8, defaultDiskGB)
            if !defaultLocation.isEmpty {
                customLocation = URL(fileURLWithPath: defaultLocation, isDirectory: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").font(.system(size: 24)).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text("New Linux VM").font(.title2.bold())
                Text("Installs and configures itself automatically — no setup steps.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(20)
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private var qemuWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This distro needs a one-time setup.").font(.callout.weight(.medium))
                Text("Run `brew install qemu` in Terminal, then reopen this sheet. Or pick Debian, which needs nothing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var storageSection: some View {
        field("Storage location") {
            HStack(spacing: 8) {
                Image(systemName: customLocation == nil ? "internaldrive" : "externaldrive")
                    .foregroundStyle(.secondary)
                Text(customLocation?.path ?? "Default (Application Support)")
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(customLocation == nil ? .secondary : .primary)
                Spacer()
                Button("Choose…") { showingFolderPicker = true }
                if customLocation != nil {
                    Button("Default") { customLocation = nil }
                }
            }
            Text("Where this VM's disk and config are stored. Pick an external drive to keep large disks off your boot volume.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { customLocation = url }
        }
    }

    private var enhancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enhanced) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enhanced developer setup").font(.headline)
                    Text("Pre-install a full dev toolchain on first boot.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if enhanced {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Oh My Zsh (Spaceship prompt, zsh-z, autosuggestions, syntax highlighting) + Oh My Tmux",
                          systemImage: "terminal")
                    Label("Docker & Compose · Miniforge (conda)", systemImage: "shippingbox")
                    Label("ripgrep · fd · bat · git · curl · wget · zip/unzip · build tools",
                          systemImage: "wrench.and.screwdriver")
                    Label("Adds a few minutes to first boot (installs in the background).",
                          systemImage: "clock")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var credInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            Text("Login: ") + Text(creds.username).bold() + Text(" / password from Settings")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            // Fixed-width status area so ticking numbers never reflow the buttons.
            statusArea
                .frame(width: 280, alignment: .leading)
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) {
                if creating { downloader.cancel() } else { dismiss() }
            }
            Button("Create & Start") { Task { await create() } }
                .keyboardShortcut(.defaultAction)
                .disabled(creating || qemuMissing)
        }
        .frame(height: 28)
        .padding(20)
    }

    @ViewBuilder private var statusArea: some View {
        if creating {
            HStack(spacing: 10) {
                if downloader.state == .downloading && downloader.totalBytes > 0 {
                    ProgressView(value: downloader.fractionCompleted)
                        .frame(width: 130)
                    Text(downloadLabel)
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                } else {
                    ProgressView().controlSize(.small)
                    Text(statusText)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Compact, fixed-unit progress (e.g. "580 / 615 MB"). Stays in MB the whole
    /// download so the unit never changes width mid-transfer.
    private var downloadLabel: String {
        let mb = 1_000_000.0
        let r = Int((Double(downloader.receivedBytes) / mb).rounded())
        let t = Int((Double(downloader.totalBytes) / mb).rounded())
        return "\(r) / \(t) MB"
    }

    private func create() async {
        errorText = nil
        creating = true
        let id = UUID()
        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? distro.name : name
        var createdDir: URL?
        do {
            let dir = try library.makeDirectory(for: id, in: customLocation)
            createdDir = dir
            let hostname = CloudInit.hostname(for: displayName, id: id)

            try await ImagePreparer.prepare(
                distro: distro, diskURL: dir.appendingPathComponent("disk.img"),
                sizeBytes: UInt64(diskGB) * VMLimits.gb, downloader: downloader,
                onPhase: { phase in
                    statusText = ["downloading": "Downloading…", "converting": "Converting image…",
                                  "finalizing": "Preparing disk…"]["\(phase)"] ?? "Working…"
                })

            statusText = "Configuring…"
            let seedOK = CloudInit.buildSeed(
                at: dir.appendingPathComponent("seed.iso"),
                username: creds.username, password: creds.password,
                publicKey: creds.ensureSSHKey(), hostname: hostname,
                instanceID: id, enhanced: enhanced)
            guard seedOK else { throw VMError.configurationInvalid("Could not build the cloud-init seed.") }

            let record = VMRecord(
                id: id, name: displayName, distroID: distro.id, distroName: distro.name,
                cpuCount: cpu, memoryBytes: UInt64(memoryGB) * VMLimits.gb,
                diskSizeBytes: UInt64(diskGB) * VMLimits.gb,
                macAddress: VZMACAddress.randomLocallyAdministered().string,
                hostname: hostname, username: creds.username, enhanced: enhanced)
            record.directoryURL = dir
            try library.register(record)

            statusText = "Booting…"
            library.instance(for: record).start()

            creating = false
            dismiss()
        } catch is CancellationError {
            if let d = createdDir { try? FileManager.default.removeItem(at: d) }
            creating = false; statusText = ""
        } catch {
            errorText = error.localizedDescription
            if let d = createdDir { try? FileManager.default.removeItem(at: d) }
            creating = false; statusText = ""
        }
    }
}
