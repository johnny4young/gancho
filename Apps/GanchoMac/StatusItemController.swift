import AppKit
import ClipboardCore
import GanchoKit
import Observation

/// Owns the resident AppKit status item that keeps Gancho visible in the
/// menu bar.
///
/// SwiftUI `MenuBarExtra` is intentionally not used here: on macOS 26 the
/// Control Center-hosted status-item scene can be invalidated during an Xcode
/// Run launch, which removes the only scene and makes the LSUIElement agent
/// exit immediately. A plain `NSStatusItem` uses public AppKit lifecycle
/// semantics and stays resident across Debug launches.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let autosaveName = "GanchoStatusItem"
    private static var visibilityAutosaveNames: [String] {
        [
            autosaveName,
            "gancho-status-item",
            "Item-0",
        ]
    }

    private weak var model: AppModel?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func attach(model: AppModel) {
        guard statusItem == nil else { return }

        self.model = model

        repairHiddenStatusItemVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        item.menu = menu
        statusItem = item

        menu.autoenablesItems = false
        menu.delegate = self

        updateStatusPresentation()
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
        guard let button = statusItem?.button, let model else { return }

        let presentation = StatusItemPresentation(status: model.monitorStatus)
        button.image = nil
        button.imagePosition = .noImage
        button.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: presentation.menuBarGlyph,
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                .baselineOffset: -1,
            ])
        button.title = presentation.menuBarGlyph
        button.toolTip = presentation.accessibilityDescription
        button.setAccessibilityLabel(presentation.accessibilityDescription)
        statusItem?.isVisible = true
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        guard let model else { return }

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
        addItem(String(localized: "Library"), action: #selector(showLibrary))
        addItem(
            String(localized: "Open panel"),
            action: #selector(openPanel),
            keyEquivalent: "v",
            modifiers: [.command, .shift])
        addItem(
            model.monitorStatus == .running
                ? String(localized: "Pause capture")
                : String(localized: "Resume capture"),
            action: #selector(togglePause))
        addToggleItem(
            String(localized: "Private mode"),
            isOn: model.preferences.isPrivateModePaused,
            action: #selector(togglePrivateMode))
        addItem(String(localized: "Ignore next copy"), action: #selector(ignoreNextCopy))

        menu.addItem(.separator())
        addItem(String(localized: "Settings…"), action: #selector(openSettings))
        addItem(String(localized: "Welcome to Gancho"), action: #selector(openWelcome))
        addItem(String(localized: "Privacy Center"), action: #selector(openPrivacyCenter))
        addItem(String(localized: "My Clipboard, Wrapped…"), action: #selector(exportWrapped))
        if model.monitorStatus == .deniedByPrivacySettings {
            addItem(String(localized: "Fix clipboard access…"), action: #selector(openPermissions))
        }
        addToggleItem(
            String(localized: "Show in Dock"),
            isOn: model.showInDock,
            action: #selector(toggleDockIcon))

        menu.addItem(.separator())
        addItem(String(localized: "Quit Gancho"), action: #selector(quit))
    }

    private func addItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    private func addToggleItem(_ title: String, isOn: Bool, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
    }

    @objc private func pasteRecentItem(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? ClipItem else { return }
        model?.paste(clip)
    }

    @objc private func showLibrary() {
        guard let model else { return }
        model.libraryWindow.show(model: model)
    }

    @objc private func openPanel() {
        guard let model else { return }
        model.panel.show(model: model)
    }

    @objc private func togglePause() {
        model?.togglePause()
        updateStatusPresentation()
    }

    @objc private func togglePrivateMode() {
        model?.togglePrivateMode()
        updateStatusPresentation()
    }

    @objc private func ignoreNextCopy() {
        model?.ignoreNextCopy()
    }

    @objc private func openSettings() {
        guard let model else { return }
        model.settingsWindow.show(model: model)
    }

    @objc private func openWelcome() {
        guard let model else { return }
        model.welcomeWindow.show(model: model)
    }

    @objc private func openPrivacyCenter() {
        guard let model else { return }
        model.privacyCenterWindow.show(model: model)
    }

    @objc private func exportWrapped() {
        guard let model else { return }
        Task {
            let stats = await WrappedStats.gather(model: model)
            WrappedExporter.savePNG(stats: stats)
        }
    }

    @objc private func openPermissions() {
        guard let model else { return }
        model.permissionWindow.show(model: model)
    }

    @objc private func toggleDockIcon() {
        guard let model else { return }
        model.showInDock.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct StatusItemPresentation {
    let menuBarGlyph: String
    let accessibilityDescription: String

    init(status: MonitorStatus) {
        switch status {
        case .running:
            menuBarGlyph = "📎"
            accessibilityDescription = String(localized: "Gancho: capturing")
        case .pausedByUser:
            menuBarGlyph = "○"
            accessibilityDescription = String(localized: "Gancho: private mode")
        case .pausedByScreenShare:
            menuBarGlyph = "◌"
            accessibilityDescription = String(localized: "Gancho: paused while sharing")
        case .stopped, .pausedByScreenLock:
            menuBarGlyph = "⏸"
            accessibilityDescription = String(localized: "Gancho: paused")
        case .deniedByPrivacySettings:
            menuBarGlyph = "⚠︎"
            accessibilityDescription = String(localized: "Gancho: pasteboard access denied")
        }
    }
}
