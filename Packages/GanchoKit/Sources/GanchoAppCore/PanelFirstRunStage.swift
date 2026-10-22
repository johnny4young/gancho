import GanchoKit

/// The empty panel's three-key lesson: shown in the peek column while the
/// history is genuinely empty and nothing has been pasted back yet. Once the
/// first paste lands it never returns.
public enum PanelFirstRunStage {
    /// Set on the first paste-back by any route (Enter, a transform, a snippet,
    /// Smart Paste); local and content-free, never gated on telemetry consent.
    public static let pasteBackKey = "first-pasteback-at"

    /// A shortcut's display string as keycaps: each leading modifier glyph on
    /// its own, then the key ("⇧⌘V" → ⇧ ⌘ V, "⌥Space" → ⌥ Space).
    public static func keycaps(for shortcut: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let leading = shortcut.prefix { modifiers.contains($0) }
        let key = shortcut.dropFirst(leading.count)
        return leading.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }

    /// `narrowed` means a query or filter emptied the list, not an empty history.
    public static func isShown(historyEmpty: Bool, narrowed: Bool, hasPastedBack: Bool) -> Bool {
        historyEmpty && !narrowed && !hasPastedBack
    }
}

extension SuccessfulReuseMethod {
    /// Whether the reuse wrote into another app; a drag or a copy does not.
    public var isPasteBack: Bool {
        switch self {
        case .paste, .transform, .snippet, .smartPaste: true
        case .drag, .copy: false
        }
    }
}
