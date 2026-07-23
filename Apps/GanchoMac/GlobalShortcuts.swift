import KeyboardShortcuts

/// App-owned names and defaults for every configurable global shortcut.
///
/// Keeping this catalog outside any individual feature controller makes the
/// shared persistence contract explicit: these raw values must remain stable
/// across dependency upgrades so existing user choices continue to restore.
extension KeyboardShortcuts.Name {
    /// ⇧⌘V by default — the muscle-memory neighbor of plain paste.
    static let togglePanel = Self(
        "toggle-panel", initial: .init(.v, modifiers: [.command, .shift]))
    /// No initial value: the user records it in Settings if they want it.
    static let togglePrivateMode = Self("toggle-private-mode")
    /// Cyclic quick-paste (each press pastes the next history item).
    static let cyclicPaste = Self("cyclic-paste")
    /// Pops and pastes the front of the paste stack.
    static let pasteFromStack = Self("paste-from-stack")
}

#if DEBUG
    /// Read-only bridge from the package's registration state to signed UI
    /// automation. The value is attached only when the explicit diagnostic
    /// launch argument is present; production accessibility remains unchanged.
    enum GlobalShortcutDiagnostics {
        static var panelRegistrationAccessibilityValue: String {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) else {
                return "global-shortcut-missing"
            }

            let state =
                KeyboardShortcuts.isEnabled(for: .togglePanel)
                ? "enabled" : "disabled"
            return
                "global-shortcut-\(state):\(shortcut.carbonKeyCode):"
                + "\(shortcut.carbonModifiers)"
        }
    }
#endif
