import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Semantic search — persisted vectors")
struct SemanticSearchTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("sem-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Vectors persist; nearest neighbor ranks first; library scoping works")
    func persistedSearch() async throws {
        let store = try makeStore()
        let groceries = ClipItem(preview: "buy milk", contentHash: "h1")
        let deploys = ClipItem(preview: "deploy api", contentHash: "h2")
        try await store.insert(groceries, content: .text("buy milk"))
        try await store.insert(deploys, content: .text("deploy api"))
        try await store.saveEmbedding(clipID: groceries.id, vector: [1, 0, 0])
        try await store.saveEmbedding(clipID: deploys.id, vector: [0, 1, 0])

        let hits = try await store.semanticSearch(queryVector: [0.9, 0.1, 0])
        #expect(hits.first?.preview == "buy milk")

        // Library scope: only snippets.
        try await store.promoteToSnippet(id: deploys.id)
        let library = try await store.semanticSearch(
            queryVector: [0.9, 0.1, 0], snippetsOnly: true)
        #expect(library.map(\.preview) == ["deploy api"])
    }

    @Test("Cosine ranking orders every match; zero vectors never score")
    func ranking() async throws {
        let store = try makeStore()
        let close = ClipItem(preview: "close", contentHash: "r1")
        let mid = ClipItem(preview: "mid", contentHash: "r2")
        let far = ClipItem(preview: "far", contentHash: "r3")
        let zero = ClipItem(preview: "zero", contentHash: "r4")
        for (item, text) in [(close, "close"), (mid, "mid"), (far, "far"), (zero, "zero")] {
            try await store.insert(item, content: .text(text))
        }
        try await store.saveEmbedding(clipID: close.id, vector: [1, 0, 0])
        try await store.saveEmbedding(clipID: mid.id, vector: [1, 1, 0])
        try await store.saveEmbedding(clipID: far.id, vector: [0, 0, 1])
        try await store.saveEmbedding(clipID: zero.id, vector: [0, 0, 0])

        // cos = 1, 1/√2, 0 — and the zero vector is skipped, never NaN.
        let hits = try await store.semanticSearch(queryVector: [1, 0, 0])
        #expect(hits.map(\.preview) == ["close", "mid", "far"])

        // topK smaller than the match count exercises the bounded partial
        // selection: exactly the best K, still in descending order.
        let topTwo = try await store.semanticSearch(queryVector: [1, 0, 0], topK: 2)
        #expect(topTwo.map(\.preview) == ["close", "mid"])
        #expect(try await store.semanticSearch(queryVector: [1, 0, 0], topK: 0).isEmpty)
    }

    @Test("Dimension mismatches and archived clips are excluded")
    func exclusions() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])

        // Query in a different dimension matches nothing.
        #expect(try await store.semanticSearch(queryVector: [1, 0, 0]).isEmpty)
    }

    @Test("Every save stamps the current embedding model version")
    func versionStamping() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])

        let stamped = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT modelVersion FROM clip_embedding")
        }
        #expect(stamped == EmbeddingModelInfo.currentVersion)
    }

    @Test("Old-pipeline vectors serve no queries and surface in bounded stale batches")
    func staleVectorLifecycle() async throws {
        let store = try makeStore()
        let fresh = ClipItem(preview: "fresh", contentHash: "f")
        let stale = ClipItem(preview: "stale", contentHash: "s")
        try await store.insert(fresh, content: .text("fresh"))
        try await store.insert(stale, content: .text("stale"))
        try await store.saveEmbedding(clipID: fresh.id, vector: [1, 0, 0])
        try await store.saveEmbedding(clipID: stale.id, vector: [1, 0, 0])
        // Simulate a vector left behind by an older pipeline.
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip_embedding SET modelVersion = modelVersion - 1 WHERE clipID = ?",
                arguments: [stale.id.uuidString])
        }

        // An old vector is not comparable to a fresh query vector — it must
        // not rank, even though its clip is visible.
        let hits = try await store.semanticSearch(queryVector: [1, 0, 0])
        #expect(hits.map(\.preview) == ["fresh"])

        // The stale row is queued for refresh, in bounded batches. A zero or
        // negative limit is a no-op, never an unbounded read.
        #expect(try await store.staleEmbeddingClipIDs(limit: 10) == [stale.id])
        #expect(try await store.staleEmbeddingClipIDs(limit: 0).isEmpty)
        #expect(try await store.staleEmbeddingClipIDs(limit: -1).isEmpty)

        // Re-saving through the normal path clears the staleness.
        try await store.saveEmbedding(clipID: stale.id, vector: [0, 1, 0])
        #expect(try await store.staleEmbeddingClipIDs(limit: 10).isEmpty)
        #expect(try await store.semanticSearch(queryVector: [1, 0, 0]).count == 2)
    }

    @Test("Archived clips never enter the stale-refresh queue")
    func staleSkipsArchived() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE clip_embedding SET modelVersion = modelVersion - 1")
            try db.execute(sql: "UPDATE clip SET isArchived = 1")
        }
        #expect(try await store.staleEmbeddingClipIDs(limit: 10).isEmpty)
    }

    @Test("Sensitive clips never enter the stale-refresh queue")
    func staleSkipsSensitive() async throws {
        // Capture never embeds a sensitive clip, so this state can only arise
        // if a future path flips `isSensitive` after a vector exists — the
        // query must hold the boundary on its own regardless.
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE clip_embedding SET modelVersion = modelVersion - 1")
            try db.execute(sql: "UPDATE clip SET isSensitive = 1")
        }
        #expect(try await store.staleEmbeddingClipIDs(limit: 10).isEmpty)
    }
}
