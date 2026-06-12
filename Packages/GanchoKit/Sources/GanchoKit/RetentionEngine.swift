import Foundation
import GRDB

/// Applies the retention policy to the store. Every statement runs on
/// GRDB's writer queue — never the main thread — so purges can run from a
/// timer or on launch without touching UI latency.
///
/// Order of evaluation (most specific first): per-item `expiresAt` →
/// sensitive lifetime → per-kind window → global window. `isPinned = 1`
/// rows are exempt from every clause, including their own `expiresAt`.
public struct RetentionEngine: Sendable {
    private let store: GRDBClipboardStore

    public init(store: GRDBClipboardStore) {
        self.store = store
    }

    /// One purge pass. Returns and LOGS the summary (purge_log table) so the
    /// Privacy Center can show counters without content.
    @discardableResult
    public func runPurge(policy: RetentionPolicy, now: Date = .now) async throws -> PurgeSummary {
        var summary = PurgeSummary()

        summary = try await store.writer.write { db in
            var partial = PurgeSummary()

            // 1. Per-item explicit expiry.
            try db.execute(
                sql:
                    "DELETE FROM clip WHERE isPinned = 0 AND expiresAt IS NOT NULL AND expiresAt <= ?",
                arguments: [now])
            partial.expiredByOwnDate = db.changesCount

            // 2. Sensitive lifetime.
            try db.execute(
                sql: "DELETE FROM clip WHERE isPinned = 0 AND isSensitive = 1 AND createdAt <= ?",
                arguments: [now.addingTimeInterval(-policy.sensitiveLifetime)])
            partial.sensitiveExpired = db.changesCount

            // 3. Per-kind windows (override the global for their kind).
            for (kind, window) in policy.perKind.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                guard let lifetime = window.lifetime else { continue }
                try db.execute(
                    sql: "DELETE FROM clip WHERE isPinned = 0 AND kind = ? AND createdAt <= ?",
                    arguments: [kind.rawValue, now.addingTimeInterval(-lifetime)])
                partial.byKindWindow += db.changesCount
            }

            // 4. Global window for every kind WITHOUT an override.
            if let lifetime = policy.global.lifetime {
                let overridden = policy.perKind.keys.map(\.rawValue)
                var sql = "DELETE FROM clip WHERE isPinned = 0 AND createdAt <= ?"
                var arguments: [any DatabaseValueConvertible] = [
                    now.addingTimeInterval(-lifetime)
                ]
                if !overridden.isEmpty {
                    let placeholders = Array(repeating: "?", count: overridden.count)
                        .joined(separator: ",")
                    sql += " AND kind NOT IN (\(placeholders))"
                    arguments.append(contentsOf: overridden.sorted())
                }
                try db.execute(sql: sql, arguments: StatementArguments(arguments))
                partial.byGlobalWindow = db.changesCount
            }

            return partial
        }

        summary.orphanedBlobsRemoved = try await store.removeOrphanedBlobs()
        try await store.logPurge(summary, at: now)
        return summary
    }
}

extension GRDBClipboardStore {
    /// Deletes blob files no row references anymore (mass purges bypass the
    /// per-row delete path, so orphans are swept here).
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
