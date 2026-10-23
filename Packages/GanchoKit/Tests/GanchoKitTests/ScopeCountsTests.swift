import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Scope counts — boards counted like the panel's list")
struct ScopeCountsTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("scope-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Archived and expired sensitive members are neither counted nor listed")
    func visibleMembersOnly() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let empty = try await store.createPinboard(name: "Empty")
        let visible = ClipItem(preview: "visible", contentHash: "v")
        let archived = ClipItem(preview: "archived", contentHash: "a")
        let expired = ClipItem(
            preview: "expired", contentHash: "e", isSensitive: true,
            expiresAt: .now.addingTimeInterval(-60))
        for item in [visible, archived, expired] {
            try await store.insert(item, content: .text(item.preview))
            try await store.assign(clipID: item.id, toBoard: work.id)
        }
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }

        let counts = try await store.scopeCounts(excluding: [])
        let visibleTotal = try await store.count()
        #expect(counts.total == visibleTotal)
        #expect(counts.boards[work.id] == 1)
        #expect(counts.boards[empty.id] == nil)
        let listed = try await store.items(inBoard: work.id, limit: 10)
        #expect(listed.map(\.id) == [visible.id], "the board list hides what the chip skips")
        let boardCount = try await store.count(inBoard: work.id)
        #expect(boardCount == listed.count)
    }

    @Test("Excluded clips leave both the total and their boards")
    func excludesPendingDeletes() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let kept = ClipItem(preview: "kept", contentHash: "k")
        let pending = ClipItem(preview: "pending", contentHash: "p")
        let loose = ClipItem(preview: "loose", contentHash: "l")
        for item in [kept, pending, loose] {
            try await store.insert(item, content: .text(item.preview))
        }
        try await store.assign(clipID: kept.id, toBoard: work.id)
        try await store.assign(clipID: pending.id, toBoard: work.id)

        let all = try await store.scopeCounts(excluding: [])
        #expect(all.total == 3)
        #expect(all.boards[work.id] == 2)
        let hiding = try await store.scopeCounts(excluding: [pending.id, loose.id])
        #expect(hiding.total == 1)
        #expect(hiding.boards[work.id] == 1)
    }

    @Test("A bulk delete beyond SQLite's variable limit still counts")
    func excludesMoreIDsThanSQLiteBinds() async throws {
        let store = try makeStore()
        let kept = ClipItem(preview: "kept", contentHash: "k")
        let pending = ClipItem(preview: "pending", contentHash: "p")
        for item in [kept, pending] {
            try await store.insert(item, content: .text(item.preview))
        }
        let excluded = Set((0..<120_000).map { _ in UUID() }).union([pending.id])
        let counts = try await store.scopeCounts(excluding: excluded)
        #expect(counts.total == 1)
    }
}
