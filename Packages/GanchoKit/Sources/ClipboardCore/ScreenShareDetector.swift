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
        /// Helper executables that exist only during an active share, and the
        /// app the user knows each one by.
        static let shareHelpers: [String: String] = [
            "CptHost": "Zoom",  // Zoom screen-share host
            "caphost": "Zoom",  // Zoom variant
            "Microsoft Teams Helper (Renderer)": "Microsoft Teams",
            "ScreenSharingAgent": "Screen Sharing"  // Apple Screen Sharing host agent
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
            sharingAppName() != nil
        }

        /// The app presumed to be sharing the screen, or nil when none is.
        public func sharingAppName() -> String? {
            runningProcessNames().lazy.compactMap { Self.shareHelpers[$0] }.first
        }
    }
#endif
