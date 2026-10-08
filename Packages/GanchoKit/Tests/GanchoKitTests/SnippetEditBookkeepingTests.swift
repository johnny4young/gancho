import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Snippet edit sync and semantic bookkeeping")
struct SnippetEditBookkeepingTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("snippet-edit-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test func editedUploadedSnippetQueuesUploadAndInvalidatesOldVector() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Old", text: "old body")
        try await store.saveEmbedding(clipID: snippet.id, vector: [1, 0])
        try await store.markUploaded(id: snippet.id, systemFields: Data([1]))
        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.semanticSearch(queryVector: [1, 0]).count == 1)

        try await store.updateSnippet(id: snippet.id, title: "New", text: "new body")

        #expect(try await store.pendingUploadIDs() == [snippet.id])
        #expect(try await store.content(for: snippet.id) == .text("new body"))
        #expect(try await store.semanticSearch(queryVector: [1, 0]).isEmpty)
        #expect(try await store.search(ClipSearchQuery(text: "new")).map(\.id) == [snippet.id])
    }

    @Test func titleOnlyEditPreservesBodyVector() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Old", text: "body")
        try await store.saveEmbedding(clipID: snippet.id, vector: [1, 0])
        try await store.markUploaded(id: snippet.id, systemFields: Data([1]))

        try await store.updateSnippet(id: snippet.id, title: "New", text: "body")

        #expect(try await store.pendingUploadIDs() == [snippet.id])
        #expect(try await store.semanticSearch(queryVector: [1, 0]).count == 1)
    }

    @Test func unchangedSaveKeepsRevisionAndSyncState() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Title", text: "body")
        try await store.markUploaded(id: snippet.id, systemFields: Data([1]))
        let before = try #require(try await store.item(id: snippet.id))

        try await store.updateSnippet(id: snippet.id, title: "Title", text: "body")

        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.item(id: snippet.id)?.contextRevision == before.contextRevision)
    }

    @Test func demotedAndMissingRowsRemainNoOps() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Old", text: "body")
        try await store.demoteFromSnippet(id: snippet.id)
        try await store.saveEmbedding(clipID: snippet.id, vector: [1, 0])
        try await store.markUploaded(id: snippet.id, systemFields: Data([1]))

        try await store.updateSnippet(id: snippet.id, title: "New", text: "changed")
        try await store.updateSnippet(id: UUID(), title: "Missing", text: "missing")

        #expect(try await store.content(for: snippet.id) == .text("body"))
        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.semanticSearch(queryVector: [1, 0]).count == 1)
    }

    @Test func vectorDeletionFailureRollsBackEditAndUploadFlag() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Old", text: "body")
        try await store.saveEmbedding(clipID: snippet.id, vector: [1, 0])
        try await store.markUploaded(id: snippet.id, systemFields: Data([1]))
        try await store.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_vector_delete BEFORE DELETE ON clip_embedding
                    BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END
                    """)
        }

        await #expect(throws: DatabaseError.self) {
            try await store.updateSnippet(id: snippet.id, title: "New", text: "changed")
        }

        #expect(try await store.item(id: snippet.id)?.title == "Old")
        #expect(try await store.content(for: snippet.id) == .text("body"))
        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.semanticSearch(queryVector: [1, 0]).count == 1)
    }
}
