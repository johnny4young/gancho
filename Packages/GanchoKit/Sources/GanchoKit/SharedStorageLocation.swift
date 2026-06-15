import Foundation

/// Where the durable store lives, per process family.
///
/// Policy (the extension-safety contract):
/// - The MAIN APP owns SQLite. It opens the database inside the App Group
///   container so future widgets/keyboard can move in without migration.
/// - EXTENSIONS never open the database. Their write path is the file
///   inbox (`SharedInbox`) — small atomic files, no lock contention, no
///   WAL coordination, processed by the app on activation. A share
///   extension lives ~seconds under a tight memory ceiling; file drops are
///   also the natural "deferred import" for large payloads.
public enum SharedStorageLocation {
    /// The store directory: App Group container when available (iOS app +
    /// extensions family), Application Support otherwise (macOS dev builds
    /// without team-signed group entitlements, tests).
    public static func storeDirectory(appGroupID: String?) -> URL {
        if let appGroupID,
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID)
        {
            return container.appendingPathComponent("store", isDirectory: true)
        }
        return URL.applicationSupportDirectory.appendingPathComponent(
            "Gancho", isDirectory: true)
    }

    /// The macOS app's store directory. The Mac app is NOT sandboxed, so this
    /// resolves to the user's real `~/Library/Application Support/Gancho` —
    /// which a Homebrew-installed `gancho` CLI (also unsandboxed) opens as the
    /// SAME database. Single source of truth shared by the app and the CLI so
    /// the two never drift onto different files.
    public static var macAppStoreDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Gancho", isDirectory: true)
    }
}
