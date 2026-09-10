import CloudKit
import Foundation
import GanchoKit

/// The explicit pull's change tokens: their shape, their serialization, and how
/// a missing or damaged file degrades.
///
/// Persisted SEPARATELY from `CKSyncEngine`'s own opaque state blob, because
/// piggybacking on that would corrupt the engine's serialization. Losing this
/// file is harmless by design — the next poll re-scans every zone and the
/// upserts are last-writer-wins idempotent — so every failure path here returns
/// EMPTY tokens instead of throwing. A poll that re-scans costs a round trip; a
/// poll that throws leaves the pull dead until the next launch.
///
/// A pure value on purpose. ``CKSyncEngineAdapter`` keeps the in-memory cache,
/// so lifting the serialization out leaves the actor owning poll state exactly
/// as it did.
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
    /// Never throws. A file missing `zones` is rejected WHOLESALE rather than
    /// half-restored, because pulling one zone incrementally while re-scanning
    /// another is harder to reason about than starting clean. A missing
    /// `database` is not damage and does decode: nil is exactly the state
    /// before the first poll is handed a database token.
    static func load(from store: SyncStateStore?) -> SyncPollTokens {
        guard let data = store?.load(),
            let decoded = try? PropertyListDecoder().decode(SyncPollTokens.self, from: data)
        else { return SyncPollTokens() }
        return decoded
    }

    /// Persists best-effort. An encode failure is deliberately silent: the only
    /// consequence is that the next poll re-scans, and a diagnostics entry for
    /// it would be noise on a path that self-heals.
    func save(to store: SyncStateStore?) {
        guard let store, let data = try? PropertyListEncoder().encode(self) else { return }
        store.save(data)
    }

    /// `CKServerChangeToken` has no public initializer, so an archive is the
    /// only way it crosses a file boundary — and the only way a test can hold
    /// one at all.
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
