import AppKit
import GanchoDesign
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Settings")
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            // The sidebar runs under a transparent title bar, like the
            // system's Settings; the section title labels the content, so the
            // window title stays hidden.
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.moveToActiveSpace]
            created.sizeToFitContentAndCenter()
            window = created
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}
