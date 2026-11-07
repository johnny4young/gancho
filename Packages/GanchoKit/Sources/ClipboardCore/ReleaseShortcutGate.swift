#if os(macOS)
    /// Decides whether a release-triggered global shortcut runs on its key-down
    /// or its key-up, and never on both for one press.
    ///
    /// While a menu tracks, KeyboardShortcuts reads raw key events, and a key-up
    /// can go missing: the menu dequeues it first when the main thread was busy,
    /// and it stops matching once a modifier is released before the key. So
    /// during menu tracking the press runs the action and its release is skipped.
    public struct ReleaseShortcutGate<Name: Hashable & Sendable>: Sendable {
        public private(set) var isMenuTracking = false
        private var ranOnPress: Set<Name> = []

        public init() {}

        public mutating func setMenuTracking(_ tracking: Bool) {
            isMenuTracking = tracking
        }

        /// Whether the press runs the action.
        public mutating func keyDown(_ name: Name) -> Bool {
            guard isMenuTracking else {
                ranOnPress.remove(name)
                return false
            }
            ranOnPress.insert(name)
            return true
        }

        /// Whether the release runs the action.
        public mutating func keyUp(_ name: Name) -> Bool {
            ranOnPress.remove(name) == nil
        }
    }
#endif
