import AppKit
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
final class PanelController {
    private var panel: KeyPanel?
    private weak var model: AppModel?

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
        Task { await model.refreshRecents() }
        // Latency telemetry for the <100ms budget (debug builds only).
        #if DEBUG
            print("panel: open took \(ContinuousClock.now - clock)")
        #endif
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel(model: AppModel) -> KeyPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: PanelView()
                .environment(model))
        let created = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered, defer: false)
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.level = .floating
        // Active-space behavior: the panel follows the user, never drags
        // them to another space.
        created.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.contentView = hosting
        created.setFrameAutosaveName("gancho-panel")
        created.isReleasedWhenClosed = false
        panel = created
        return created
    }

    private func place(_ panel: NSPanel) {
        switch position {
        case .lastPosition:
            // Frame autosave already restored it.
            break
        case .centered:
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(
                    NSPoint(
                        x: frame.midX - panel.frame.width / 2,
                        y: frame.midY - panel.frame.height / 2))
            }
        case .atCursor:
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(
                NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height))
        }
    }
}

/// Borderless-ish nonactivating panels refuse key status by default; the
/// search field needs it for type-to-search.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
