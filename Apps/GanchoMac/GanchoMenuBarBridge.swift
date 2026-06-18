import Foundation

/// Content-free side channel between the main app and the paint-only menu-bar
/// helper, shared by both targets.
///
/// Backed by an App Group suite, so it resolves to the shared group container
/// under the App Store sandbox and to a shared preferences domain otherwise —
/// either way reachable by both processes without bespoke IPC. It carries ONLY
/// non-clipboard data: the current status presentation (a glyph + an
/// accessibility label, both already localized by the app), the localized menu
/// titles, and the per-launch command nonce. Recent clips and previews never
/// cross it — they stay in the main app process.
enum GanchoMenuBarBridge {
    static let appGroupSuite = "group.com.johnny4young.gancho"

    private enum Key {
        static let statusGlyph = "menu-bar.status.glyph"
        static let statusLabel = "menu-bar.status.label"
        static let titles = "menu-bar.titles"
        static let nonce = "menu-bar.nonce"
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupSuite) }

    // MARK: Status presentation — the app writes (localized), the helper paints.

    static func writeStatus(glyph: String, label: String) {
        guard let defaults else { return }
        defaults.set(glyph, forKey: Key.statusGlyph)
        defaults.set(label, forKey: Key.statusLabel)
    }

    static func readStatus() -> (glyph: String, label: String) {
        (
            defaults?.string(forKey: Key.statusGlyph) ?? GanchoMenuBarCommand.statusGlyph,
            defaults?.string(forKey: Key.statusLabel)
                ?? GanchoMenuBarCommand.statusAccessibilityLabel
        )
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
}
