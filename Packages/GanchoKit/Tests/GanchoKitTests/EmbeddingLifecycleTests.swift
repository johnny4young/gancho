import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Semantic vectors never outlive their clip")
struct EmbeddingLifecycleTests {
    private func makeStore(migrated: Bool = true) throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("embeddings-\(UUID().uuidString)")))
        if migrated { try store.migrate() }
        return store
    }

    private func embeddingIDs(_ store: GRDBClipboardStore) async throws -> Set<String> {
        try await store.writer.read { db in
            try String.fetchSet(db, sql: "SELECT clipID FROM clip_embedding")
        }
    }

    @Test("Deleting a clip, plainly or for sync, drops its vector")
    func deleteDropsVector() async throws {
        let store = try makeStore()
        let plain = ClipItem(preview: "plain", contentHash: "p")
        let synced = ClipItem(preview: "synced", contentHash: "s")
        let kept = ClipItem(preview: "kept", contentHash: "k")
        for item in [plain, synced, kept] {
            try await store.insert(item, content: .text(item.preview))
            try await store.saveEmbedding(clipID: item.id, vector: [1, 0])
        }

        try await store.delete(id: plain.id)
        try await store.deleteForSync(id: synced.id)

        #expect(try await embeddingIDs(store) == [kept.id.uuidString])
    }

    @Test("A retention purge drops the purged clips' vectors")
    func retentionDropsVector() async throws {
        let store = try makeStore()
        let now = Date.now
        let old = ClipItem(
            createdAt: now.addingTimeInterval(-90 * 86_400), preview: "old", contentHash: "o")
        try await store.insert(old, content: .text("old"))
        try await store.saveEmbedding(clipID: old.id, vector: [1, 0])

        _ = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .month), now: now)

        #expect(try await embeddingIDs(store).isEmpty)
    }

    @Test("The migration removes vectors orphaned before it existed")
    func migrationRemovesExistingOrphans() async throws {
        let store = try makeStore(migrated: false)
        try store.migrate(upTo: GanchoDatabaseMigrator.Identifier.textRecipes.rawValue)
        let kept = ClipItem(preview: "kept", contentHash: "k")
        try await store.insert(kept, content: .text("kept"))
        try await store.saveEmbedding(clipID: kept.id, vector: [1, 0])
        try await store.saveEmbedding(clipID: UUID(), vector: [0, 1])

        try store.migrate()

        #expect(try await embeddingIDs(store) == [kept.id.uuidString])
    }
}
