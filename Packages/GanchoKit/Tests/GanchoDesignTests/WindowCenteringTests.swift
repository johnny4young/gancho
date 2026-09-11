#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import GanchoDesign

    /// Gancho's window controllers host a fixed-width SwiftUI root through
    /// `NSWindow(contentViewController:)`. A window centered before SwiftUI
    /// sizes it opens with its left edge on the screen's midpoint, so these pin
    /// the size first, then the centering.
    @Suite("Hosted windows open centered")
    @MainActor
    struct WindowCenteringTests {
        private static let contentSize = CGSize(width: 620, height: 720)

        private func hostedWindow() -> NSWindow {
            _ = NSApplication.shared
            let hosting = NSHostingController(
                rootView: Color.clear.frame(
                    width: Self.contentSize.width, height: Self.contentSize.height))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            return window
        }

        @Test("The window already has its content size when it is centered")
        func sizedBeforeCentering() {
            let window = hostedWindow()
            window.sizeToFitContentAndCenter()
            #expect(window.contentRect(forFrameRect: window.frame).size == Self.contentSize)
        }

        @Test("The window is centered at its full width")
        func centeredAtFullWidth() throws {
            let window = hostedWindow()
            window.sizeToFitContentAndCenter()
            let screen = try #require(window.screen ?? NSScreen.main, "centering needs a display")
            // `center()` does not say whether it uses the visible frame or the
            // full one, and their midpoints differ only when the Dock sits on a
            // side. The failure this guards is a window off by half its width.
            let offset = min(
                abs(window.frame.midX - screen.visibleFrame.midX),
                abs(window.frame.midX - screen.frame.midX))
            #expect(offset <= 1, "window \(window.frame) on screen \(screen.visibleFrame)")
        }
    }
#endif
