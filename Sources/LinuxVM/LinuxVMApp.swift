import SwiftUI
import AppKit

/// Promotes the app to a regular foreground app and brings its window to the
/// front on launch (a SwiftUI app built via SwiftPM otherwise can launch
/// without activating).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct LinuxVMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = VMLibrary()
    @StateObject private var credentials = CredentialsStore()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var hostStore = HostStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(credentials)
                .environmentObject(themeManager)
                .environmentObject(hostStore)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { library.hostStore = hostStore }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(credentials)
                .environmentObject(themeManager)
                .environmentObject(hostStore)
                .appTheme(themeManager.current)
        }
    }
}
