import AppKit
import SwiftUI

@MainActor
final class MonitorWindowController {
    private var controller: NSWindowController?

    func show(viewModel: MainViewModel, monitorStore: MonitorStore) {
        let hosting = NSHostingController(rootView: MonitorWindowView(viewModel: viewModel, monitorStore: monitorStore))
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 260, y: 240, width: 860, height: 260),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.level = .floating
            window.title = "PRBar Monitor"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.minSize = NSSize(width: 700, height: 120)
            window.center()
            controller = NSWindowController(window: window)
        } else {
            controller?.contentViewController = hosting
        }

        controller?.showWindow(nil)
        controller?.window?.orderFrontRegardless()
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
