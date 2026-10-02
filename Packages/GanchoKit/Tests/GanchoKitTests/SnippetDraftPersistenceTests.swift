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

    @Test(
        "Editing uploaded snippet content queues its shared fields for sync",
        arguments: [
            ("Changed", "Original"), ("Original", "Changed body"), ("Changed", "Changed body")
        ])
    func editedSharedFieldsArePending(title: String, text: String) async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Original", text: "Original")
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        #expect(try await store.pendingUploads().isEmpty)
        #expect(
            try await store.updateSnippetDraft(
                id: item.id, title: title, text: text, keyword: "local"))
        let pending = try await store.pendingUploads()
        #expect(pending.map(\.item.id) == [item.id])
        #expect(pending.first?.item.title == title)
        #expect(pending.first?.content == .text(text))
    }

    @Test("Local-only keyword edits neither queue an upload nor clear an existing one")
    func keywordKeepsSyncState() async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Original", text: "Original")
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        #expect(
            try await store.updateSnippetDraft(
                id: item.id, title: "Original", text: "Original", keyword: "local"))
        #expect(try await store.pendingUploads().isEmpty)
        try await store.markNeedsUpload(id: item.id)
        #expect(
            try await store.updateSnippetDraft(
                id: item.id, title: "Original", text: "Original", keyword: "another"))
        #expect(try await store.pendingUploads().map(\.item.id) == [item.id])
    }

    @Test("A local keyword edit cannot outrank a newer remote shared-field edit")
    func keywordDoesNotAdvanceSharedRevision() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let original = ClipItem(updatedAt: base, title: "Original", preview: "Original")
        let item = try await store.saveRecoveredSnippet(
            item: original, text: "Original", keyword: nil, isPro: true)
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        #expect(
            try await store.updateSnippetDraft(
                id: item.id, title: "Original", text: "Original", keyword: "local"))
        #expect(try await store.item(id: item.id)?.updatedAt == base)
        var remote = original
        remote.updatedAt = base.addingTimeInterval(1)
        remote.title = "Remote title"
        #expect(
            try await store.applyRemoteUpsert(
                remote, content: .text("Remote body"), systemFields: Data([2])))
        let current = try #require(try await store.item(id: item.id))
        #expect(current.title == "Remote title")
        #expect(current.keyword == "local")
        #expect(try await store.snippets().map(\.id) == [item.id])
        #expect(try await store.content(for: item.id) == .text("Remote body"))
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

    @Test("Expired originals and recovered drafts cannot be saved")
    func expiredContent() async throws {
        let store = try makeStore()
        let item = try await store.saveSnippet(title: "Original", text: "Original")
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET expiresAt = ? WHERE id = ?",
                arguments: [Date.distantPast, item.id.uuidString])
        }
        await #expect(throws: SnippetDraftSaveError.protectedContent) {
            try await store.updateSnippetDraft(
                id: item.id, title: "Late", text: "Late", keyword: nil)
        }
        let expired = ClipItem(preview: "Expired", expiresAt: .distantPast)
        await #expect(throws: SnippetDraftSaveError.protectedContent) {
            try await store.saveRecoveredSnippet(
                item: expired, text: "Expired", keyword: nil, isPro: true)
        }
        #expect(try await store.item(id: expired.id) == nil)
        let stored = try await store.writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT contentText FROM clip WHERE id = ?",
                arguments: [item.id.uuidString])
        }
        #expect(stored == "Original")
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
