import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Content-bound embedding persistence")
struct ContentBoundEmbeddingTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("embedding-body-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test func anEditCannotBeFollowedByAnOldVector() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "old", contentHash: "body-race")
        try await store.insert(item, content: .text("old"))
        try await store.updateClipText(id: item.id, text: "new")

        #expect(
            !(try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "old")))
        #expect(try await store.semanticSearch(queryVector: [1, 0]).isEmpty)
        #expect(
            try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [0, 1], expectedText: "new"))
        #expect(try await store.semanticSearch(queryVector: [0, 1]).map(\.id) == [item.id])
    }

    @Test func titleAndContentEqualABAChangesKeepValidBodyEvidence() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "body", contentHash: "body-aba")
        try await store.insert(item, content: .text("body"))
        try await store.updateTitle(id: item.id, title: "New title")
        try await store.updateClipText(id: item.id, text: "temporary")
        try await store.updateClipText(id: item.id, text: "body")
        #expect(
            try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "body"))
    }

    @Test func deletedAndRecreatedIdentityRequiresCurrentBodyEvidence() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "old", contentHash: "recreated-body")
        try await store.insert(item, content: .text("old"))
        try await store.delete(id: item.id)
        #expect(
            !(try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "old")))
        try await store.insert(item, content: .text("new"))
        #expect(
            !(try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "old")))
        #expect(
            try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [0, 1], expectedText: "new"))
        try await store.delete(id: item.id)
        try await store.insert(item, content: .text("old"))
        #expect(
            try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "old"))
    }

    @Test func expiredRowsThatRetentionKeepsStayIndexable() async throws {
        // Reads keep a pinned, boarded, or snippet row visible past its expiry,
        // so the guarded write must accept that row's current body as main did.
        let store = try makeStore()
        let item = ClipItem(preview: "body", contentHash: "curated-expired")
        try await store.insert(item, content: .text("body"))
        try await store.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE clip SET isPinned = 1, expiresAt = '2000-01-01 00:00:00.000'
                    WHERE id = ?
                    """,
                arguments: [item.id.uuidString])
        }
        #expect(
            try await store.saveEmbeddingIfCurrent(
                clipID: item.id, vector: [1, 0], expectedText: "body"))
    }

    @Test func changedPrivacyAndExpiryRejectEvenAnIdenticalBody() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "body", contentHash: "protected-body")
        try await store.insert(item, content: .text("body"))
        let mutations = [
            "isSensitive = 1", "kind = 'jwt'", "isArchived = 1",
            "expiresAt = '2000-01-01 00:00:00.000'", "contentTypeIdentifier = 'public.file-url'"
        ]
        for mutation in mutations {
            try await store.writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE clip SET isSensitive = 0, kind = 'text', isArchived = 0,
                            expiresAt = NULL, contentTypeIdentifier = NULL WHERE id = ?
                        """,
                    arguments: [item.id.uuidString])
                try db.execute(
                    sql: "UPDATE clip SET \(mutation) WHERE id = ?",
                    arguments: [item.id.uuidString])
            }
            #expect(
                !(try await store.saveEmbeddingIfCurrent(
                    clipID: item.id, vector: [1, 0], expectedText: "body")),
                "Accepted changed eligibility: \(mutation)")
        }
    }
}
