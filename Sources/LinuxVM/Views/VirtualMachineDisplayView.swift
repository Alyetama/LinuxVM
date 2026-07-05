import SwiftUI
import Virtualization

/// Bridges AppKit's `VZVirtualMachineView` (the live framebuffer + input) into
/// SwiftUI.
struct VirtualMachineDisplayView: NSViewRepresentable {
    let vm: VZVirtualMachine?

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        if #available(macOS 14.0, *) {
            // Keep the guest at its fixed scanout resolution and let the view
            // scale it to fill the window. If this is `true`, the guest display
            // is reconfigured to the view's *native Retina pixel* size (e.g.
            // ~3000px wide), which makes the text console microscopic.
            view.automaticallyReconfiguresDisplay = false
        }
        view.virtualMachine = vm
        return view
    }

    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        if nsView.virtualMachine !== vm {
            nsView.virtualMachine = vm
        }
    }
}
