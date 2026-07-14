import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum EditingStoreFailure: Error { case write }

private actor EditingStoreSpy: ClipReading, ClipEnriching {
    var storedItem: ClipItem?
    var storedContent: ClipContent?
    var failsWrite = false
    private(set) var writtenTitles: [String] = []
    private(set) var writtenTexts: [String] = []

    init(item: ClipItem?, content: ClipContent? = .text("body")) {
        storedItem = item
        storedContent = content
    }

    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func items(ids: [UUID]) async throws -> [ClipItem] { [] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func item(id: UUID) async throws -> ClipItem? {
        storedItem?.id == id ? storedItem : nil
    }
    func content(for id: UUID) async throws -> ClipContent? {
        storedItem?.id == id ? storedContent : nil
    }
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
    func updateClipText(id: UUID, text: String) async throws {
        guard !failsWrite else { throw EditingStoreFailure.write }
        guard var item = storedItem, item.id == id else { return }
        writtenTexts.append(text)
        storedContent = .text(text)
        item.preview = String(text.prefix(120))
        storedItem = item
    }
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

@Suite("Clip editing controller — durable user edits")
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

    @Test("A changed text body is preserved exactly, persisted, then enqueued")
    func changedTextPersistsAndEnqueues() async {
        let item = ClipItem(preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item, content: .text("body"))
        let sync = EditingSyncSpy()
        let edited = "  first line\nsecond line  "

        let outcome = await controller.updateText(
            item, text: edited, store: store, engine: sync)

        #expect(outcome == .saved)
        #expect(await store.writtenTexts == [edited])
        #expect(await sync.enqueuedIDs == [item.id])
    }

    @Test("Unchanged and blank text never write or sync")
    func unchangedAndBlankTextAreNoOps() async {
        let item = ClipItem(preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item, content: .text("body"))
        let sync = EditingSyncSpy()

        let unchanged = await controller.updateText(
            item, text: "body", store: store, engine: sync)
        let blank = await controller.updateText(
            item, text: " \n ", store: store, engine: sync)

        #expect(unchanged == .unchanged)
        #expect(blank == .emptyContent)
        #expect(await store.writtenTexts.isEmpty)
        #expect(await sync.enqueuedIDs.isEmpty)
    }

    @Test("Sensitive and binary clips stay read-only")
    func sensitiveAndBinaryClipsAreReadOnly() async {
        let sensitive = ClipItem(
            kind: .secret, preview: "••••", contentHash: "secret", isSensitive: true)
        let binary = ClipItem(kind: .image, preview: "Image", contentHash: "image")
        let sensitiveStore = EditingStoreSpy(
            item: sensitive, content: .text("never expose"))
        let binaryStore = EditingStoreSpy(
            item: binary, content: .binary(data: Data([1, 2, 3]), typeIdentifier: "public.png"))
        let sync = EditingSyncSpy()

        let sensitiveOutcome = await controller.updateText(
            sensitive, text: "replace", store: sensitiveStore, engine: sync)
        let binaryOutcome = await controller.updateText(
            binary, text: "replace", store: binaryStore, engine: sync)

        #expect(sensitiveOutcome == .notEditable)
        #expect(binaryOutcome == .notEditable)
        #expect(await sensitiveStore.writtenTexts.isEmpty)
        #expect(await binaryStore.writtenTexts.isEmpty)
        #expect(await sync.enqueuedIDs.isEmpty)
    }

    @Test("Masked-preview kinds stay read-only even when not flagged sensitive")
    func maskedKindsAreReadOnly() async {
        // A lone JWT / card number classifies to a masked kind but is NOT
        // flagged `isSensitive`; the editability guard must still refuse it.
        for kind in [ClipContentKind.jwt, .creditCard] {
            let item = ClipItem(kind: kind, preview: "•••", contentHash: "masked-\(kind.rawValue)")
            let store = EditingStoreSpy(item: item, content: .text("eyJ.raw.token"))
            let sync = EditingSyncSpy()

            let outcome = await controller.updateText(
                item, text: "replace", store: store, engine: sync)

            #expect(outcome == .notEditable, "\(kind.rawValue) must be read-only")
            #expect(await store.writtenTexts.isEmpty)
            #expect(await sync.enqueuedIDs.isEmpty)
        }
    }

    @Test("Failed text writes never enqueue")
    func failedTextWriteNeverEnqueues() async {
        let item = ClipItem(preview: "body", contentHash: "body")
        let store = EditingStoreSpy(item: item, content: .text("body"))
        await store.failWrites()
        let sync = EditingSyncSpy()

        let outcome = await controller.updateText(
            item, text: "new body", store: store, engine: sync)

        #expect(outcome == .failed)
        #expect(await sync.enqueuedIDs.isEmpty)
    }
}
