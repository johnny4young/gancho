import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import Observation

/// Owns Gancho's in-process AppKit status-item fallback.
///
/// SwiftUI `MenuBarExtra` is intentionally not used here: on macOS 26 a hidden
/// Control Center-hosted scene can remain registered while never painting. A
/// plain `NSStatusItem` gives Gancho an AppKit-owned resident item for local
/// UI tests and for builds where the external helper cannot launch. Production
/// launches `GanchoMenuBarHelper` first because macOS can hide the main bundle's
/// status-item owner while still exposing it to Accessibility. The fallback
/// intentionally has no autosave name: persisted menu-bar customization state
/// is exactly what can keep a repaired agent registered in Accessibility while
/// not painting. Both paths open the same `MenuBarMenu`, drawn by this app.
@MainActor
final class StatusItemController: NSObject {
    private static let autosaveName = "GanchoPrimaryStatusItem"
    private static var visibilityAutosaveNames: [String] {
        [
            autosaveName,
            "GanchoStatusItem",
            "gancho-status-item",
            "Item-0",
            "Item-1",
            "Item-2"
        ]
    }

    private weak var model: AppModel?
    private var statusItem: NSStatusItem?
    private var menu: MenuBarMenu?

    /// Whether the in-process fallback item is currently painting.
    var isAttached: Bool { statusItem != nil }

    /// The process-local signal used by the lifecycle guard. If macOS or a
    /// menu-bar manager removes this item, the history process must not remain
    /// alive without a manipulation affordance.
    var hasVisibleAffordance: Bool {
        guard let statusItem, statusItem.isVisible else { return false }
        return statusItem.button?.window != nil
    }

    /// Removes the in-process fallback item. Called when the external helper is
    /// confirmed running so the two never paint a duplicate icon.
    func detach() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func attach(model: AppModel, menu: MenuBarMenu) {
        guard statusItem == nil else { return }

        self.model = model
        self.menu = menu

        repairHiddenStatusItemVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(
            withLength: GanchoMenuBarCommand.statusItemLength)
        // AppKit's native fail-closed contract: Command-dragging the last
        // manipulation affordance out of the menu bar terminates Gancho.
        item.behavior = .terminationOnRemoval
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        updateStatusPresentation()
        // AppKit can apply its automatically chosen visibility autosave state
        // while materializing the button. Repair it once after that first host
        // setup; later presentation refreshes must never mask a real removal.
        item.isVisible = true
        observeStatus()
    }

    private func repairHiddenStatusItemVisibilityDefaults() {
        let defaults = UserDefaults.standard
        for autosaveName in Self.visibilityAutosaveNames {
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(autosaveName)")
            defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
        }
        defaults.synchronize()
    }

    @objc private func statusItemClicked() {
        guard let model, let statusItem, let button = statusItem.button else { return }
        switch MenuBarClick(modifiers: NSApp.currentEvent?.modifierFlags ?? []) {
        case .command(let command):
            command.perform(on: model)
            updateStatusPresentation()
        case .openMenu:
            guard let menu else { return }
            menu.onOpen = { [weak self] in self?.updateStatusPresentation() }
            menu.onClose = { [weak self] in self?.updateStatusPresentation() }
            // Attached only for this click, so a plain click still reaches here.
            statusItem.menu = menu.menu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func observeStatus() {
        guard let model else { return }
        withObservationTracking {
            _ = model.menuBarBadge
            _ = model.menuBarAccessibilityLabel
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusPresentation()
                self?.observeStatus()
            }
        }
    }

    private func updateStatusPresentation() {
        guard let statusItem, let button = statusItem.button, let model else { return }

        MenuBarGlyph.apply(badge: model.menuBarBadge, to: button)
        button.toolTip = model.menuBarAccessibilityLabel
        button.setAccessibilityLabel(model.menuBarAccessibilityLabel)
        #if DEBUG
            if let badge = model.menuBarBadge {
                button.setAccessibilityValue("badge:\(badge.bridgeValue)")
            } else {
                button.setAccessibilityValue("badge:none")
            }
            if CommandLine.arguments.contains("-diagnose-global-shortcut-for-ui-test") {
                button.setAccessibilityValue(
                    GlobalShortcutDiagnostics.panelRegistrationAccessibilityValue)
            }
        #endif

        #if DEBUG
            logResolvedPlacement(of: button)
        #endif
    }

    #if DEBUG
        /// Logs which screen the status item resolved onto (or warns if it
        /// landed off-screen) — the signal that makes a hidden or mis-placed
        /// item obvious at launch instead of only in the accessibility tree.
        private func logResolvedPlacement(of button: NSStatusBarButton) {
            guard let frame = button.window?.frame else {
                print("status-item: no host window yet")
                return
            }
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
                print("status-item: on \(screen.localizedName) at \(NSStringFromRect(frame))")
            } else {
                print("status-item: WARNING resolved off-screen at \(NSStringFromRect(frame))")
            }
        }
    #endif
}

/// The status item's spoken capture state. Shared by the in-process fallback
/// and the App Group publisher that drives the helper.
struct StatusItemPresentation {
    let accessibilityDescription: String

    init(status: MonitorStatus) {
        accessibilityDescription =
            switch status {
            case .running: String(localized: "Gancho: capturing")
            case .pausedByUser: String(localized: "Gancho: private mode")
            case .pausedByScreenShare: String(localized: "Gancho: paused while sharing")
            case .stopped, .pausedByScreenLock: String(localized: "Gancho: paused")
            case .deniedByPrivacySettings: String(localized: "Gancho: pasteboard access denied")
            }
    }
}
