import AppKit
import GanchoAppCore
import GanchoDesign
import SwiftUI

@MainActor
final class LibraryWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        model.panel.hide()
        if window == nil {
            let hosting = NSHostingController(
                rootView: LibraryView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Library")
            created.styleMask = [.titled, .closable, .resizable]
            created.isReleasedWhenClosed = false
            // Open roomy and never let it shrink below the two-pane layout's needs.
            created.setContentSize(NSSize(width: 900, height: 640))
            created.contentMinSize = NSSize(width: 800, height: 560)
            created.center()
            #if DEBUG
                // XCTest window screenshots can fail on negative-coordinate displays.
                // Only opt-in, disposable fixtures use the primary screen.
                if CommandLine.arguments.contains("-place-library-for-ui-test"),
                    StoreBootstrap.request() != .production,
                    let frame = NSScreen.screens.first?.visibleFrame
                {
                    created.setFrameTopLeftPoint(
                        NSPoint(x: frame.minX + 40, y: frame.maxY - 40))
                }
            #endif
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // The window is cached, so the view's `.task` runs once; presenting is
        // the retry the failed-load message promises.
        model.reloadSavedFilters()
    }
}
