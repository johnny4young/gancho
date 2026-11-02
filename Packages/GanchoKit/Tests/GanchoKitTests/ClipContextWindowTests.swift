import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Jump to context — clips first copied around one moment")
struct ClipContextWindowTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("context-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(
        _ name: String, seconds: TimeInterval, pinned: Bool = false, expiresAt: Date? = nil
    ) -> ClipItem {
        ClipItem(
            createdAt: anchor.addingTimeInterval(seconds), preview: name, contentHash: name,
            isPinned: pinned, isSensitive: expiresAt != nil, expiresAt: expiresAt)
    }

    @Test("The window is inclusive at both ends and oldest first; pins keep their time")
    func window() async throws {
        let store = try makeStore()
        let clips = [
            clip("too early", seconds: -121), clip("start", seconds: -120),
            clip("pinned", seconds: -30, pinned: true), clip("anchor", seconds: 0),
            clip("end", seconds: 120), clip("too late", seconds: 121)
        ]
        for item in clips { try await store.insert(item, content: .text(item.preview)) }
        let range = anchor.addingTimeInterval(-120)...anchor.addingTimeInterval(120)
        let rows = try await store.itemsCreated(in: range)
        #expect(rows.map(\.preview) == ["start", "pinned", "anchor", "end"])
    }

    @Test("Archived and expired clips stay out; a recopy keeps its first copy's time")
    func hiddenRows() async throws {
        let store = try makeStore()
        let archived = clip("archived", seconds: 10)
        let expired = clip("expired", seconds: 20, expiresAt: .now.addingTimeInterval(-60))
        let recopied = clip("recopied", seconds: 30)
        for item in [archived, expired, recopied] {
            try await store.insert(item, content: .text(item.preview))
        }
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }
        _ = try await store.insert(
            ClipItem(preview: "recopied", contentHash: "recopied"), content: .text("recopied"))
        let rows = try await store.itemsCreated(in: anchor...anchor.addingTimeInterval(60))
        #expect(rows.map(\.preview) == ["recopied"])
        #expect(try await store.itemsCreated(in: anchor...anchor, limit: 0).isEmpty)
    }
}
