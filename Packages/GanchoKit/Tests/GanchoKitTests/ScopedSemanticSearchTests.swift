import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Scoped semantic retrieval")
struct ScopedSemanticSearchTests {
    private func store() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "scope-\(UUID())")))
        try store.migrate()
        return store
    }

    @Test func everyPredicateAppliesBeforeTopK() async throws {
        let store = try store()
        let board = try await store.createPinboard(name: "Scope", sfSymbol: "folder")
        for index in 0..<20 {
            let excluded = ClipItem(preview: "Excluded", contentHash: "out-\(index)")
            try await store.insert(excluded, content: .text("Excluded"))
            try await store.saveEmbedding(clipID: excluded.id, vector: [1, 0])
        }
        let eligible = ClipItem(
            kind: .code, preview: "Eligible", contentHash: "eligible",
            sourceAppBundleID: "test.editor", isPinned: true)
        try await store.insert(eligible, content: .text("Eligible"))
        try await store.assign(clipID: eligible.id, toBoard: board.id)
        try await store.saveEmbedding(clipID: eligible.id, vector: [0.5, 1])
        let window =
            eligible.createdAt.addingTimeInterval(-1)...eligible.createdAt.addingTimeInterval(1)
        let query = ClipSearchQuery(
            text: "irrelevant lexical predicate", kinds: [.code], sourceAppBundleID: "test.editor",
            dateRange: window, boardID: board.id,
            markedOnly: true, pinnedOnly: true, includedIDs: [eligible.id])
        #expect(
            try await store.semanticSearch(queryVector: [1, 0], query: query, topK: 1).map(\.id)
                == [eligible.id])
        #expect(
            try await store.semanticSearch(
                queryVector: [1, 0], query: ClipSearchQuery(text: "", includedIDs: []), topK: 1
            ).isEmpty)
    }

    @Test func protectedExpiredAndArchivedRowsCannotConsumeLimit() async throws {
        let store = try store()
        let safe = ClipItem(preview: "Safe", contentHash: "safe")
        let forbidden = [
            ClipItem(kind: .secret, preview: "Protected", contentHash: "kind"),
            ClipItem(preview: "Sensitive", contentHash: "detector", isSensitive: true),
            ClipItem(preview: "Expired", contentHash: "expired", expiresAt: .distantPast)
        ]
        for item in forbidden + [safe] {
            try await store.insert(item, content: .text(item.preview))
            try await store.saveEmbedding(
                clipID: item.id, vector: item.id == safe.id ? [0.5, 1] : [1, 0])
        }
        #expect(try await store.semanticSearch(queryVector: [1, 0], topK: 1).map(\.id) == [safe.id])
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?", arguments: [safe.id.uuidString])
        }
        #expect(try await store.semanticSearch(queryVector: [1, 0], topK: 1).isEmpty)
    }

    @Test func tiesAndNonFiniteVectorsAreDeterministic() async throws {
        let store = try store()
        let earlier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        let later = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        for id in [later, earlier] {
            let item = ClipItem(id: id, preview: "Tied", contentHash: id.uuidString)
            try await store.insert(item, content: .text("Tied"))
            try await store.saveEmbedding(clipID: id, vector: [1, 0])
        }
        #expect(try await store.semanticSearch(queryVector: [1, 0], topK: 1).map(\.id) == [earlier])
        #expect(
            try await store.semanticSearch(queryVector: [1, 0], topK: 2).map(\.id) == [
                earlier, later
            ])
        #expect(try await store.semanticSearch(queryVector: [.nan, 0]).isEmpty)
        #expect(try await store.semanticSearch(queryVector: [.infinity, 0]).isEmpty)
    }
    @Test func coverageCountsOnlyScopedCurrentTextEmbeddings() async throws {
        let store = try store()
        let eligible = ClipItem(
            kind: .code, contentHash: "indexed", sourceAppBundleID: "test.editor")
        let missing = ClipItem(
            kind: .code, contentHash: "missing", sourceAppBundleID: "test.editor")
        let foreign = ClipItem(contentHash: "foreign", sourceAppBundleID: "other")
        let protected = ClipItem(contentHash: "private", isSensitive: true)
        for item in [eligible, missing, foreign, protected] {
            try await store.insert(item, content: .text("Synthetic"))
        }
        try await store.saveEmbedding(clipID: eligible.id, vector: [1, 0])
        let query = ClipSearchQuery(text: "", kinds: [.code], sourceAppBundleID: "test.editor")
        #expect(
            try await store.semanticIndexCoverage(query: query, dimension: 2)
                == SemanticIndexCoverage(eligible: 2, indexed: 1))
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip_embedding SET modelVersion = -1 WHERE clipID = ?",
                arguments: [eligible.id.uuidString])
        }
        #expect(try await store.semanticIndexCoverage(query: query, dimension: 2).indexed == 0)
        #expect(try await store.semanticIndexCoverage(query: query, dimension: 3).indexed == 0)
    }

}
