import AppKit
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import OSLog
import SwiftUI

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
    private enum PreferenceKey {
        static let position = "panel-position"
        static let contentWidth = "panel-content-width"
        static let contentHeight = "panel-content-height"
    }

    private static let minimumContentSize = CGSize(width: 720, height: 460)
    private static let maximumContentSize = CGSize(width: 1_400, height: 900)

    private var panel: KeyPanel?
    private var largePreviewWindow: NSWindow?
    private weak var model: AppModel?
    private var activeFileDragSource: MultiFileDragSource?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    /// The open interval, from `show()` to the panel's first `onAppear`. Held
    /// across the two callbacks so Instruments (and the `-measure-panel`
    /// baseline) see the true request→first-frame latency, not just the
    /// synchronous ordering cost.
    private var firstFrameInterval: OSSignpostIntervalState?
    private var firstFrameClock: ContinuousClock.Instant?
    private static let measuresFirstFrame =
        CommandLine.arguments.contains("-measure-panel")

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
                rawValue: defaults.string(forKey: PreferenceKey.position) ?? "")
                ?? .centered
        }
        set { defaults.set(newValue.rawValue, forKey: PreferenceKey.position) }
    }

    var textSize: PanelTextSize {
        get { PanelTextSize.resolved(defaults.string(forKey: PanelTextSize.storageKey)) }
        set {
            defaults.set(newValue.rawValue, forKey: PanelTextSize.storageKey)
            #if DEBUG
                // UI automation observes the semantic preference without
                // flattening the SwiftUI hierarchy into a test-only wrapper.
                panel?.setAccessibilityValue(newValue.rawValue)
            #endif
        }
    }

    var preferredContentSize: CGSize {
        let width = defaults.double(forKey: PreferenceKey.contentWidth)
        let height = defaults.double(forKey: PreferenceKey.contentHeight)
        guard width > 0, height > 0 else { return PanelSizePreset.standard.contentSize }
        return Self.clampedContentSize(CGSize(width: width, height: height))
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
        // Panel request → first visible frame: begin here, end at the panel's
        // first onAppear (`notePanelDidAppear`). A reopen that skips the
        // onAppear (already visible) closes the interval synchronously below.
        if firstFrameInterval == nil {
            firstFrameInterval = Signpost.panelToFirstFrame.begin()
            firstFrameClock = ContinuousClock.now
        }
        let wasVisible = panel?.isVisible == true
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
        // An already-visible panel re-order fires no onAppear; close the
        // interval now so it never dangles as an eternal open.
        if wasVisible { notePanelDidAppear() }
    }

    /// Called from `PanelView.onAppear` when the panel's content first renders.
    /// Ends the request→first-frame interval and, under `-measure-panel`,
    /// prints the wall-clock latency so a warm run collects an SLO baseline.
    func notePanelDidAppear() {
        guard let interval = firstFrameInterval else { return }
        Signpost.panelToFirstFrame.end(interval)
        firstFrameInterval = nil
        if Self.measuresFirstFrame, let start = firstFrameClock {
            print("panel-first-frame: \(ContinuousClock.now - start)")
        }
        firstFrameClock = nil
    }

    func hide() {
        closeLargePreview()
        panel?.orderOut(nil)
    }

    /// Applies a convenient starting size without disabling ordinary AppKit
    /// edge resizing. The resulting live/manual size is persisted separately
    /// from the screen-specific frame so it also survives display changes.
    func resize(to preset: PanelSizePreset) {
        resizeContent(to: preset.contentSize)
    }

    func resizeContent(to requestedSize: CGSize) {
        let size = Self.clampedContentSize(requestedSize)
        persistContentSize(size)
        guard let model else { return }
        let panel = ensurePanel(model: model)
        var target = panel.frameRect(
            forContentRect: NSRect(
                origin: .zero, size: NSSize(width: size.width, height: size.height)))
        let current = panel.frame
        target.origin = NSPoint(
            x: current.midX - target.width / 2,
            y: current.midY - target.height / 2)
        if let screen = panel.screen ?? Self.targetScreen {
            target = panel.constrainFrameRect(target, to: screen)
        }
        panel.setFrame(target, display: true, animate: panel.isVisible)
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
                let fileItemCount =
                    session.draggingPasteboard.pasteboardItems?.count(where: {
                        $0.availableType(from: [.fileURL]) != nil
                    }) ?? 0
                NotificationCenter.default.post(
                    name: .uiTestMultiFileDragStarted, object: fileItemCount)
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

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistContentSize(window.contentRect(forFrameRect: window.frame).size)
    }

    private func ensurePanel(model: AppModel) -> KeyPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: PanelView(model: model, displayDefaults: defaults)
                .environment(model)
                .ganchoTinted())
        let styleMask: NSWindow.StyleMask =
            Self.isUITestLaunch
            ? [.titled, .closable, .resizable, .fullSizeContentView]
            : [.titled, .nonactivatingPanel, .resizable, .fullSizeContentView]
        let preferredSize = preferredContentSize
        let created = KeyPanel(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            // Chromeless floating panel (Spotlight-style): titled so AppKit
            // reliably creates and orders it, with the title bar made
            // transparent and controls hidden below. Dismissed with Escape.
            styleMask: styleMask,
            backing: .buffered, defer: false)
        created.title = "Gancho"
        created.setAccessibilityIdentifier("history-panel")
        #if DEBUG
            created.setAccessibilityValue(textSize.rawValue)
        #endif
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
        #if DEBUG
            let usesOpaqueUITestBackground =
                CommandLine.arguments.contains("-opaque-panel-for-ui-test")
            created.isOpaque = usesOpaqueUITestBackground
            created.backgroundColor =
                usesOpaqueUITestBackground ? .windowBackgroundColor : .clear
        #else
            created.isOpaque = false
            created.backgroundColor = .clear
        #endif
        created.contentView = hosting
        created.contentMinSize = NSSize(
            width: Self.minimumContentSize.width, height: Self.minimumContentSize.height)
        created.contentMaxSize = NSSize(
            width: Self.maximumContentSize.width, height: Self.maximumContentSize.height)
        // UI tests use a disposable defaults suite; do not let them read or
        // mutate the developer's screen-specific NSWindow autosave domain.
        #if DEBUG
            if AppModel.uiTestDefaultsSuiteName() == nil {
                created.setFrameAutosaveName("gancho-panel")
            }
        #else
            created.setFrameAutosaveName("gancho-panel")
        #endif
        created.isReleasedWhenClosed = false
        created.delegate = self
        panel = created
        return created
    }

    private func persistContentSize(_ requestedSize: CGSize) {
        let size = Self.clampedContentSize(requestedSize)
        defaults.set(size.width, forKey: PreferenceKey.contentWidth)
        defaults.set(size.height, forKey: PreferenceKey.contentHeight)
    }

    private static func clampedContentSize(_ requestedSize: CGSize) -> CGSize {
        CGSize(
            width: min(
                max(requestedSize.width, minimumContentSize.width), maximumContentSize.width),
            height: min(
                max(requestedSize.height, minimumContentSize.height), maximumContentSize.height))
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
