import Foundation
import GRDB

/// Applies the retention policy to the store. Every statement runs on
/// GRDB's writer queue — never the main thread — so purges can run from a
/// timer or on launch without touching UI latency.
///
/// Order of evaluation (most specific first): per-item `expiresAt` →
/// sensitive lifetime → per-kind window → global window. Pinned rows and
/// board members are exempt from every clause EXCEPT the sensitive
/// lifetime: a detected secret always follows the shorter sensitive limit
/// — favoriting or filing it must not make it permanent (the CHANGELOG
/// promise). Snippets are exempt from everything, including the sensitive
/// clause: promotion is explicit, permanent curation.
public struct RetentionEngine: Sendable {
    private let store: GRDBClipboardStore

    public init(store: GRDBClipboardStore) {
        self.store = store
    }

    /// One purge pass. Returns and LOGS the summary (purge_log table) so the
    /// Privacy Center can show counters without content.
    @discardableResult
    public func runPurge(policy: RetentionPolicy, now: Date = .now) async throws -> PurgeSummary {
        let (purged, blobCandidates) = try await store.writer.write {
            db -> (PurgeSummary, Set<String>) in
            var partial = PurgeSummary()
            var candidates: Set<String> = []

            // Every clause tombstones its synced victims BEFORE deleting them,
            // so the deletion propagates to iCloud instead of the record
            // resurrecting on the next fetch (an expired secret must not live
            // on in the cloud forever). Same predicate for both statements so
            // they cover exactly the same rows; unsynced rows (no system
            // fields) have no cloud record, so they need no tombstone. The
            // victims' blob hashes are captured BEFORE the delete so orphan
            // cleanup after the transaction is O(deleted), not a full sweep.
            func purge(where predicate: String, arguments: StatementArguments) throws -> Int {
                try candidates.formUnion(
                    String.fetchSet(
                        db,
                        sql: "SELECT DISTINCT contentBlobHash FROM clip "
                            + "WHERE contentBlobHash IS NOT NULL AND " + predicate,
                        arguments: arguments))
                try db.execute(
                    sql: "INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) "
                        + "SELECT id, ? FROM clip "
                        + "WHERE syncSystemFields IS NOT NULL AND " + predicate,
                    arguments: StatementArguments([now]) + arguments)
                try db.execute(
                    sql: "DELETE FROM clip WHERE " + predicate, arguments: arguments)
                return db.changesCount
            }

            // 1. Per-item explicit expiry.
            partial.expiredByOwnDate = try purge(
                where:
                    "isPinned = 0 AND isSnippet = 0 AND id NOT IN (SELECT clipID FROM clip_board) AND expiresAt IS NOT NULL AND expiresAt <= ?",
                arguments: [now])

            // 2. Sensitive lifetime. Deliberately IGNORES `isPinned` and
            // board membership (unlike every other clause): a detected
            // secret must not become permanent by being favorited or filed
            // onto a board. Snippets are the one exemption — promoting is an
            // explicit, deliberate act of permanent curation.
            partial.sensitiveExpired = try purge(
                where: "isSnippet = 0 AND isSensitive = 1 AND createdAt <= ?",
                arguments: [now.addingTimeInterval(-policy.sensitiveLifetime)])

            // 3. Per-kind windows (override the global for their kind).
            for (kind, window) in policy.perKind.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                guard let lifetime = window.lifetime else { continue }
                partial.byKindWindow += try purge(
                    where:
                        "isPinned = 0 AND isSnippet = 0 AND id NOT IN (SELECT clipID FROM clip_board) AND kind = ? AND createdAt <= ?",
                    arguments: [kind.rawValue, now.addingTimeInterval(-lifetime)])
            }

            // 4. Global window for every kind WITHOUT an override.
            if let lifetime = policy.global.lifetime {
                let overridden = policy.perKind.keys.map(\.rawValue)
                var predicate =
                    "isPinned = 0 AND isSnippet = 0 AND id NOT IN (SELECT clipID FROM clip_board) AND createdAt <= ?"
                var arguments: [any DatabaseValueConvertible] = [
                    now.addingTimeInterval(-lifetime)
                ]
                if !overridden.isEmpty {
                    let placeholders = Array(repeating: "?", count: overridden.count)
                        .joined(separator: ",")
                    predicate += " AND kind NOT IN (\(placeholders))"
                    arguments.append(contentsOf: overridden.sorted())
                }
                partial.byGlobalWindow = try purge(
                    where: predicate, arguments: StatementArguments(arguments))
            }

            return (partial, candidates)
        }

        // Blobs are files, not rows — they are cleaned OUTSIDE the write
        // transaction, precisely (only the deleted rows' hashes, each
        // ref-checked), mirroring the per-row `delete(id:)` path.
        var summary = purged
        summary.orphanedBlobsRemoved = try await store.removeBlobsIfOrphaned(blobCandidates)
        try await store.logPurge(summary, at: now)
        return summary
    }
}

extension GRDBClipboardStore {
    /// Deletes the given candidate blob hashes — the hashes of rows a mass
    /// delete just removed — when no surviving row still references them.
    /// Content-addressed blobs are shared, so each candidate is ref-checked
    /// before its file goes; a blob still referenced is never deleted. The
    /// precise counterpart to the full-sweep ``removeOrphanedBlobs()``:
    /// O(deleted) instead of O(table + files).
    func removeBlobsIfOrphaned(_ candidates: Set<String>) async throws -> Int {
        guard !candidates.isEmpty else { return 0 }
        let orphaned = try await writer.read { db in
            try candidates.filter { hash in
                try ClipRow.filter(Column("contentBlobHash") == hash).fetchCount(db) == 0
            }
        }
        for hash in orphaned {
            blobsForMaintenance.delete(hash: hash)
        }
        return orphaned.count
    }

    /// Full-sweep fallback: deletes every blob file no row references. The
    /// steady-state mass-delete paths (retention purge, panic delete) use
    /// the precise ``removeBlobsIfOrphaned(_:)`` instead; keep this as the
    /// explicit garbage-collection entry point for repair/maintenance.
    func removeOrphanedBlobs() async throws -> Int {
        let referenced = try await writer.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT DISTINCT contentBlobHash FROM clip WHERE contentBlobHash IS NOT NULL"
            )
        }
        return blobsForMaintenance.removeAll(except: referenced)
    }

    /// Appends one purge run to the log (Privacy Center counters).
    func logPurge(_ summary: PurgeSummary, at date: Date) async throws {
        let payload = String(
            decoding: try JSONEncoder().encode(summary), as: UTF8.self)
        try await writer.write { db in
            try db.execute(
                sql: "INSERT INTO purge_log (runAt, totalRowsPurged, summary) VALUES (?, ?, ?)",
                arguments: [date, summary.totalRowsPurged, payload])
        }
    }

    /// Total purged items since a date — the Privacy Center counter.
    public func purgedItemCount(since date: Date) async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(totalRowsPurged), 0) FROM purge_log WHERE runAt >= ?",
                arguments: [date]) ?? 0
        }
    }
}
