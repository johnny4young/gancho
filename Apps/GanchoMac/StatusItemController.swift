import AppKit
import ClipboardCore
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
/// not painting. Command metadata is shared with the helper through
/// `GanchoMenuBarCommand`, a centralized command surface that keeps private
/// clipboard previews out of the helper process.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
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
    private let menu = NSMenu()

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

    func attach(model: AppModel) {
        guard statusItem == nil else { return }

        self.model = model

        repairHiddenStatusItemVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(
            withLength: GanchoMenuBarCommand.statusItemLength)
        // AppKit's native fail-closed contract: Command-dragging the last
        // manipulation affordance out of the menu bar terminates Gancho.
        item.behavior = .terminationOnRemoval
        item.menu = menu
        statusItem = item

        menu.autoenablesItems = false
        menu.delegate = self

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

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
        updateStatusPresentation()
    }

    private func observeStatus() {
        guard let model else { return }
        withObservationTracking {
            _ = model.monitorStatus
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusPresentation()
                self?.observeStatus()
            }
        }
    }

    private func updateStatusPresentation() {
        guard let statusItem, let button = statusItem.button, let model else { return }

        let presentation = StatusItemPresentation(status: model.monitorStatus)
        button.image = presentation.icon.templateImage()
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = presentation.accessibilityDescription
        button.setAccessibilityLabel(presentation.accessibilityDescription)

        #if DEBUG
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

    private func rebuildMenu() {
        menu.removeAllItems()
        guard let model else { return }

        // Glanceable state header (matches the design's menu top).
        let presentation = StatusItemPresentation(status: model.monitorStatus)
        let header = NSMenuItem(
            title: presentation.accessibilityDescription, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.image = presentation.icon.statusDot()
        menu.addItem(header)
        menu.addItem(.separator())

        if model.recentItems.isEmpty {
            let item = NSMenuItem(
                title: String(localized: "Copy something — it will appear here."),
                action: nil,
                keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for clip in model.recentItems.prefix(5) {
                let item = NSMenuItem(
                    title: clip.preview,
                    action: #selector(pasteRecentItem(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = clip
                item.image = NSImage(
                    systemSymbolName: clip.kind.symbolName, accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        addCommand(.library)
        addCommand(.openPanel)
        addCommand(
            .toggleCapture,
            title: GanchoMenuBarCommand.toggleCapture.title(
                captureIsRunning: model.monitorStatus == .running))
        addCommand(
            .togglePrivateMode,
            state: model.preferences.isPrivateModePaused ? .on : .off)
        addCommand(.ignoreNextCopy)

        menu.addItem(.separator())
        addCommand(.settings)
        addCommand(.welcome)
        addCommand(.privacyCenter)
        addCommand(.wrapped)
        if model.monitorStatus == .deniedByPrivacySettings {
            addCommand(.fixClipboardAccess)
        }
        menu.addItem(.separator())
        addCommand(.quit)
    }

    private func addCommand(
        _ command: GanchoMenuBarCommand,
        title: String? = nil,
        state: NSControl.StateValue = .off
    ) {
        let item = NSMenuItem(
            title: title ?? command.title,
            action: #selector(performCommand(_:)),
            keyEquivalent: command.keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = command.modifiers
        item.representedObject = command.rawValue
        item.state = state
        item.setAccessibilityIdentifier(command.accessibilityIdentifier)
        item.setAccessibilityLabel(command.accessibilityLabel)
        menu.addItem(item)
    }

    @objc private func pasteRecentItem(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? ClipItem else { return }
        model?.paste(clip)
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let command = GanchoMenuBarCommand(rawValue: rawValue),
            let model
        else { return }
        command.perform(on: model)
        updateStatusPresentation()
    }
}

/// Maps the monitor status to a menu-bar glyph + accessibility label. Shared by
/// the in-process fallback and the App Group publisher that drives the helper.
struct StatusItemPresentation {
    let icon: MenuBarStatusIcon
    let accessibilityDescription: String

    init(status: MonitorStatus) {
        switch status {
        case .running:
            icon = .active
            accessibilityDescription = String(localized: "Gancho: capturing")
        case .pausedByUser:
            icon = .paused
            accessibilityDescription = String(localized: "Gancho: private mode")
        case .pausedByScreenShare:
            icon = .paused
            accessibilityDescription = String(localized: "Gancho: paused while sharing")
        case .stopped, .pausedByScreenLock:
            icon = .stopped
            accessibilityDescription = String(localized: "Gancho: paused")
        case .deniedByPrivacySettings:
            icon = .denied
            accessibilityDescription = String(localized: "Gancho: pasteboard access denied")
        }
    }
}
