import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Clipboard migration batches")
struct ClipImportBatchTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-batch-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: directory))
        try store.migrate()
        return store
    }

    @Test("Migration deduplicates across devices without touching the existing row")
    func deduplicatesWithoutMutation() async throws {
        let store = try makeStore()
        let originalDate = Date(timeIntervalSince1970: 1_750_000_000)
        let existing = ClipItem(
            createdAt: originalDate,
            updatedAt: originalDate,
            lastUsedAt: originalDate,
            preview: "existing",
            contentHash: "shared-hash",
            sourceDeviceName: "Mac A",
            isPinned: true)
        try await store.insert(existing, content: .text("existing"))

        let duplicate = ClipItem(
            preview: "foreign duplicate",
            contentHash: "shared-hash",
            sourceDeviceName: "Mac B")
        let fresh = ClipItem(preview: "fresh", contentHash: "fresh-hash")
        let result = try await store.importTextBatch([
            ClipImportBatchItem(item: duplicate, text: "existing"),
            ClipImportBatchItem(item: fresh, text: "fresh")
        ])

        #expect(result.insertedItems == [fresh])
        #expect(result.skippedDuplicates == 1)
        let rows = try await store.items()
        #expect(rows.count == 2)
        let unchanged = try #require(rows.first { $0.id == existing.id })
        #expect(unchanged.lastUsedAt == originalDate)
        #expect(unchanged.updatedAt == originalDate)
        #expect(unchanged.isPinned)
        #expect(try await store.content(for: fresh.id) == .text("fresh"))
    }

    @Test("A failed migration rolls back every row")
    func failureRollsBackBatch() async throws {
        let store = try makeStore()
        let sharedID = UUID()
        let first = ClipItem(id: sharedID, preview: "first", contentHash: "first-hash")
        let conflicting = ClipItem(
            id: sharedID,
            preview: "conflicting",
            contentHash: "second-hash")

        await #expect(throws: (any Error).self) {
            try await store.importTextBatch([
                ClipImportBatchItem(item: first, text: "first"),
                ClipImportBatchItem(item: conflicting, text: "conflicting")
            ])
        }
        #expect(try await store.count() == 0)
    }
}
