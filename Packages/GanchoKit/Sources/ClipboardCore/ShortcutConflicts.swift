#if os(macOS)
    import Foundation

    /// Static conflict check for user-recorded global shortcuts: never fail
    /// silently when the chosen combo collides with a system staple. The
    /// check is by normalized description ("⇧⌘4") — KeyboardShortcuts hands
    /// us exactly that string.
    public enum ShortcutConflicts {
        /// System-reserved or muscle-memory combos worth warning about.
        static let knownSystemShortcuts: [String: String] = [
            "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo",
            "⌘A": "Select All", "⌘S": "Save", "⌘Q": "Quit", "⌘W": "Close Window",
            "⌘Space": "Spotlight", "⌥⌘Space": "Finder Search",
            "⇧⌘3": "Screenshot", "⇧⌘4": "Screenshot Selection",
            "⇧⌘5": "Screenshot Toolbar", "⌃⌘Q": "Lock Screen",
            "⌘Tab": "App Switcher", "⌃↑": "Mission Control",
        ]

        /// Lookup table with normalized keys (computed once).
        private static let normalizedShortcuts: [String: String] = Dictionary(
            uniqueKeysWithValues: knownSystemShortcuts.map { (normalize($0.key), $0.value) })

        /// Human-readable owner of the conflicting shortcut, nil when free.
        public static func conflict(with shortcutDescription: String) -> String? {
            normalizedShortcuts[normalize(shortcutDescription)]
        }

        /// Strips whitespace and uppercases the key letter so "⇧⌘v" and
        /// "⇧ ⌘ V" compare equal.
        static func normalize(_ description: String) -> String {
            String(
                description
                    .filter { !$0.isWhitespace }
                    .map { $0.isLetter ? Character($0.uppercased()) : $0 })
        }
    }
#endif
