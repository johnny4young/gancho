import Foundation
import GRDB
@_spi(GanchoInternal) import GanchoKit
import Testing

@testable import GanchoAppCore

private actor EnqueueSpy: SyncEngine {
    private(set) var enqueued: [[UUID]] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueued.append(items.map(\.id)) }
    func enqueueDeletion(ids _: [UUID]) async {}
    func enqueue(boards _: [Pinboard]) async {}
    func enqueueBoardDeletion(ids _: [UUID]) async {}
}

@Suite("Snippet draft controller — write, then sync")
struct SnippetDraftControllerTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("snippet-draft-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("A saved draft is written, then enqueued for sync")
    func savedDraftIsEnqueued() async throws {
        let store = try makeStore()
        let engine = EnqueueSpy()
        let snippet = try await store.saveSnippet(title: "Before", text: "Before")

        let saved = try await SnippetDraftController().save(
            id: snippet.id, fields: .init(title: "After", keyword: "", body: "After"),
            store: store, engine: engine)

        #expect(saved)
        #expect(try await store.content(for: snippet.id) == .text("After"))
        #expect(await engine.enqueued == [[snippet.id]])
    }

    @Test("A draft whose snippet is gone writes and enqueues nothing")
    func missingSnippetIsNotEnqueued() async throws {
        let store = try makeStore()
        let engine = EnqueueSpy()
        let snippet = try await store.saveSnippet(title: "Gone", text: "Gone")
        try await store.delete(id: snippet.id)

        let saved = try await SnippetDraftController().save(
            id: snippet.id, fields: .init(title: "Late", keyword: "", body: "Late"),
            store: store, engine: engine)

        #expect(!saved)
        #expect(await engine.enqueued.isEmpty)
    }

    @Test("A recovered snippet is inserted, then enqueued for sync")
    func recoveredSnippetIsEnqueued() async throws {
        let store = try makeStore()
        let engine = EnqueueSpy()
        let prepared = try SnippetDraftRecovery.prepare(
            .init(title: "Recovered", body: "body"), sensitiveLifetime: 600,
            detectSecrets: true, fallbackTitle: "Recovered")

        let recovered = try await SnippetDraftController().saveRecovered(
            item: prepared.item, text: prepared.text, keyword: nil, isPro: true,
            store: store, engine: engine)

        #expect(try await store.snippets().map(\.id) == [recovered.id])
        #expect(await engine.enqueued == [[recovered.id]])
    }
}
