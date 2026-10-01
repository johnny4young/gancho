import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Atomic snippet draft persistence")
struct SnippetDraftPersistenceTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "recovery-\(UUID())")))
        try store.migrate()
        return store
    }

    @Test("Deletion and demotion reject late writes without resurrection")
    func unavailableOriginal() async throws {
        let store = try makeStore()
        let removed = try await store.saveSnippet(title: "Removed", text: "Old")
        try await store.delete(id: removed.id)
        #expect(
            !(try await store.updateSnippetDraft(
                id: removed.id, title: "Late", text: "Late", keyword: "late")))
        #expect(try await store.item(id: removed.id) == nil)
        let demoted = try await store.saveSnippet(title: "Demoted", text: "Old")
        try await store.demoteFromSnippet(id: demoted.id)
        #expect(
            !(try await store.updateSnippetDraft(
                id: demoted.id, title: "Late", text: "Late", keyword: "late")))
        #expect(try await store.content(for: demoted.id) == .text("Old"))
    }

    @Test("Title, body and keyword commit together; changed text invalidates its vector")
    func atomicFields() async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Before", text: "Before")
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])
        #expect(
            try await store.updateSnippetDraft(
                id: item.id, title: "After", text: "After", keyword: "  after  "))
        let updated = try #require(try await store.item(id: item.id))
        #expect(updated.title == "After")
        #expect(updated.keyword == "after")
        #expect(try await store.content(for: item.id) == .text("After"))
        #expect(try await store.semanticSearch(queryVector: [1, 0]).isEmpty)
    }

    @Test("Recovery never deduplicates onto another clip")
    func explicitNewIdentity() async throws {
        let store = try makeStore()
        let existing = ClipItem(preview: "Hello", contentHash: "same")
        try await store.insert(existing, content: .text("Hello"))
        let recovered = ClipItem(title: "Recovered", preview: "Hello", contentHash: "same")
        let saved = try await store.saveRecoveredSnippet(
            item: recovered, text: "Hello", keyword: "hi", isPro: false)
        #expect(saved.id == recovered.id)
        #expect(saved.id != existing.id)
        #expect(try await store.count() == 2)
        #expect(try await store.snippets().map(\.id) == [saved.id])
        #expect(saved.keyword == "hi")
    }

    @Test("The free ceiling is enforced in the insertion transaction")
    func freeCeiling() async throws {
        let store = try makeStore()
        for index in 0..<SnippetLimits.freeMaxSnippets {
            _ = try await store.saveSnippet(title: "Seed", text: "Seed \(index)")
        }
        let item = ClipItem(preview: "New", contentHash: "new")
        await #expect(throws: SnippetDraftSaveError.freeLimitReached) {
            try await store.saveRecoveredSnippet(
                item: item, text: "New", keyword: nil, isPro: false)
        }
        #expect(try await store.item(id: item.id) == nil)
        _ = try await store.saveRecoveredSnippet(item: item, text: "New", keyword: nil, isPro: true)
    }

    @Test("Protected originals and recovered items cannot be written")
    func protectedContent() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .jwt, preview: "masked", contentHash: "protected")
        try await store.insert(item, content: .text("synthetic token"))
        try await store.promoteToSnippet(id: item.id)
        await #expect(throws: SnippetDraftSaveError.protectedContent) {
            try await store.updateSnippetDraft(
                id: item.id, title: "Unsafe", text: "Unsafe", keyword: nil)
        }
        await #expect(throws: SnippetDraftSaveError.protectedContent) {
            try await store.saveRecoveredSnippet(
                item: item, text: "Unsafe", keyword: nil, isPro: true)
        }
        #expect(try await store.content(for: item.id) == .text("synthetic token"))
    }

    @Test("A failed transaction leaves every edited field and embedding intact")
    func writeFailureRollsBack() async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Original", text: "Original")
        try await store.saveEmbedding(clipID: item.id, vector: [1, 0])
        try await store.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_vector_delete BEFORE DELETE ON clip_embedding
                    BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END
                    """)
        }
        await #expect(throws: DatabaseError.self) {
            try await store.updateSnippetDraft(
                id: item.id, title: "Changed", text: "Changed", keyword: "changed")
        }
        let unchanged = try #require(try await store.item(id: item.id))
        #expect(unchanged.title == "Original")
        #expect(unchanged.keyword == nil)
        #expect(try await store.content(for: item.id) == .text("Original"))
        #expect(try await store.semanticSearch(queryVector: [1, 0]).count == 1)
    }

    @Test("Concurrent recovery cannot exceed the free ceiling")
    func concurrentRecoveryCeiling() async throws {
        let store = try makeStore()
        for index in 0..<(SnippetLimits.freeMaxSnippets - 1) {
            _ = try await store.saveSnippet(title: "Seed", text: "Seed \(index)")
        }
        let successes = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<2 {
                group.addTask {
                    do {
                        _ = try await store.saveRecoveredSnippet(
                            item: ClipItem(preview: "New", contentHash: "new-\(index)"),
                            text: "New", keyword: nil, isPro: false)
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await saved in group where saved { count += 1 }
            return count
        }
        #expect(successes == 1)
        #expect(try await store.snippets().count == SnippetLimits.freeMaxSnippets)
    }

    @Test("Cancellation before delivery leaves the original untouched")
    func cancellation() async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Original", text: "Original")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.updateSnippetDraft(
                id: item.id, title: "Late", text: "Late", keyword: "late")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.content(for: item.id) == .text("Original"))
    }
}
