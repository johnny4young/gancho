#if canImport(AppKit)
    import AppKit

    extension NSWindow {
        /// Sizes the window to its content view controller's fitting size, then
        /// centers it. Use it in place of `center()` for any window built with
        /// `NSWindow(contentViewController:)` around an `NSHostingController`.
        ///
        /// Such a window comes out a single point wide, because SwiftUI has not
        /// laid anything out yet. `center()` centers that sliver, which puts its
        /// left edge on the screen's midpoint, and the first layout then grows
        /// the window rightward from there. It opens off-center by half its
        /// width, and on a 1024-point display a 620-point window loses its
        /// right edge off-screen, along with any controls placed there.
        public func sizeToFitContentAndCenter() {
            if let contentView = contentViewController?.view {
                setContentSize(contentView.fittingSize)
            }
            center()
        }
    }
#endif
