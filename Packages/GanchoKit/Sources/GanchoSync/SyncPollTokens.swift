import CloudKit
import Foundation
import GanchoKit

/// Explicit-pull tokens, persisted separately from `CKSyncEngine` state.
/// A missing or invalid property list loads empty; a damaged token archive
/// decodes to nil when used. Refetches use the adapter's idempotent apply path.
/// ``CKSyncEngineAdapter`` owns the in-memory cache and polling lifecycle.
struct SyncPollTokens: Codable, Equatable, Sendable {
    /// Database-level change token, archived. Nil until the first poll that
    /// completes far enough to be handed one.
    var database: Data?
    /// Per-zone change tokens, archived, keyed by zone NAME rather than
    /// `CKRecordZone.ID` — the id is not `Codable`, and the name is what
    /// survives a zone being recreated under the same name.
    var zones: [String: Data]

    init(database: Data? = nil, zones: [String: Data] = [:]) {
        self.database = database
        self.zones = zones
    }

    /// The persisted tokens, or empty ones when the file is absent, unreadable,
    /// or was written in a shape this version no longer understands.
    ///
    /// `zones` is required by the existing file format. `database` is optional,
    /// including before the first completed database poll. Archive contents are
    /// validated separately by ``unarchive(_:)``.
    static func load(from store: SyncStateStore?) -> SyncPollTokens {
        guard let data = store?.load(),
            let decoded = try? PropertyListDecoder().decode(SyncPollTokens.self, from: data)
        else { return SyncPollTokens() }
        return decoded
    }

    /// Best-effort persistence. A failed write leaves the previous on-disk
    /// tokens in place; the adapter retains its current in-memory tokens.
    func save(to store: SyncStateStore?) {
        guard let store, let data = try? PropertyListEncoder().encode(self) else { return }
        store.save(data)
    }

    /// Archives an opaque CloudKit token using secure coding.
    static func archive(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    /// Nil for absent OR damaged bytes. Both mean the same thing to the caller:
    /// poll from the beginning.
    static func unarchive(_ data: Data?) -> CKServerChangeToken? {
        data.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
    }
}
