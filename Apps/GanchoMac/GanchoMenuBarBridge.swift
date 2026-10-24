import Foundation

#if !STANDALONE_MENU_BAR
    import GanchoKit
#endif

/// Content-free side channel between the main app and the paint-only
/// menu-bar helper, shared by both targets.
///
/// Backed by an App Group suite: the shared group container under the App
/// Store sandbox, a shared preferences domain otherwise. Either way it is a
/// plain plist outside the encrypted store, so it carries NO clip-derived
/// value: the status label and badge, the localized command titles, the
/// per-launch nonce, the recorded panel shortcut, and the status button's
/// screen frame. The menu with recent clips is drawn by the main app itself.
enum GanchoMenuBarBridge {
    static let appGroupSuite = "group.com.johnny4young.gancho"

    private enum Key {
        static let statusLabel = "menu-bar.status.label"
        static let statusBadge = "menu-bar.status.badge"
        static let titles = "menu-bar.titles"
        static let nonce = "menu-bar.nonce"
        static let panelShortcut = "menu-bar.panel-shortcut"
        static let buttonFrame = "menu-bar.button-frame"
        /// Earlier builds wrote a masked "last copied" preview here.
        static let retired = [
            "menu-bar.status.icon", "menu-bar.last-copied.preview", "menu-bar.last-copied.label",
            "menu-bar.last-copied.at"
        ]
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupSuite) }

    /// Removes values earlier builds left in the plist, including the old
    /// clipboard preview.
    static func removeRetiredValues() {
        for key in Key.retired { defaults?.removeObject(forKey: key) }
    }

    // MARK: Status — the app writes, the helper paints.

    static func writeStatus(label: String, badge: MenuBarBadge?) {
        guard let defaults else { return }
        defaults.set(label, forKey: Key.statusLabel)
        if let badge {
            defaults.set(badge.bridgeValue, forKey: Key.statusBadge)
        } else {
            defaults.removeObject(forKey: Key.statusBadge)
        }
    }

    static func readStatus() -> (label: String, badge: MenuBarBadge?) {
        let label =
            defaults?.string(forKey: Key.statusLabel)
            ?? GanchoMenuBarCommand.statusAccessibilityLabel
        let badge = defaults?.string(forKey: Key.statusBadge).flatMap(
            MenuBarBadge.init(bridgeValue:))
        return (label, badge)
    }

    // MARK: Localized menu titles — `[command.rawValue: localized title]`.

    static func writeTitles(_ titles: [String: String]) {
        defaults?.set(titles, forKey: Key.titles)
    }

    static func readTitles() -> [String: String] {
        defaults?.dictionary(forKey: Key.titles) as? [String: String] ?? [:]
    }

    // MARK: Panel shortcut — the recorded toggle-panel shortcut, or none.

    static func writePanelShortcut(_ shortcut: MenuBarKeyEquivalent?) {
        if let shortcut {
            defaults?.set(shortcut.bridgeValue, forKey: Key.panelShortcut)
        } else {
            defaults?.removeObject(forKey: Key.panelShortcut)
        }
    }

    static func readPanelShortcut() -> MenuBarKeyEquivalent? {
        MenuBarKeyEquivalent(bridgeValue: defaults?.dictionary(forKey: Key.panelShortcut))
    }

    // MARK: Command nonce — the app writes it and validates inbound commands
    // against it; the helper reads it and attaches it to each notification.

    static func writeNonce(_ nonce: String) {
        defaults?.set(nonce, forKey: Key.nonce)
    }

    static func readNonce() -> String? {
        defaults?.string(forKey: Key.nonce)
    }

    // MARK: Status button frame — the helper writes it before `showMenu`, so the
    // app can open its menu under the icon.

    static func writeButtonFrame(_ frame: NSRect) {
        defaults?.set(NSStringFromRect(frame), forKey: Key.buttonFrame)
    }

    static func readButtonFrame() -> NSRect? {
        defaults?.string(forKey: Key.buttonFrame).map(NSRectFromString).flatMap {
            $0.isEmpty ? nil : $0
        }
    }
}
