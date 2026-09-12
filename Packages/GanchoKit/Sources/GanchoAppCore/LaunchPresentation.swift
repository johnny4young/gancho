#if os(macOS)
    import ClipboardCore
    import Foundation

    /// What the Mac opens when it finishes launching.
    ///
    /// A menu-bar agent has no main window, so "what shows at launch" is a
    /// decision rather than a scene, and it was previously an `if/else` chain in
    /// the composition root that no test could reach.
    public enum LaunchPresentation: Sendable, Equatable {
        /// The onboarding window: a first run, or a UI test asking for it.
        case welcome
        /// macOS is refusing pasteboard reads; this window explains the fix.
        case pasteboardPermission
        /// A UI test asking for deterministic panel access without the hotkey.
        case panel
        /// Nothing opens; the agent waits in the menu bar.
        case menuBarOnly

        /// Decides from the state of the launch.
        ///
        /// The order is the contract. A UI test that asked for the panel gets
        /// ONLY the panel, so a fresh defaults suite cannot drop an onboarding
        /// window in front of the flow under test. Onboarding then outranks the
        /// pasteboard explainer: a first run has to introduce the app before it
        /// asks anyone to change a system privacy setting, and the explainer is
        /// still waiting on the next launch.
        ///
        /// - Parameters:
        ///   - opensPanel: the UI-test hook asked for the panel.
        ///   - forcesWelcome: the UI-test hook asked for onboarding.
        ///   - hasSeenWelcome: onboarding has been completed on this Mac before.
        ///   - monitorStatus: what the capture monitor reports right now.
        public static func decide(
            opensPanel: Bool,
            forcesWelcome: Bool,
            hasSeenWelcome: Bool,
            monitorStatus: MonitorStatus
        ) -> LaunchPresentation {
            if opensPanel { return .panel }
            if forcesWelcome || !hasSeenWelcome { return .welcome }
            return monitorStatus == .deniedByPrivacySettings ? .pasteboardPermission : .menuBarOnly
        }
    }
#endif
