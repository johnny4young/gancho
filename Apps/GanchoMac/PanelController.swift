import AppKit
import GanchoDesign
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
    private weak var model: AppModel?

    /// The panel auto-hides when it loses key focus (the user clicks another
    /// app or window), Spotlight-style. Flip this to keep it open on purpose —
    /// the seam for a future "pin" affordance.
    var keepsOpenOnFocusLoss = false

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
        // Latency telemetry for the <100ms budget (debug builds only).
        #if DEBUG
            print("panel: open took \(ContinuousClock.now - clock)")
        #endif
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Auto-hide when the panel loses key focus — a click in another app or
    /// window dismisses it (Spotlight-style). Held open while a preview sheet is
    /// attached, while pinned, and under UI tests (which drive visibility via
    /// the launch hook, not focus).
    func windowDidResignKey(_ notification: Notification) {
        guard !Self.isUITestLaunch, !keepsOpenOnFocusLoss,
            let panel, panel.attachedSheet == nil
        else { return }
        panel.orderOut(nil)
    }

    private func ensurePanel(model: AppModel) -> KeyPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: PanelView()
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
