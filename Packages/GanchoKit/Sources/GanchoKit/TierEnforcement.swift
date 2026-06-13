import Foundation
import GRDB

/// Applies free-plan ceilings WITHOUT deleting anything: overflow rows are
/// archived (hidden from lists/search, still exported, still on disk) and
/// released the moment the tier turns Pro. Pins, board members, and
/// sensitive items are never archived (sensitive ones expire on their own).
public struct TierEnforcement: Sendable {
    public struct Summary: Sendable, Equatable {
        public var archived: Int
        public var released: Int

        public init(archived: Int = 0, released: Int = 0) {
            self.archived = archived
            self.released = released
        }
    }

    private let store: GRDBClipboardStore

    public init(store: GRDBClipboardStore) {
        self.store = store
    }

    /// One enforcement pass. Pro releases everything; Free archives rows
    /// beyond the newest `historyItems` OR older than `historyDays`.
    @discardableResult
    public func enforce(tier: UserTier, now: Date = .now) async throws -> Summary {
        try await store.writer.write { db in
            var summary = Summary()
            switch tier {
            case .pro:
                try db.execute(sql: "UPDATE clip SET isArchived = 0 WHERE isArchived = 1")
                summary.released = db.changesCount
            case .free:
                let cutoff = now.addingTimeInterval(-FreeTierLimits.historyDays)
                try db.execute(
                    sql: """
                        UPDATE clip SET isArchived = 1
                        WHERE isArchived = 0 AND isPinned = 0 AND pinboardID IS NULL
                          AND createdAt < ?
                        """,
                    arguments: [cutoff])
                summary.archived = db.changesCount

                try db.execute(
                    sql: """
                        UPDATE clip SET isArchived = 1
                        WHERE id IN (
                            SELECT id FROM clip
                            WHERE isArchived = 0 AND isPinned = 0 AND pinboardID IS NULL
                            ORDER BY createdAt DESC
                            LIMIT -1 OFFSET ?
                        )
                        """,
                    arguments: [FreeTierLimits.historyItems])
                summary.archived += db.changesCount
            }
            return summary
        }
    }
}

extension GRDBClipboardStore {
    /// The non-intrusive notice counter ("N older clips are archived —
    /// they come back with Pro").
    public func archivedCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE isArchived = 1") ?? 0
        }
    }
}
