import SwiftUI

/// Accent color per distro family.
func distroAccent(_ distroID: String) -> Color {
    if distroID.hasPrefix("debian") { return Color(red: 0.84, green: 0.10, blue: 0.32) }
    if distroID.hasPrefix("ubuntu") { return Color(red: 0.90, green: 0.36, blue: 0.16) }
    if distroID.hasPrefix("fedora") { return Color(red: 0.20, green: 0.40, blue: 0.74) }
    return .indigo
}

struct VMCard: View {
    @ObservedObject var record: VMRecord
    @ObservedObject var instance: VMInstance
    @EnvironmentObject var theme: ThemeManager
    var onOpenConsole: () -> Void
    var onDelete: () -> Void

    @State private var copied = false

    private var accent: Color { distroAccent(record.distroID) }
    private var running: Bool { instance.runState == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statsArea
            Divider().opacity(0.35)
            footer
            actions
        }
        .padding(16)
        .background(theme.current.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.current.border.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 12) {
            DistroLogo(distroID: record.distroID, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(record.name).font(.headline).lineLimit(1)
                    if record.enhanced {
                        Image(systemName: "wand.and.stars")
                            .font(.caption2).foregroundStyle(.purple)
                            .help("Enhanced developer setup")
                    }
                }
                Text(record.distroName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusPill(state: instance.runState)
        }
    }

    @ViewBuilder private var statsArea: some View {
        let s = instance.stats
        HStack(alignment: .top, spacing: 18) {
            RingGauge(
                fraction: (s?.cpuPercent ?? 0) / 100,
                centerText: running ? (s.map { "\(Int($0.cpuPercent))%" } ?? "··") : "—",
                caption: "CPU · \(record.cpuCount) cores",
                active: running && s != nil
            )
            VStack(spacing: 10) {
                BarStat(label: "Memory", fraction: memFraction(s),
                        detail: memDetail(s), active: running && s != nil)
                VStack(spacing: 5) {
                    BarStat(
                        label: "Disk",
                        fraction: Double(record.diskAllocatedBytes) / Double(max(record.diskSizeBytes, 1)),
                        detail: "\(Format.bytes(record.diskAllocatedBytes)) / \(Format.bytes(record.diskSizeBytes))",
                        active: true, tint: accent)
                    ioRow(s)
                }
            }
        }
    }

    @ViewBuilder private func ioRow(_ s: GuestSample?) -> some View {
        HStack(spacing: 12) {
            Label(running ? Format.rate(s?.diskReadBytesPerSec ?? 0) : "—", systemImage: "arrow.down")
            Label(running ? Format.rate(s?.diskWriteBytesPerSec ?? 0) : "—", systemImage: "arrow.up")
            Spacer()
            Text("disk I/O").foregroundStyle(.tertiary)
        }
        .font(.caption2).monospacedDigit()
        .foregroundStyle(running && s != nil ? .secondary : .tertiary)
        .labelStyle(.titleAndIcon)
    }

    private func memFraction(_ s: GuestSample?) -> Double {
        guard let s, s.memTotalBytes > 0 else { return 0 }
        return Double(s.memUsedBytes) / Double(s.memTotalBytes)
    }
    private func memDetail(_ s: GuestSample?) -> String {
        if let s, s.memTotalBytes > 0 {
            return "\(Format.bytes(s.memUsedBytes)) / \(Format.bytes(s.memTotalBytes))"
        }
        return "\(Format.bytes(record.memoryBytes)) allocated"
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                if running {
                    Label(Format.uptime(since: instance.startedAt), systemImage: "clock")
                    if let ip = instance.ipAddress {
                        Label(ip, systemImage: "network")
                    } else {
                        Label("getting IP…", systemImage: "network").foregroundStyle(.tertiary)
                    }
                } else {
                    Label("\(record.cpuCount) vCPU", systemImage: "cpu")
                    Label(Format.bytes(record.memoryBytes), systemImage: "memorychip")
                }
                Spacer()
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            switch instance.runState {
            case .stopped, .error:
                Button { instance.start() } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(accent)
            case .running:
                Button { onOpenConsole() } label: { Label("Console", systemImage: "terminal") }
                    .controlSize(.small)
                Button { copySSH() } label: {
                    Label(copied ? "Copied" : "Copy ssh",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small).disabled(instance.ipAddress == nil)
                Menu {
                    Button("Shut Down") { instance.requestStop() }
                    Button("Force Stop", role: .destructive) { instance.forceStop() }
                } label: { Label("Stop", systemImage: "stop.fill") }
                    .menuStyle(.button).controlSize(.small).fixedSize()
            default:
                ProgressView().controlSize(.small)
            }
            Spacer()
            Menu {
                Button("Delete VM…", role: .destructive) { onDelete() }
                    .disabled(instance.runState.isActive)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func copySSH() {
        let host = instance.ipAddress ?? record.hostname
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(record.username)@\(host)", forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}
