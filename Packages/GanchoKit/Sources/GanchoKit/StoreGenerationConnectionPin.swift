import Foundation
import GRDB

#if SQLITE_HAS_CODEC
    import SQLCipher
#else
    import SQLite3
#endif

/// Pin the actual SQLite connection, not GRDB's longer-lived configuration or
/// dispatch watchdog. SQLite drops this reference only after closing its pager,
/// including delayed close_v2 completion with outstanding statements/backups.
extension StoreGenerationLease {
    enum ConnectionFailure: Error { case releasedGeneration, registrationFailed }

    func pin(to database: Database) throws {
        guard let connection = database.sqliteConnection else {
            throw ConnectionFailure.registrationFailed
        }
        // Per-connection private name prevents accidental replacement by other
        // application functions. No persisted schema or query uses this function.
        let name = "gancho_generation_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let retained = Unmanaged.passRetained(self).toOpaque()
        let result = sqlite3_create_function_v2(
            connection, name, 0, SQLITE_UTF8 | SQLITE_DIRECTONLY, retained,
            { context, _, _ in sqlite3_result_null(context) }, nil, nil,
            { pointer in
                guard let pointer else { return }
                // Drop only this connection's reference. Never release shared
                // generation ownership beneath sibling readers or snapshots.
                Unmanaged<StoreGenerationLease>.fromOpaque(pointer).release()
            })
        // SQLite invokes xDestroy on registration failure too. It owns the
        // retained pointer after the call; releasing it here would double-free.
        guard result == SQLITE_OK else { throw ConnectionFailure.registrationFailed }
    }
}
