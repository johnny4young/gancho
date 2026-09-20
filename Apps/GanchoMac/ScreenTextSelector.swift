import AppKit
import GanchoAppCore
import GanchoDesign

@MainActor final class ScreenTextSelector {
    private let cursor = RegionSelectionCursor.make()
    private var previousCursor: NSCursor?
    private var requestID: UUID?
    private var windows: [NSPanel] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func select(id: UUID) async -> CGRect? {
        finish(nil)
        requestID = id
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            guard let primary = NSScreen.screens.first else {
                finish(nil)
                return
            }
            previousCursor = NSCursor.current
            var keyPanel: NSPanel?
            for screen in NSScreen.screens {
                let panel = RegionPanel(
                    contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                panel.acceptsMouseMovedEvents = true
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.isReleasedWhenClosed = false
                panel.cancelSelection = { [weak self] in self?.cancel(id: id) }
                let view = RegionSelectionView(
                    frame: NSRect(origin: .zero, size: screen.frame.size), cursor: cursor)
                view.setAccessibilityElement(true)
                view.setAccessibilityRole(.group)
                view.setAccessibilityIdentifier("screen-ocr-selector")
                view.setAccessibilityLabel(
                    String(localized: "Drag to select text. Escape cancels."))
                view.finish = { [weak self] start, end in
                    self?.finish(
                        ScreenTextRegion.selection(
                            from: start, to: end, display: screen.frame,
                            primaryDisplayTop: primary.frame.maxY))
                }
                panel.contentView = view
                windows.append(panel)
                panel.orderFrontRegardless()
                if screen.frame.contains(NSEvent.mouseLocation) { keyPanel = panel }
            }
            // Assign keyboard ownership after every display's panel is ordered.
            // Escape must work before the first click, without activating the app.
            let keyboardPanel = keyPanel ?? windows.first
            keyboardPanel?.makeKey()
            keyboardPanel?.makeFirstResponder(keyboardPanel?.contentView)
            cursor.set()
        }
    }

    func cancel(id: UUID) { if requestID == id { finish(nil) } }

    private func finish(_ result: CGRect?) {
        let pending = continuation
        continuation = nil
        requestID = nil
        for window in windows {
            (window.contentView as? RegionSelectionView)?.endSelection()
            window.orderOut(nil)
            window.close()
        }
        windows = []
        previousCursor?.set()
        previousCursor = nil
        pending?.resume(returning: result)
    }
}

private final class RegionPanel: NSPanel {
    var cancelSelection: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancelSelection?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelSelection?() } else { super.keyDown(with: event) }
    }
}
