#if canImport(AppKit)
    import AppKit

    /// Region-selection presentation only; capture, coordinates and lifetime belong to the caller.
    @MainActor public final class RegionSelectionView: NSView {
        private let cursor: NSCursor
        private var cursorTracking: NSTrackingArea?
        private var isSelecting = true

        public init(frame: NSRect, cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: frame)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError("Use init(frame:cursor:)") }

        public var finish: ((CGPoint, CGPoint) -> Void)?
        private var start: CGPoint?
        private var current: CGPoint?
        override public var acceptsFirstResponder: Bool { true }
        override public var needsPanelToBecomeKey: Bool { true }
        // A drag on another display must select immediately, not only make its panel key.
        override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override public func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let cursorTracking { removeTrackingArea(cursorTracking) }
            cursorTracking = nil
            guard isSelecting else { return }
            // cursorUpdate is not delivered with activeAlways. Use mouse events so
            // the nonactivating selector works while another application has focus.
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [
                    .activeAlways, .mouseEnteredAndExited, .mouseMoved,
                    .inVisibleRect, .enabledDuringMouseDrag
                ],
                owner: self, userInfo: nil)
            addTrackingArea(tracking)
            cursorTracking = tracking
        }

        /// Stop before closing the panel so a queued mouse event cannot restore
        /// the selection cursor after cancellation or over a newer request.
        public func endSelection() {
            isSelecting = false
            if let cursorTracking { removeTrackingArea(cursorTracking) }
            cursorTracking = nil
            finish = nil
            start = nil
            current = nil
        }

        private func updateCursor() { if isSelecting { cursor.set() } }
        override public func mouseEntered(with event: NSEvent) { updateCursor() }
        override public func mouseMoved(with event: NSEvent) { updateCursor() }
        override public func mouseDown(with event: NSEvent) {
            guard isSelecting else { return }
            updateCursor()
            window?.makeKey()
            start = event.locationInWindow
            current = start
            needsDisplay = true
        }
        override public func mouseDragged(with event: NSEvent) {
            guard isSelecting else { return }
            updateCursor()
            current = event.locationInWindow
            needsDisplay = true
        }
        override public func mouseUp(with event: NSEvent) {
            guard let start, let window else { return }
            finish?(
                window.convertPoint(toScreen: start),
                window.convertPoint(toScreen: event.locationInWindow))
        }
        override public func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()
            guard let start, let current else { return }
            let rect = NSRect(
                x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(start.x - current.x),
                height: abs(start.y - current.y)
            ).intersection(bounds)
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
        }
    }
#endif
