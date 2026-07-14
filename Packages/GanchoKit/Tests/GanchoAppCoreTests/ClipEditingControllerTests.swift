import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum EditingStoreFailure: Error { case write }

private actor EditingStoreSpy: ClipReading, ClipEnriching {
    var storedItem: ClipItem?
    var failsWrite = false
    private(set) var writtenTitles: [String] = []

    init(item: ClipItem?) { storedItem = item }

    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func items(ids: [UUID]) async throws -> [ClipItem] { [] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func item(id: UUID) async throws -> ClipItem? {
        storedItem?.id == id ? storedItem : nil
    }
    func content(for id: UUID) async throws -> ClipContent? { nil }
    func count() async throws -> Int { storedItem == nil ? 0 : 1 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }

    func updateTitle(id: UUID, title: String) async throws {
        guard !failsWrite else { throw EditingStoreFailure.write }
        guard var item = storedItem, item.id == id else { return }
        writtenTitles.append(title)
        item.title = title
        storedItem = item
    }

    func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool { false }
    func attachExtractedText(id: UUID, text: String) async throws {}
    func updateClipText(id: UUID, text: String) async throws {}
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {}

    func failWrites() { failsWrite = true }
}

private actor EditingSyncSpy: SyncEngine {
    private(set) var enqueuedIDs: [UUID] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueuedIDs += items.map(\.id) }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

@Suite("Clip editing controller — durable title edits")
struct ClipEditingControllerTests {
    private let controller = ClipEditingController()

    @Test("A changed title is trimmed, persisted, then enqueued")
    func changedTitlePersistsAndEnqueues() async {
        let item = ClipItem(title: "Old", preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item)
        let sync = EditingSyncSpy()

        let outcome = await controller.updateTitle(
            item, title: "  New title\n", store: store, engine: sync)

        #expect(outcome == .saved)
        #expect(await store.writtenTitles == ["New title"])
        #expect(await sync.enqueuedIDs == [item.id])
    }

    @Test("Whitespace intentionally clears a title")
    func whitespaceClearsTitle() async {
        let item = ClipItem(title: "Generated", preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item)

        let outcome = await controller.updateTitle(
            item, title: " \n ", store: store, engine: NoopSyncEngine())

        #expect(outcome == .saved)
        #expect(await store.writtenTitles == [""])
    }

    @Test("An unchanged title performs no write or sync")
    func unchangedTitleIsNoOp() async {
        let item = ClipItem(title: "Stable", preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item)
        let sync = EditingSyncSpy()

        let outcome = await controller.updateTitle(
            item, title: " Stable ", store: store, engine: sync)

        #expect(outcome == .unchanged)
        #expect(await store.writtenTitles.isEmpty)
        #expect(await sync.enqueuedIDs.isEmpty)
    }

    @Test("Missing and failed writes never enqueue")
    func failedWritesNeverEnqueue() async {
        let item = ClipItem(title: "Old", preview: "body", contentHash: "body")
        let missingStore = EditingStoreSpy(item: nil)
        let failingStore = EditingStoreSpy(item: item)
        await failingStore.failWrites()
        let sync = EditingSyncSpy()

        let missing = await controller.updateTitle(
            item, title: "New", store: missingStore, engine: sync)
        let failed = await controller.updateTitle(
            item, title: "New", store: failingStore, engine: sync)

        #expect(missing == .clipUnavailable)
        #expect(failed == .failed)
        #expect(await sync.enqueuedIDs.isEmpty)
    }
}
