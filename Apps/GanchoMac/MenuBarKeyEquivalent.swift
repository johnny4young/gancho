import AppKit

/// A menu key equivalent as plain values, so the paint-only helper (which does
/// not link KeyboardShortcuts) can show the shortcut the user recorded.
nonisolated struct MenuBarKeyEquivalent: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init?(key: String?, modifiers: NSEvent.ModifierFlags) {
        guard let key, !key.isEmpty else { return nil }
        self.key = key
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    var bridgeValue: [String: Any] {
        ["key": key, "modifiers": modifiers.rawValue]
    }

    init?(bridgeValue: [String: Any]?) {
        guard let bridgeValue,
            let key = bridgeValue["key"] as? String,
            let raw = (bridgeValue["modifiers"] as? NSNumber)?.uintValue
        else { return nil }
        self.init(key: key, modifiers: NSEvent.ModifierFlags(rawValue: raw))
    }

    @MainActor func apply(to item: NSMenuItem) {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
    }
}
