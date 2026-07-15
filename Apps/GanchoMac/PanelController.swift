import AppKit
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// ⇧⌘V by default — the muscle-memory neighbor of plain paste.
    static let togglePanel = Self(
        "toggle-panel", default: .init(.v, modifiers: [.command, .shift]))
    /// No default: the user records it in Settings if they want it.
    static let togglePrivateMode = Self("toggle-private-mode")
    /// Cyclic quick-paste (each press pastes the next history item).
    static let cyclicPaste = Self("cyclic-paste")
    /// Pops and pastes the front of the paste stack.
    static let pasteFromStack = Self("paste-from-stack")
}

/// Where the panel appears. PasteNow pattern: user-configurable.
enum PanelPosition: String, CaseIterable {
    case centered
    case atCursor
    case lastPosition
}

/// Owns the floating NSPanel: nonactivating (the frontmost app keeps focus
/// focus-wise until the user acts), floating level, joins the ACTIVE space.
/// The panel instance is created once and reused — reopening is an
/// orderFront, which is what keeps open latency far under the 100ms budget.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var largePreviewWindow: NSWindow?
    private weak var model: AppModel?
    private var activeFileDragSource: MultiFileDragSource?
    #if DEBUG
        private var uiTestMultiFileDropOverlay: UITestMultiFileDropOverlay?
    #endif

    /// The panel auto-hides when it loses key focus (the user clicks another
    /// app or window), Spotlight-style. Flip this to keep it open on purpose —
    /// the seam for a future "pin" affordance.
    var keepsOpenOnFocusLoss = false

    /// True while a drag that started inside the panel is still in flight —
    /// dropping into another app can steal key focus, and hiding the source
    /// window mid-drag would cancel the drag.
    private var isDraggingOut = false
    /// Distinguishes overlapping drag sessions so a stale watcher never
    /// clears the flag of a newer drag.
    private var dragOutGeneration = 0

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var position: PanelPosition {
        get {
            PanelPosition(
                rawValue: UserDefaults.standard.string(forKey: "panel-position") ?? "")
                ?? .centered
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "panel-position") }
    }

    /// Registers the global shortcut. Called once from AppModel.init.
    func attach(model: AppModel) {
        self.model = model
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self, weak model] in
            guard let self, let model else { return }
            self.toggle(model: model)
        }
    }

    func toggle(model: AppModel) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(model: model)
        }
    }

    func show(model: AppModel) {
        let clock = ContinuousClock.now
        let panel = ensurePanel(model: model)
        place(panel)
        panel.makeKeyAndOrderFront(nil)
        if Self.isUITestLaunch {
            panel.orderFrontRegardless()
        }
        Task { await model.refreshRecents() }
        // Opening the panel is "I want to see my clips" — pull the latest from
        // iCloud (and push pending) so another device's recent clips appear.
        // Non-blocking: the local list shows instantly; synced clips land on
        // settle. The engine is push-driven on its own; this is the latency
        // belt-and-braces for the moment the user is actually looking.
        model.syncNow()
        // Latency telemetry for the <100ms budget (debug builds only).
        #if DEBUG
            print("panel: open took \(ContinuousClock.now - clock)")
        #endif
    }

    func hide() {
        closeLargePreview()
        panel?.orderOut(nil)
    }

    /// Presents the selected clip as an attached, resizable sheet. Attaching it
    /// keeps the nonactivating source panel alive behind the preview and returns
    /// keyboard focus to the same search/list state when the sheet closes.
    func showLargePreview(_ item: ClipItem, model: AppModel) {
        let panel = ensurePanel(model: model)
        guard panel.attachedSheet == nil else { return }

        let hosting = NSHostingController(
            rootView: ClipLargePreview(item: item) { [weak self] in
                self?.closeLargePreview()
            }
            .environment(model)
            .ganchoTinted())
        let preview = NSWindow(contentViewController: hosting)
        preview.title = String(localized: "Preview")
        preview.styleMask = [.titled, .resizable, .fullSizeContentView]
        preview.titleVisibility = .hidden
        preview.titlebarAppearsTransparent = true
        preview.isReleasedWhenClosed = false
        preview.setAccessibilityIdentifier("large-preview-window")
        preview.setContentSize(NSSize(width: 900, height: 660))
        preview.contentMinSize = NSSize(width: 640, height: 420)
        preview.standardWindowButton(.closeButton)?.isHidden = true
        preview.standardWindowButton(.miniaturizeButton)?.isHidden = true
        preview.standardWindowButton(.zoomButton)?.isHidden = true
        largePreviewWindow = preview
        panel.beginSheet(preview) { [weak self] _ in
            self?.largePreviewWindow = nil
        }
    }

    func closeLargePreview() {
        guard let preview = largePreviewWindow else { return }
        if let parent = preview.sheetParent {
            parent.endSheet(preview)
        } else {
            preview.orderOut(nil)
            largePreviewWindow = nil
        }
    }

    /// Called at drag start (SwiftUI's `.onDrag` gives the source no end
    /// callback), so the session's end is observed the only way available:
    /// the mouse button releasing.
    func noteDragOutStarted() {
        dragOutGeneration += 1
        let generation = dragOutGeneration
        isDraggingOut = true
        Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let self, self.dragOutGeneration == generation else { return }
            self.isDraggingOut = false
        }
    }

    #if DEBUG
        /// Installs the signed UI smoke's destination on the top-level panel,
        /// outside SwiftUI's hosted hit-test tree. The handler receives only a
        /// count; paths and clipboard content never leave AppKit.
        func configureUITestMultiFileDrop(_ handler: ((Int) -> Void)?) {
            guard let contentView = panel?.contentView else { return }
            guard let handler else {
                uiTestMultiFileDropOverlay?.removeFromSuperview()
                uiTestMultiFileDropOverlay = nil
                return
            }
            let overlay = uiTestMultiFileDropOverlay ?? UITestMultiFileDropOverlay()
            overlay.onDrop = handler
            if overlay.superview == nil {
                overlay.frame = contentView.bounds
                overlay.autoresizingMask = [.width, .height]
                contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
            }
            uiTestMultiFileDropOverlay = overlay
        }
    #endif

    /// Starts the AppKit-only edge of drag-out from the row's narrow responder
    /// bridge, with one NSDraggingItem per concrete file URL.
    @discardableResult
    func beginMultiFileDrag(
        _ payload: LoadedFileDragPayload, event: NSEvent,
        sourceView: NSView, model: AppModel
    ) -> Bool {
        guard event.type == .leftMouseDragged, event.window === sourceView.window,
            NSEvent.pressedMouseButtons & 1 == 1, activeFileDragSource == nil,
            payload.urls.count > 1
        else { return false }

        let source = MultiFileDragSource { [weak self, weak model] delivered in
            guard let self else { return }
            noteDragOutEnded()
            activeFileDragSource = nil
            guard delivered, let model else { return }
            Task { @MainActor in await model.noteDragOutDelivered(payload.items) }
        }
        activeFileDragSource = source
        let draggingItems = payload.urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon =
                (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
                ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            icon?.size = NSSize(width: 40, height: 40)
            item.setDraggingFrame(
                NSRect(
                    x: event.locationInWindow.x - 20,
                    y: event.locationInWindow.y - 20,
                    width: 40,
                    height: 40),
                contents: icon)
            return item
        }
        let session = sourceView.beginDraggingSession(
            with: draggingItems, event: event, source: source)
        session.draggingFormation = .stack
        session.animatesToStartingPositionsOnCancelOrFail = true
        #if DEBUG
            if CommandLine.arguments.contains("-show-multi-file-drop-target") {
                NotificationCenter.default.post(
                    name: .uiTestMultiFileDragStarted, object: payload.urls.count)
            }
        #endif
        noteDragOutStarted()
        return true
    }

    private func noteDragOutEnded() {
        dragOutGeneration += 1
        isDraggingOut = false
    }

    /// Auto-hide when the panel loses key focus — a click in another app or
    /// window dismisses it (Spotlight-style). Held open while a preview sheet is
    /// attached, while pinned, while a drag-out is in flight, and under UI tests
    /// (which drive visibility via the launch hook, not focus).
    func windowDidResignKey(_ notification: Notification) {
        guard !Self.isUITestLaunch, !keepsOpenOnFocusLoss, !isDraggingOut,
            let panel, panel.attachedSheet == nil
        else { return }
        panel.orderOut(nil)
    }

    private func ensurePanel(model: AppModel) -> KeyPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: PanelView(model: model)
                .environment(model)
                .ganchoTinted())
        let styleMask: NSWindow.StyleMask =
            Self.isUITestLaunch
            ? [.titled, .closable, .fullSizeContentView]
            : [.titled, .nonactivatingPanel, .fullSizeContentView]
        let created = KeyPanel(
            // Wide enough for the list + the peek column beside it.
            contentRect: NSRect(x: 0, y: 0, width: 864, height: 540),
            // Chromeless floating panel (Spotlight-style): titled so AppKit
            // reliably creates and orders it, with the title bar made
            // transparent and controls hidden below. Dismissed with Escape.
            styleMask: styleMask,
            backing: .buffered, defer: false)
        created.title = "Gancho"
        created.setAccessibilityIdentifier("history-panel")
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        // Nonactivating panels must survive app deactivation: the user's
        // editor/browser remains the focused app while Gancho floats above it.
        created.hidesOnDeactivate = false
        created.standardWindowButton(.closeButton)?.isHidden = true
        created.standardWindowButton(.miniaturizeButton)?.isHidden = true
        created.standardWindowButton(.zoomButton)?.isHidden = true
        // No window shadow: on a translucent borderless panel the shadow hugs
        // the glass and reads as a dark hairline around the edge. The glass
        // material carries its own depth.
        created.hasShadow = false
        created.level = .floating
        // Active-space behavior: the panel follows the user, never drags
        // them to another space.
        created.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.contentView = hosting
        created.setFrameAutosaveName("gancho-panel")
        created.isReleasedWhenClosed = false
        created.delegate = self
        panel = created
        return created
    }

    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains("-open-panel-on-launch")
    }

    private func place(_ panel: NSPanel) {
        if CommandLine.arguments.contains("-place-panel-for-ui-test") {
            // Fixed global coordinates keep synthesized drags away
            // from a stale autosaved frame on another or disconnected screen.
            panel.setFrameOrigin(NSPoint(x: 100, y: 100))
            return
        }
        switch position {
        case .lastPosition:
            // Frame autosave already restored it. If the saved display is no
            // longer reachable, fall back to the current pointer screen.
            guard !panel.frame.intersectsAnyScreen else {
                break
            }
            center(panel)
        case .centered:
            center(panel)
        case .atCursor:
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(
                NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height))
        }
    }

    private func center(_ panel: NSPanel) {
        guard let screen = Self.targetScreen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2))
    }

    private static var targetScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// Retained only for the lifetime of one AppKit drag. The source owns no app
/// state; it reports the negotiated result back to `PanelController` and is
/// released immediately when the session ends.
@MainActor
private final class MultiFileDragSource: NSObject, NSDraggingSource {
    private let onEnd: (Bool) -> Void

    init(onEnd: @escaping (Bool) -> Void) {
        self.onEnd = onEnd
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onEnd(!operation.isEmpty)
    }
}

#if DEBUG
    /// Topmost test-only destination. It declines the initial mouse-down so the
    /// real row remains the drag source, then participates in drag hit-testing
    /// across the panel and reads each independent file-URL pasteboard object.
    @MainActor
    private final class UITestMultiFileDropOverlay: NSView {
        var onDrop: ((Int) -> Void)?

        init() {
            super.init(frame: .zero)
            registerForDraggedTypes([.fileURL])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type,
                type == .leftMouseDragged || type == .leftMouseUp,
                bounds.contains(point)
            else { return nil }
            return self
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            fileURLs(from: sender).isEmpty ? [] : .copy
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            let urls = fileURLs(from: sender)
            guard !urls.isEmpty else { return false }
            onDrop?(urls.count)
            return true
        }

        private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true
            ]
            return sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: options) as? [URL] ?? []
        }
    }
#endif

extension NSRect {
    fileprivate var intersectsAnyScreen: Bool {
        NSScreen.screens.contains { intersects($0.visibleFrame) }
    }
}

/// Borderless-ish nonactivating panels refuse key status by default; the
/// search field needs it for type-to-search.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// The panel is created once and reused (reopening is an `orderFront`), so
    /// any close request (⌘W, a programmatic close) hides it rather than
    /// destroying the instance.
    override func performClose(_ sender: Any?) {
        orderOut(sender)
    }
}
