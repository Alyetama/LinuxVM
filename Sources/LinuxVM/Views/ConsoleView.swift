import SwiftUI

/// The VM's live graphical console, shown in a sheet. Optional — the VM runs
/// headless and self-configures; this is for when you want a terminal on it.
struct ConsoleView: View {
    @ObservedObject var record: VMRecord
    @ObservedObject var instance: VMInstance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let vm = instance.vm {
                    VirtualMachineDisplayView(vm: vm)
                } else {
                    placeholder
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(record.name).font(.headline)
            StatusPill(state: instance.runState)
            if let s = instance.stats {
                Text("CPU \(Int(s.cpuPercent))%  ·  RAM \(Format.bytes(s.memUsedBytes))/\(Format.bytes(s.memTotalBytes))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Text("Log in as \(record.username)").font(.caption).foregroundStyle(.tertiary)
            if instance.runState == .running {
                Button { instance.requestStop() } label: { Label("Shut Down", systemImage: "power") }
                    .controlSize(.small)
            }
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "display").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text(instance.runState.label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
