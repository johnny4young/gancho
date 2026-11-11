#if os(macOS)
    /// Closes a menu that Gancho's menu-bar helper holds open before a paste
    /// posts ⌘V. While a menu tracks, its process owns the keyboard, so the key
    /// event would reach that menu instead of the app being pasted into.
    @MainActor
    public struct MenuClearance {
        public struct Effects {
            /// Whether the menu is on screen.
            public var isMenuOpen: @MainActor () -> Bool
            /// Asks the menu to close; it may take a moment to go.
            public var closeMenu: @MainActor () -> Void
            /// One short wait between checks.
            public var pause: @MainActor () async -> Void

            public init(
                isMenuOpen: @escaping @MainActor () -> Bool,
                closeMenu: @escaping @MainActor () -> Void,
                pause: @escaping @MainActor () async -> Void
            ) {
                self.isMenuOpen = isMenuOpen
                self.closeMenu = closeMenu
                self.pause = pause
            }
        }

        /// Checks after the close request before the paste goes ahead anyway.
        public static let maximumChecks = 10

        private let effects: Effects

        public init(effects: Effects) {
            self.effects = effects
        }

        /// Returns once the menu is closed, or after `maximumChecks` pauses.
        public func clear() async {
            guard effects.isMenuOpen() else { return }
            effects.closeMenu()
            for _ in 0..<Self.maximumChecks {
                await effects.pause()
                if !effects.isMenuOpen() { return }
            }
        }
    }
#endif
