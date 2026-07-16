import SwiftUI
import UniformTypeIdentifiers

/// Default resources for newly created VMs, shared with the New VM sheet.
enum DefaultsKey {
    static let cpu = "defaultCPU"
    static let memGB = "defaultMemGB"
    static let diskGB = "defaultDiskGB"
    /// Absolute path of the default parent folder for new VMs; "" = app default.
    static let location = "defaultStorageLocation"
}

/// Proper macOS Settings window (⌘,) with tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            CredentialsSettingsTab()
                .tabItem { Label("Credentials", systemImage: "key.fill") }
            HostsSettingsTab()
                .tabItem { Label("Remote Hosts", systemImage: "server.rack") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 460)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(DefaultsKey.cpu) private var cpu = 2
    @AppStorage(DefaultsKey.memGB) private var memGB = 4
    @AppStorage(DefaultsKey.diskGB) private var diskGB = 32
    @AppStorage(DefaultsKey.location) private var location = ""
    @State private var showingPicker = false

    var body: some View {
        Form {
            Section("Defaults for new VMs") {
                Stepper("CPU cores: \(cpu)", value: $cpu, in: VMLimits.minCPU...VMLimits.maxCPU)
                Stepper("Memory: \(memGB) GB", value: $memGB, in: 1...VMLimits.maxMemoryGB)
                Stepper("Disk: \(diskGB) GB", value: $diskGB, in: 8...512, step: 8)
            }
            Section("Default storage location") {
                LabeledContent("Folder") {
                    Text(location.isEmpty ? "Application Support (default)" : location)
                        .foregroundStyle(location.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Choose…") { showingPicker = true }
                    if !location.isEmpty { Button("Reset to Default") { location = "" } }
                }
                Text("New VMs are stored here unless you override it when creating one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Image conversion") {
                LabeledContent("qemu-img") {
                    if Shell.hasQemuImg {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Needed for Ubuntu/Fedora. Run: brew install qemu")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Debian images need no conversion and work without qemu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { location = url.path }
        }
    }
}

private struct CredentialsSettingsTab: View {
    @EnvironmentObject var creds: CredentialsStore
    @State private var reveal = false

    var body: some View {
        Form {
            Section("Default login (applied to new VMs)") {
                TextField("Username", text: $creds.username)
                HStack {
                    Group {
                        if reveal { TextField("Password", text: $creds.password) }
                        else { SecureField("Password", text: $creds.password) }
                    }
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                    Button { copySecret(creds.password) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy password (marked private so clipboard managers skip it)")
                }
                if !CredentialsStore.isValidUsername(creds.username) {
                    Label("Username must be lowercase, start with a letter, and use only a–z, 0–9, _ or -",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Save") { creds.save() }
                    .disabled(!CredentialsStore.isValidUsername(creds.username) || creds.password.isEmpty)
            }
            Section("SSH key (for reading live stats)") {
                Text("The app authorizes this key in every VM so it can read CPU, memory, and disk usage over SSH.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy Public Key") { copy(creds.publicKey ?? "") }
                    .disabled(creds.publicKey == nil)
            }
            Text("Existing VMs keep the credentials they were created with.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        // Never leave the password revealed once you leave this tab/window.
        .onDisappear { reveal = false }
    }

    /// Plain copy for non-secret values (e.g. the SSH public key).
    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// Copy a secret, marked with the nspasteboard "concealed" type so
    /// well-behaved clipboard managers don't store it in their history.
    private func copySecret(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pb.declareTypes([.string, concealed], owner: nil)
        pb.setString(s, forType: .string)
        pb.setString("", forType: concealed)
    }
}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject var themeManager: ThemeManager
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme").font(.headline)
                Text("Pick a color scheme for the app.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ThemeCatalog.all) { theme in
                        ThemeSwatch(theme: theme, selected: theme.id == themeManager.current.id)
                            .onTapGesture { themeManager.select(theme) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.isSystem ? AnyShapeStyle(.background) : AnyShapeStyle(theme.background))
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.isSystem ? AnyShapeStyle(.quaternary) : AnyShapeStyle(theme.surface))
                        .frame(height: 26)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 5) {
                                Circle().fill(theme.accent).frame(width: 9, height: 9)
                                Capsule().fill(.secondary.opacity(0.5)).frame(width: 34, height: 5)
                            }.padding(.leading, 7)
                        }
                    HStack(spacing: 5) {
                        Capsule().fill(theme.accent).frame(width: 30, height: 7)
                        Capsule().fill(.secondary.opacity(0.4)).frame(width: 18, height: 7)
                        Spacer()
                    }
                }
                .padding(10)
            }
            .frame(height: 78)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(selected ? theme.accent : Color.secondary.opacity(0.25),
                                  lineWidth: selected ? 2.5 : 1)
            )
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent).font(.caption2) }
                Text(theme.name).font(.caption).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            DistroLogo(distroID: "", size: 64)
            Text("Linux VM").font(.title2.bold())
            Text("Version 1.0").font(.callout).foregroundStyle(.secondary)
            Text("Create isolated Linux VMs on Apple Silicon that install and configure themselves automatically via cloud-init.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Text("VMs are stored in ~/Library/Application Support/LinuxVM")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct HostsSettingsTab: View {
    @EnvironmentObject var hostStore: HostStore
    @State private var name = ""
    @State private var user = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var testing = false
    @State private var testResult: String?

    private var canAdd: Bool {
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Hosts") {
                if hostStore.hosts.isEmpty {
                    Text("No remote hosts yet.").foregroundStyle(.secondary)
                }
                ForEach(hostStore.hosts) { h in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.name.isEmpty ? h.sshTarget : h.name)
                            Text("\(h.sshTarget):\(h.port)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { hostStore.remove(h) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Add a libvirt host") {
                TextField("Label (optional)", text: $name)
                TextField("SSH user", text: $user)
                TextField("Host / IP", text: $host)
                TextField("Port", text: $port).frame(width: 90)
                HStack {
                    Button("Test") { Task { await test() } }
                        .disabled(!canAdd || testing)
                    Button("Add") {
                        hostStore.add(RemoteHost(name: name, user: user, host: host,
                                                 port: Int(port) ?? 22))
                        name = ""; user = ""; host = ""; port = "22"; testResult = nil
                    }.disabled(!canAdd)
                    if testing { ProgressView().controlSize(.small) }
                }
                if let testResult {
                    Text(testResult).font(.caption)
                        .foregroundStyle(testResult.hasPrefix("OK") ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("The host needs libvirt, virtinst, qemu-utils, and your SSH public key (Credentials → Copy Public Key) in its authorized_keys.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
    }

    private func test() async {
        testing = true; testResult = nil
        let h = RemoteHost(name: name, user: user, host: host, port: Int(port) ?? 22)
        let result = await Task.detached { RemoteBackend.test(h) }.value
        testing = false
        testResult = (result.ok ? "OK — " : "") + result.message
    }
}
