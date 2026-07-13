import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum CurationStoreFailure: Error, Hashable {
    case pinCount
    case setPinned
    case snippetCount
    case promote
}

private actor CurationStoreSpy:
    ClipReading, ClipMutating, StoreStatsProviding, SnippetStoring
{
    private var item: ClipItem?
    private var pinCount: Int
    private var snippetCountValue: Int
    private let failures: Set<CurationStoreFailure>
    private(set) var setPinnedCalls: [Bool] = []
    private(set) var promoteCalls = 0

    init(
        item: ClipItem?,
        pinCount: Int = 0,
        snippetCount: Int = 0,
        failures: Set<CurationStoreFailure> = []
    ) {
        self.item = item
        self.pinCount = pinCount
        self.snippetCountValue = snippetCount
        self.failures = failures
    }

    func currentItem() -> ClipItem? { item }

    func items(offset _: Int, limit _: Int) async throws -> [ClipItem] {
        item.map { [$0] } ?? []
    }

    func items(ids: [UUID]) async throws -> [ClipItem] {
        guard let item, ids.contains(item.id) else { return [] }
        return [item]
    }

    func recentForBrowse(offset _: Int, limit _: Int) async throws -> [ClipItem] {
        item.map { [$0] } ?? []
    }

    func item(id: UUID) async throws -> ClipItem? {
        item?.id == id ? item : nil
    }

    func content(for _: UUID) async throws -> ClipContent? { nil }
    func count() async throws -> Int { item == nil ? 0 : 1 }
    func thumbnailData(for _: UUID) async throws -> Data? { nil }

    @discardableResult
    func insert(_ item: ClipItem, content _: ClipContent?) async throws -> ClipItem {
        self.item = item
        return item
    }

    func delete(id _: UUID) async throws { item = nil }
    func deleteForSync(id _: UUID, now _: Date) async throws { item = nil }
    func deleteAllSensitive() async throws -> Int { 0 }

    func setPinned(id: UUID, _ pinned: Bool) async throws {
        if failures.contains(.setPinned) { throw CurationStoreFailure.setPinned }
        guard var item, item.id == id else { return }
        item.isPinned = pinned
        self.item = item
        setPinnedCalls.append(pinned)
    }

    func recordUse(id _: UUID, now _: Date) async throws {}

    func pinnedCount() async throws -> Int {
        if failures.contains(.pinCount) { throw CurationStoreFailure.pinCount }
        return pinCount
    }

    func sensitiveCount() async throws -> Int { 0 }
    func archivedCount() async throws -> Int { 0 }
    func syncedCount() async throws -> Int { 0 }
    func purgedItemCount(since _: Date) async throws -> Int { 0 }

    func promoteToSnippet(id _: UUID, title _: String?) async throws {
        if failures.contains(.promote) { throw CurationStoreFailure.promote }
        promoteCalls += 1
    }

    func demoteFromSnippet(id _: UUID) async throws {}
    func snippets() async throws -> [ClipItem] { [] }

    func snippetCount() async throws -> Int {
        if failures.contains(.snippetCount) { throw CurationStoreFailure.snippetCount }
        return snippetCountValue
    }

    func saveSnippet(title: String, text _: String, language _: String?) async throws -> ClipItem {
        ClipItem(title: title)
    }

    func updateSnippet(id _: UUID, title _: String, text _: String) async throws {}
    func setKeyword(id _: UUID, keyword _: String?) async throws {}
    func incrementUses(id _: UUID) async throws {}
    func snippet(matchingKeyword _: String) async throws -> ClipItem? { nil }
}

private actor CurationEngineSpy: SyncEngine {
    private(set) var enqueuedItemIDs: [UUID] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueuedItemIDs += items.map(\.id) }
    func enqueueDeletion(ids _: [UUID]) async {}
    func enqueue(boards _: [Pinboard]) async {}
    func enqueueBoardDeletion(ids _: [UUID]) async {}
}

@Suite("Clip curation controller — shared pin and snippet policy")
struct ClipCurationControllerTests {
    private let controller = ClipCurationController()

    @Test("Pin success mutates once and immediately enqueues the clip")
    func pinSuccess() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let store = CurationStoreSpy(item: item)
        let engine = CurationEngineSpy()

        let outcome = await controller.togglePin(
            item, tier: .free, store: store, engine: engine)

        #expect(outcome == .pinned)
        #expect(await store.setPinnedCalls == [true])
        #expect(await store.currentItem()?.isPinned == true)
        #expect(await engine.enqueuedItemIDs == [item.id])
    }

    @Test("Unpin bypasses the free limit and enqueues the mutation")
    func unpinBypassesLimit() async {
        let item = ClipItem(
            preview: "clip", contentHash: "clip", isPinned: true)
        let store = CurationStoreSpy(item: item, pinCount: PinLimits.freeMaxPins)
        let engine = CurationEngineSpy()

        let outcome = await controller.togglePin(
            item, tier: .free, store: store, engine: engine)

        #expect(outcome == .unpinned)
        #expect(await store.setPinnedCalls == [false])
        #expect(await engine.enqueuedItemIDs == [item.id])
    }

    @Test("Free pin limit blocks the write and sync enqueue")
    func pinLimit() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let store = CurationStoreSpy(item: item, pinCount: PinLimits.freeMaxPins)
        let engine = CurationEngineSpy()

        let outcome = await controller.togglePin(
            item, tier: .free, store: store, engine: engine)

        #expect(outcome == .freeLimitReached)
        #expect(await store.setPinnedCalls.isEmpty)
        #expect(await engine.enqueuedItemIDs.isEmpty)
    }

    @Test("A stale pin snapshot is an idempotent no-op")
    func stalePinSnapshot() async {
        let stored = ClipItem(
            preview: "clip", contentHash: "clip", isPinned: true)
        var stale = stored
        stale.isPinned = false
        let store = CurationStoreSpy(item: stored)
        let engine = CurationEngineSpy()

        let outcome = await controller.togglePin(
            stale, tier: .free, store: store, engine: engine)

        #expect(outcome == .alreadyPinned)
        #expect(await store.setPinnedCalls.isEmpty)
        #expect(await engine.enqueuedItemIDs.isEmpty)
    }

    @Test("Unavailable clips and pin store failures never enqueue")
    func unavailableAndFailure() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let unavailableStore = CurationStoreSpy(item: nil)
        let unavailableEngine = CurationEngineSpy()
        let countFailureStore = CurationStoreSpy(item: item, failures: [.pinCount])
        let countFailureEngine = CurationEngineSpy()
        let failingStore = CurationStoreSpy(item: item, failures: [.setPinned])
        let failingEngine = CurationEngineSpy()

        let unavailable = await controller.togglePin(
            item, tier: .pro, store: unavailableStore, engine: unavailableEngine)
        let countFailed = await controller.togglePin(
            item, tier: .free, store: countFailureStore, engine: countFailureEngine)
        let failed = await controller.togglePin(
            item, tier: .pro, store: failingStore, engine: failingEngine)

        #expect(unavailable == .clipUnavailable)
        #expect(countFailed == .failed)
        #expect(failed == .failed)
        #expect(await unavailableEngine.enqueuedItemIDs.isEmpty)
        #expect(await countFailureEngine.enqueuedItemIDs.isEmpty)
        #expect(await failingEngine.enqueuedItemIDs.isEmpty)
    }

    @Test("Snippet promotion succeeds below the limit")
    func snippetSuccess() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let store = CurationStoreSpy(
            item: item, snippetCount: SnippetLimits.freeMaxSnippets - 1)

        let outcome = await controller.promoteToSnippet(
            item, tier: .free, store: store)

        #expect(outcome == .promoted)
        #expect(await store.promoteCalls == 1)
    }

    @Test("Unavailable clips never report a successful snippet promotion")
    func snippetUnavailable() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let store = CurationStoreSpy(item: nil)

        let outcome = await controller.promoteToSnippet(
            item, tier: .pro, store: store)

        #expect(outcome == .clipUnavailable)
        #expect(await store.promoteCalls == 0)
    }

    @Test("Free snippet limit blocks promotion, while Pro bypasses it")
    func snippetLimit() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let blockedStore = CurationStoreSpy(
            item: item, snippetCount: SnippetLimits.freeMaxSnippets)
        let proStore = CurationStoreSpy(
            item: item, snippetCount: SnippetLimits.freeMaxSnippets)

        let blocked = await controller.promoteToSnippet(
            item, tier: .free, store: blockedStore)
        let promoted = await controller.promoteToSnippet(
            item, tier: .pro, store: proStore)

        #expect(blocked == .freeLimitReached)
        #expect(await blockedStore.promoteCalls == 0)
        #expect(promoted == .promoted)
        #expect(await proStore.promoteCalls == 1)
    }

    @Test("Snippet count and promotion failures never report success")
    func snippetFailures() async {
        let item = ClipItem(preview: "clip", contentHash: "clip")
        let countFailure = CurationStoreSpy(item: item, failures: [.snippetCount])
        let writeFailure = CurationStoreSpy(item: item, failures: [.promote])

        let countOutcome = await controller.promoteToSnippet(
            item, tier: .free, store: countFailure)
        let writeOutcome = await controller.promoteToSnippet(
            item, tier: .free, store: writeFailure)

        #expect(countOutcome == .failed)
        #expect(writeOutcome == .failed)
        #expect(await countFailure.promoteCalls == 0)
        #expect(await writeFailure.promoteCalls == 0)
    }
}
