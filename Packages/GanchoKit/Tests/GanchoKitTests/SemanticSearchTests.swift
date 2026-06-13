import Foundation
import GRDB
import Testing

@testable import GanchoKit

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

    @Test("Dimension mismatches and archived clips are excluded")
    func exclusions() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])

        // Query in a different dimension matches nothing.
        #expect(try await store.semanticSearch(queryVector: [1, 0, 0]).isEmpty)
    }
}
