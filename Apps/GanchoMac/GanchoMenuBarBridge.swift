import Foundation

/// Content-free side channel between the main app and the paint-only menu-bar
/// helper, shared by both targets.
///
/// Backed by an App Group suite, so it resolves to the shared group container
/// under the App Store sandbox and to a shared preferences domain otherwise —
/// either way reachable by both processes without bespoke IPC. It carries ONLY
/// non-clipboard data: the current status presentation (a content-free icon
/// identifier + a localized accessibility label), the localized menu titles,
/// the per-launch command nonce, and a single "last copied" preview for the
/// menu's recent row. That preview is the ONLY clip-derived value that crosses:
/// it is already masked for sensitive clips, and private mode omits it entirely.
/// Full clip content and the history never leave the main app process.
enum GanchoMenuBarBridge {
    static let appGroupSuite = "group.com.johnny4young.gancho"

    private enum Key {
        static let statusIcon = "menu-bar.status.icon"
        static let statusLabel = "menu-bar.status.label"
        static let titles = "menu-bar.titles"
        static let nonce = "menu-bar.nonce"
        static let lastCopiedPreview = "menu-bar.last-copied.preview"
        static let lastCopiedLabel = "menu-bar.last-copied.label"
        static let lastCopiedAt = "menu-bar.last-copied.at"
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupSuite) }

    // MARK: Status presentation — the app writes, the helper paints.

    static func writeStatus(icon: MenuBarStatusIcon, label: String) {
        guard let defaults else { return }
        defaults.set(icon.rawValue, forKey: Key.statusIcon)
        defaults.set(label, forKey: Key.statusLabel)
    }

    static func readStatus() -> (icon: MenuBarStatusIcon, label: String) {
        let icon =
            defaults?.string(forKey: Key.statusIcon)
            .flatMap(MenuBarStatusIcon.init(rawValue:)) ?? .active
        let label =
            defaults?.string(forKey: Key.statusLabel)
            ?? GanchoMenuBarCommand.statusAccessibilityLabel
        return (icon, label)
    }

    // MARK: Localized menu titles — `[command.rawValue: localized title]`.

    static func writeTitles(_ titles: [String: String]) {
        defaults?.set(titles, forKey: Key.titles)
    }

    static func readTitles() -> [String: String] {
        defaults?.dictionary(forKey: Key.titles) as? [String: String] ?? [:]
    }

    // MARK: Command nonce — the app writes it and validates inbound commands
    // against it; the helper reads it and stamps every command deep link.

    static func writeNonce(_ nonce: String) {
        defaults?.set(nonce, forKey: Key.nonce)
    }

    static func readNonce() -> String? {
        defaults?.string(forKey: Key.nonce)
    }

    // MARK: Last-copied preview — the single masked clip-derived value (see the
    // type doc). The app writes it after each capture, masked for sensitive
    // clips, and writes `nil` in private mode to clear it; the helper shows it
    // in the menu's recent row.

    /// - Parameter label: the localized "Last copied" caption word (the helper
    ///   has no string catalog, so the app resolves it and the helper appends a
    ///   locale-formatted relative time).
    static func writeLastCopied(preview: String?, label: String, at date: Date) {
        guard let defaults else { return }
        if let preview {
            defaults.set(preview, forKey: Key.lastCopiedPreview)
            defaults.set(label, forKey: Key.lastCopiedLabel)
            defaults.set(date.timeIntervalSince1970, forKey: Key.lastCopiedAt)
        } else {
            defaults.removeObject(forKey: Key.lastCopiedPreview)
            defaults.removeObject(forKey: Key.lastCopiedLabel)
            defaults.removeObject(forKey: Key.lastCopiedAt)
        }
    }

    static func readLastCopied() -> (preview: String, label: String, at: Date)? {
        guard let defaults, let preview = defaults.string(forKey: Key.lastCopiedPreview)
        else { return nil }
        let label = defaults.string(forKey: Key.lastCopiedLabel) ?? "Last copied"
        return (
            preview, label, Date(timeIntervalSince1970: defaults.double(forKey: Key.lastCopiedAt))
        )
    }
}
