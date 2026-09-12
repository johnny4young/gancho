import AppKit
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
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
