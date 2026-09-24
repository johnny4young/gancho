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
            try db.execute(
                sql: "INSERT INTO inbox_receipt (id, committedAt) VALUES (?, ?)",
                arguments: [id, Date()])
            try Task.checkCancellation()
            return .inserted(stored.item)
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
