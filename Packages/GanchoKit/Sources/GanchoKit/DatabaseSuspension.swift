import Foundation
import GRDB

/// Cooperative database suspension for iOS background transitions.
///
/// iOS terminates an app with `0xDEAD10CC` ("dead lock") if it holds a SQLite
/// lock while the process is suspended and the database lives in a shared App
/// Group container — Gancho's exact setup. GRDB avoids this when stores open
/// with `Configuration.observesSuspensionNotifications` (which
/// ``GRDBClipboardStore`` sets on iOS) AND the app posts these notifications as
/// it crosses the background boundary.
///
/// The shared core owns the GRDB dependency, so the iOS app drives suspension
/// through this seam instead of importing GRDB. macOS never suspends, so the
/// macOS app and CLI never call these.
public enum DatabaseSuspension {
    /// Suspend before the process is suspended (e.g. on `.background`). GRDB
    /// releases its locks; any in-flight write fails with `SQLITE_INTERRUPT` or
    /// `SQLITE_ABORT` rather than risking the `0xDEAD10CC` termination.
    public static func suspend() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    /// Resume when the process returns to the foreground (`.active`). Suspended
    /// databases start accepting writes again.
    public static func resume() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }
}
