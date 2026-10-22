import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Scope counts — boards counted like the panel's list")
struct ScopeCountsTests {
    @Test("Archived and expired sensitive members are not counted; empty boards are absent")
    func visibleMembersOnly() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("scope-\(UUID().uuidString)")))
        try store.migrate()
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

        let counts = try await store.visibleCountsByBoard()
        #expect(counts[work.id] == 1)
        #expect(counts[empty.id] == nil)
        #expect(try await store.count(inBoard: work.id) == 3)
    }
}
