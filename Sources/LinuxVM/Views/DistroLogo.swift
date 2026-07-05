import SwiftUI

/// A round distro badge: the brand color with a simple geometric mark.
struct DistroLogo: View {
    let distroID: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(distroAccent(distroID).gradient)
            mark.frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var mark: some View {
        if distroID.hasPrefix("ubuntu") {
            UbuntuMark()
        } else if distroID.hasPrefix("debian") {
            DebianMark()
        } else if distroID.hasPrefix("fedora") {
            FedoraMark()
        } else {
            Image(systemName: "shippingbox.fill").resizable().scaledToFit()
                .foregroundStyle(.white)
        }
    }
}

/// Ubuntu "Circle of Friends": a ring with three dots.
private struct UbuntuMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = s * 0.36
            let dot = s * 0.22
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: s * 0.065)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                ForEach([-90.0, 30.0, 150.0], id: \.self) { deg in
                    let a = deg * .pi / 180
                    // Short "arm" from center to each friend, then the dot.
                    Circle().fill(.white)
                        .frame(width: dot, height: dot)
                        .position(x: c.x + r * cos(a), y: c.y + r * sin(a))
                }
            }
        }
    }
}

/// Debian "swirl": an open spiral.
private struct DebianMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Path { p in
                let turns = 1.65, steps = 80
                for i in 0...steps {
                    let t = Double(i) / Double(steps) * turns * 2 * .pi
                    let rr = s * (0.06 + 0.052 * t / (2 * .pi))
                    let pt = CGPoint(x: c.x + rr * cos(t - .pi / 2),
                                     y: c.y + rr * sin(t - .pi / 2))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        }
    }
}

/// Fedora mark: a bold white "f".
private struct FedoraMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Text("f")
                .font(.system(size: s * 0.95, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
