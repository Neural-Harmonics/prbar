import AppKit
import SwiftUI

@MainActor
final class MonitorWindowController {
    private var controller: NSWindowController?

    func show(viewModel: MainViewModel, monitorStore: MonitorStore) {
        let hosting = NSHostingController(rootView: MonitorWindowView(viewModel: viewModel, monitorStore: monitorStore))
        if controller == nil {
            let panel = NSPanel(contentRect: NSRect(x: 260, y: 240, width: 860, height: 620),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                backing: .buffered,
                                defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.title = "PRBar Monitor"
            panel.contentViewController = hosting
            controller = NSWindowController(window: panel)
        } else {
            controller?.contentViewController = hosting
        }

        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
