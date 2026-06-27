#if GANCHO_DIRECT_DOWNLOAD
    import Sparkle

    /// Owns the Sparkle auto-updater for the direct-download build. Created at
    /// launch so the app checks the appcast (the `SUFeedURL` in Info.plist) on
    /// Sparkle's schedule and verifies updates against the embedded
    /// `SUPublicEDKey`. Compiled out of the App Store build entirely.
    @MainActor
    final class SparkleUpdater {
        private let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        /// Whether a manual check is currently allowed (false while one runs).
        var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

        /// User-initiated "Check for Updates…".
        func checkForUpdates() { controller.checkForUpdates(nil) }
    }
#endif
