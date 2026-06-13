#if os(macOS)
    import AppKit
    import Foundation

    /// Best-effort "is the screen being shared" check, by presence of the
    /// helper processes conferencing apps spawn ONLY while sharing.
    ///
    /// Deliberate decisions:
    /// - NO `NSWindow.sharingType` window-hiding — Maccy shipped it and
    ///   reverted (breaks DisplayPort monitors, issue #1136). We pause
    ///   CAPTURE and hide PREVIEWS instead of fighting the compositor.
    /// - NO ScreenCaptureKit enumeration — `SCShareableContent` triggers the
    ///   Screen Recording permission prompt, which Gancho has no business
    ///   asking for. Process presence needs no permission.
    /// The check is conservative: it can miss exotic sharing tools (the
    /// user always has manual private mode); it never false-positives on a
    /// conferencing app that is merely OPEN.
    public struct ScreenShareDetector: Sendable {
        /// Helper executables that exist only during an active share.
        static let shareHelperNames: Set<String> = [
            "CptHost",  // Zoom screen-share host
            "caphost",  // Zoom variant
            "Microsoft Teams Helper (Renderer)",  // Teams share renderer
            "ScreenSharingAgent",  // Apple Screen Sharing host agent
        ]

        private let runningProcessNames: @Sendable () -> [String]

        public init(
            runningProcessNames: @escaping @Sendable () -> [String] = {
                NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
            }
        ) {
            self.runningProcessNames = runningProcessNames
        }

        public func isScreenSharePresumed() -> Bool {
            let names = Set(runningProcessNames())
            return !names.isDisjoint(with: Self.shareHelperNames)
        }
    }
#endif
