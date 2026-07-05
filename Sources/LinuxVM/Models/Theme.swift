import SwiftUI

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A color scheme for the app's chrome (window, cards, accent).
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: Color
    let surface: Color
    let border: Color
    let accent: Color
    /// System follows the OS appearance and uses semantic colors.
    var isSystem: Bool = false
}

enum ThemeCatalog {
    static let system = Theme(
        id: "system", name: "System",
        background: Color(nsColor: .windowBackgroundColor),
        surface: Color(nsColor: .controlBackgroundColor),
        border: Color(nsColor: .separatorColor),
        accent: .accentColor, isSystem: true)

    // Popular dark schemes (palette values only).
    static let dracula = Theme(id: "dracula", name: "Dracula",
        background: Color(hex: 0x1E1F29), surface: Color(hex: 0x282A36),
        border: Color(hex: 0x44475A), accent: Color(hex: 0xBD93F9))
    static let nord = Theme(id: "nord", name: "Nord",
        background: Color(hex: 0x2E3440), surface: Color(hex: 0x3B4252),
        border: Color(hex: 0x4C566A), accent: Color(hex: 0x88C0D0))
    static let tokyoNight = Theme(id: "tokyo-night", name: "Tokyo Night",
        background: Color(hex: 0x1A1B26), surface: Color(hex: 0x24283B),
        border: Color(hex: 0x414868), accent: Color(hex: 0x7AA2F7))
    static let catppuccin = Theme(id: "catppuccin", name: "Catppuccin Mocha",
        background: Color(hex: 0x1E1E2E), surface: Color(hex: 0x313244),
        border: Color(hex: 0x45475A), accent: Color(hex: 0xCBA6F7))
    static let gruvbox = Theme(id: "gruvbox", name: "Gruvbox Dark",
        background: Color(hex: 0x282828), surface: Color(hex: 0x3C3836),
        border: Color(hex: 0x504945), accent: Color(hex: 0xFE8019))
    static let solarized = Theme(id: "solarized", name: "Solarized Dark",
        background: Color(hex: 0x002B36), surface: Color(hex: 0x073642),
        border: Color(hex: 0x586E75), accent: Color(hex: 0x268BD2))
    static let oneDark = Theme(id: "one-dark", name: "One Dark",
        background: Color(hex: 0x282C34), surface: Color(hex: 0x21252B),
        border: Color(hex: 0x3E4451), accent: Color(hex: 0x61AFEF))
    static let monokai = Theme(id: "monokai", name: "Monokai",
        background: Color(hex: 0x272822), surface: Color(hex: 0x2D2E27),
        border: Color(hex: 0x49483E), accent: Color(hex: 0x66D9EF))

    static let all: [Theme] = [
        system, dracula, nord, tokyoNight, catppuccin, gruvbox, solarized, oneDark, monokai
    ]
    static func theme(_ id: String) -> Theme? { all.first { $0.id == id } }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var current: Theme

    init() {
        let id = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        current = ThemeCatalog.theme(id) ?? ThemeCatalog.system
    }

    func select(_ theme: Theme) {
        current = theme
        UserDefaults.standard.set(theme.id, forKey: "appTheme")
    }
}

extension View {
    /// Applies the theme's tint and color scheme to a view tree.
    @ViewBuilder func appTheme(_ theme: Theme) -> some View {
        self.tint(theme.isSystem ? nil : theme.accent)
            .preferredColorScheme(theme.isSystem ? nil : .dark)
    }
}
