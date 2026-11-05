import AppKit

extension NSWindow {
    /// Shows a window the user asked for above other apps. `NSApp.activate()` is
    /// a request the system can refuse for a menu-bar agent, which leaves the
    /// window behind the active app. Not for the panel, which must keep that
    /// app active so it can paste into it.
    func bringToFront() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
