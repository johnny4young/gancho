import Foundation
import GRDB

extension GRDBClipboardStore: InboxClipIngesting {
    public func insertInboxDelivery(
        id: String, item: ClipItem, content: ClipContent?
    ) async throws -> InboxInsertResult {
        try Task.checkCancellation()
        // Avoid touching payload blobs on the usual receipt replay path.
        if try await writer.read({ db in try Self.hasInboxReceipt(id, in: db) }) {
            return .alreadyCommitted
        }
        let row = try insertionRow(item, content: content)
        return try await writer.write { db in
            try Task.checkCancellation()
            // The second check is authoritative across concurrent processes.
            if try Self.hasInboxReceipt(id, in: db) { return .alreadyCommitted }
            let stored = try Self.insert(row, in: db)
            // A crash before the in-memory enqueue must still leave durable
            // outbound work, including when insertion deduplicated a synced row.
            try db.execute(
                sql: "UPDATE clip SET needsUpload = 1 WHERE id = ?",
                arguments: [stored.id])
            try db.execute(
                sql: "INSERT INTO inbox_receipt (id, committedAt, clipID) VALUES (?, ?, ?)",
                arguments: [id, Date(), stored.id])
            try Task.checkCancellation()
            return .inserted(stored.item)
        }
    }

    public func itemForInboxDelivery(id: String) async throws -> ClipItem? {
        try await writer.read { db in
            guard
                let clipID = try String.fetchOne(
                    db, sql: "SELECT clipID FROM inbox_receipt WHERE id = ?", arguments: [id])
            else { return nil }
            return try ClipRow.filter(key: clipID).fetchOne(db)?.item
        }
    }

    @discardableResult
    public func pruneInboxReceipts(committedBefore date: Date) async throws -> Int {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM inbox_receipt WHERE committedAt < ?", arguments: [date])
            return db.changesCount
        }
    }

    private static func hasInboxReceipt(_ id: String, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM inbox_receipt WHERE id = ?)", arguments: [id])
            == true
    }
}
