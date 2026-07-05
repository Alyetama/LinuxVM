import SwiftUI

/// Color ramp for a utilization fraction (0–1): green → orange → red.
func utilizationColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.6: return .green
    case ..<0.85: return .orange
    default: return .red
    }
}

/// Circular progress ring with a centered value, used for CPU%.
struct RingGauge: View {
    var fraction: Double          // 0...1
    var centerText: String
    var caption: String
    var size: CGFloat = 76
    var active: Bool = true

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: active ? clamped : 0)
                    .stroke(active ? utilizationColor(clamped) : Color.secondary,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: clamped)
                VStack(spacing: 0) {
                    Text(centerText)
                        .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(active ? .primary : .secondary)
                }
            }
            .frame(width: size, height: size)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Horizontal usage bar with a label and a trailing detail, used for RAM/disk.
struct BarStat: View {
    var label: String
    var fraction: Double
    var detail: String
    var active: Bool = true
    var tint: Color? = nil

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(detail).font(.caption).monospacedDigit().foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(active ? (tint ?? utilizationColor(clamped)) : Color.secondary.opacity(0.5))
                        .frame(width: max(4, geo.size.width * clamped))
                        .animation(.easeOut(duration: 0.5), value: clamped)
                }
            }
            .frame(height: 7)
        }
    }
}

/// Status pill (Running / Stopped / Booting / Error).
struct StatusPill: View {
    let state: VMInstance.RunState

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped: return .secondary
        }
    }
    private var text: String {
        switch state {
        case .running: return "Running"
        case .starting: return "Booting"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .error: return "Error"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

enum Format {
    static func bytes(_ b: UInt64) -> String { ByteCountFormatter.human(Int64(b)) }

    static func rate(_ bytesPerSec: UInt64) -> String {
        if bytesPerSec < 1024 { return "\(bytesPerSec) B/s" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = bytesPerSec < 1_000_000 ? [.useKB] : [.useMB]
        return f.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }

    static func uptime(since start: Date?) -> String {
        guard let start else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m \(s%60)s" }
        let h = s/3600, m = (s%3600)/60
        return "\(h)h \(m)m"
    }
}
