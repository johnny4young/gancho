import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Inbox receipts — atomic durable insertion")
struct InboxReceiptTests {
    @Test("Receipt failure rolls back new rows and dedupe mutations")
    func receiptFailureRollsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-receipt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try DatabaseQueue()
        let store = GRDBClipboardStore(writer: db, blobs: BlobStore(directory: root))
        try store.migrate()
        let existing = ClipItem(contentHash: "existing")
        try await store.insert(existing, content: .text("synthetic existing"))
        let persistedBefore = try await store.items(offset: 0, limit: 10)
        try await db.write { db in
            try db.execute(
                sql:
                    "CREATE TRIGGER fail_inbox_receipt BEFORE INSERT ON inbox_receipt "
                    + "BEGIN SELECT RAISE(ABORT, 'synthetic receipt refusal'); END"
            )
        }
        for hash in ["new", "existing"] {
            await #expect(throws: (any Error).self) {
                try await store.insertInboxDelivery(
                    id: hash, item: ClipItem(contentHash: hash), content: .text("synthetic"))
            }
        }
        #expect(try await store.items(offset: 0, limit: 10) == persistedBefore)
        #expect(
            try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM inbox_receipt") }
                == 0)
        try await db.write { try $0.execute(sql: "DROP TRIGGER fail_inbox_receipt") }
        guard
            case .inserted = try await store.insertInboxDelivery(
                id: "new", item: ClipItem(contentHash: "new"), content: .text("synthetic"))
        else {
            Issue.record("retry must insert after rollback")
            return
        }
    }

    @Test("Restarted receipt replay never retimestamps or resurrects a deleted clip")
    func restartAndDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-restart-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let item = ClipItem(contentHash: "synthetic-replay")
        let first = try GRDBClipboardStore(directory: root)
        #expect(
            try await first.insertInboxDelivery(
                id: "delivery", item: item, content: .text("synthetic")) == .inserted(item))
        let persistedBefore = try await first.item(id: item.id)
        let restarted = try GRDBClipboardStore(directory: root)
        #expect(
            try await restarted.insertInboxDelivery(
                id: "delivery", item: item, content: .text("synthetic")) == .alreadyCommitted)
        #expect(try await restarted.item(id: item.id) == persistedBefore)
        try await restarted.delete(id: item.id)
        #expect(
            try await first.insertInboxDelivery(
                id: "delivery", item: item, content: .text("synthetic")) == .alreadyCommitted)
        #expect(try await first.items(offset: 0, limit: 10).isEmpty)
    }

    @Test("Two database owners commit a delivery exactly once")
    func concurrentOwners() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-concurrent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try GRDBClipboardStore(directory: root)
        let second = try GRDBClipboardStore(directory: root)
        async let left = first.insertInboxDelivery(
            id: "one", item: ClipItem(contentHash: "left"), content: .text("synthetic left"))
        async let right = second.insertInboxDelivery(
            id: "one", item: ClipItem(contentHash: "right"), content: .text("synthetic right"))
        let outcomes = try await [left, right]
        #expect(outcomes.filter { $0 == .alreadyCommitted }.count == 1)
        #expect(try await first.items(offset: 0, limit: 10).count == 1)
    }

    @Test("Cancellation before insertion creates neither receipt nor row")
    func cancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await store.insertInboxDelivery(
                id: "cancel", item: ClipItem(contentHash: "cancel"), content: .text("synthetic"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.items(offset: 0, limit: 10).isEmpty)
    }
}
