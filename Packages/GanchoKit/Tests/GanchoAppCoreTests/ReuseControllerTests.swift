import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor ReuseStoreSpy: ClipboardStore, ReuseUsageStoring {
    private var storage: [ClipItem] = []
    private var searches: [String] = []
    private var events: [String] = []
    private var deleteCount = 0

    func seed(_ items: [ClipItem]) {
        storage = items
    }

    func eventLog() -> [String] { events }
    func storedIDs() -> [UUID] { storage.map(\.id) }
    func deletionCount() -> Int { deleteCount }

    @discardableResult
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        events.append("insert:\(item.preview)")
        var stored = item
        if content == nil, let current = storage.first(where: { $0.id == item.id }) {
            // Match GRDB's metadata-only move-to-top semantics: a stale view
            // snapshot must not erase the use signal written immediately before.
            stored.uses = current.uses
            stored.lastUsedAt = current.lastUsedAt
        }
        storage.removeAll { $0.id == item.id }
        storage.insert(stored, at: 0)
        return stored
    }

    func items(offset: Int, limit: Int) async throws -> [ClipItem] {
        Array(storage.dropFirst(offset).prefix(limit))
    }

    func count() async throws -> Int { storage.count }

    func delete(id: UUID) async throws {
        deleteCount += 1
        storage.removeAll { $0.id == id }
    }

    func content(for _: UUID) async throws -> ClipContent? { nil }
    func exportJSON() async throws -> Data { Data() }
    func exportCSV() async throws -> Data { Data() }

    func recordUseAndSnippetSuggestion(
        id: UUID, now: Date, requiredUses: Int
    ) async throws -> ClipItem? {
        guard let index = storage.firstIndex(where: { $0.id == id }) else {
            events.append("use:missing")
            return nil
        }
        let preview = storage[index].preview
        events.append("use:\(preview)")
        storage[index].uses += 1
        storage[index].lastUsedAt = now
        let updated = storage[index]
        guard updated.uses == requiredUses, !updated.isSensitive else { return nil }
        return updated
    }

    func recordSearch(_ query: String, now _: Date) async throws {
        searches.removeAll { $0 == query }
        searches.insert(query, at: 0)
        events.append("search:\(query)")
    }

    func recentSearches(limit: Int) async throws -> [String] {
        Array(searches.prefix(limit))
    }

    func clearSearchHistory() async throws {
        searches.removeAll()
        events.append("clear-searches")
    }
}

@MainActor
private final class ReuseRecorder {
    var recentSnapshots: [[UUID]] = []
    var rememberValues: [Bool] = []
}

@Suite("Reuse controller — recent history and actions")
@MainActor
struct ReuseControllerTests {
    private func clip(_ preview: String) -> ClipItem {
        ClipItem(preview: preview, contentHash: preview)
    }

    private func makeController(
        store: ReuseStoreSpy,
        rememberSearches: Bool = true,
        deletionGrace: Duration = .seconds(6),
        recorder: ReuseRecorder = ReuseRecorder()
    ) -> ReuseController {
        let controller = ReuseController(
            store: store,
            usageStore: store,
            rememberSearches: rememberSearches,
            deletionCoordinator: DeletionCoordinator(grace: deletionGrace),
            onRememberSearchesChanged: { recorder.rememberValues.append($0) })
        controller.setRecentItemsObserver {
            recorder.recentSnapshots.append($0.map(\.id))
        }
        return controller
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("Refreshing publishes the store's recent metadata page")
    func refreshRecents() async {
        let store = ReuseStoreSpy()
        let recorder = ReuseRecorder()
        let first = clip("first")
        let second = clip("second")
        await store.seed([first, second])
        let controller = makeController(store: store, recorder: recorder)

        await controller.refreshRecents()

        #expect(controller.recentItems.map(\.id) == [first.id, second.id])
        #expect(recorder.recentSnapshots == [[first.id, second.id]])
    }

    @Test("A successful paste records use and search before moving the clip to the top")
    func recordPaste() async {
        let store = ReuseStoreSpy()
        let first = clip("first")
        let second = clip("second")
        await store.seed([first, second])
        let controller = makeController(store: store)
        controller.activeSearchQuery = "invoice"

        await controller.recordPaste(of: second, now: Date(timeIntervalSince1970: 100))

        #expect(await store.eventLog() == ["use:second", "search:invoice", "insert:second"])
        #expect(controller.activeSearchQuery.isEmpty)
        #expect(controller.recentItems.map(\.id) == [second.id, first.id])
        #expect(await controller.recentSearches() == ["invoice"])
    }

    @Test("A successful third use returns one non-sensitive snippet candidate")
    func recordPasteReturnsExactThresholdCandidate() async {
        let store = ReuseStoreSpy()
        let item = ClipItem(preview: "reusable", contentHash: "reusable", uses: 2)
        await store.seed([item])
        let controller = makeController(store: store)

        let candidate = await controller.recordPaste(of: item)
        let afterThreshold = await controller.recordPaste(of: item)

        #expect(candidate?.id == item.id)
        #expect(candidate?.uses == SnippetLimits.promotionSuggestionUseThreshold)
        #expect(afterThreshold == nil, "the exact-threshold suggestion must not repeat")
    }

    @Test("Sensitive clips never become snippet candidates")
    func sensitivePasteNeverSuggestsSnippet() async {
        let store = ReuseStoreSpy()
        let item = ClipItem(
            preview: "•••", contentHash: "sensitive", isSensitive: true, uses: 2)
        await store.seed([item])
        let controller = makeController(store: store)

        let candidate = await controller.recordPaste(of: item)

        #expect(candidate == nil)
    }

    @Test("Drag delivery records ranking and search without reordering the visible list")
    func recordDrag() async {
        let store = ReuseStoreSpy()
        let first = clip("first")
        let second = clip("second")
        await store.seed([first, second])
        let controller = makeController(store: store)
        await controller.refreshRecents()
        controller.activeSearchQuery = "reference"

        await controller.recordDragDelivery(
            of: second, now: Date(timeIntervalSince1970: 200))

        #expect(await store.eventLog() == ["use:second", "search:reference"])
        #expect(controller.recentItems.map(\.id) == [first.id, second.id])
        #expect(controller.activeSearchQuery.isEmpty)
    }

    @Test("Disabling search memory persists the choice, clears history, and blocks new queries")
    func disableSearchMemory() async {
        let store = ReuseStoreSpy()
        let recorder = ReuseRecorder()
        let item = clip("clip")
        await store.seed([item])
        let controller = makeController(store: store, recorder: recorder)
        controller.activeSearchQuery = "private query"

        controller.rememberSearches = false
        await waitUntil { await store.eventLog().contains("clear-searches") }
        await controller.recordDragDelivery(of: item)

        #expect(recorder.rememberValues == [false])
        #expect(await store.eventLog() == ["clear-searches", "use:clip"])
        #expect(await controller.recentSearches().isEmpty)
        #expect(controller.activeSearchQuery.isEmpty)
    }

    @Test("Paste-stack mutations preserve duplicate identity and FIFO consumption")
    func pasteStack() {
        let store = ReuseStoreSpy()
        let controller = makeController(store: store)
        let first = clip("first")
        let second = clip("second")

        controller.pushToStack(first)
        controller.pushToStack(first)
        controller.pushToStack(second)
        let duplicateIDs = controller.pasteStackEntries.prefix(2).map(\.id)
        #expect(Set(duplicateIDs).count == 2)

        controller.removeFromStack(entryID: duplicateIDs[0])
        #expect(controller.popNextFromStack()?.id == first.id)
        #expect(controller.popNextFromStack()?.id == second.id)
        #expect(controller.popNextFromStack() == nil)
        #expect(controller.pasteStackEntries.isEmpty)
    }

    @Test("Cyclic selection wraps and resets after eight seconds of silence")
    func cyclicSelection() async {
        let store = ReuseStoreSpy()
        let first = clip("first")
        let second = clip("second")
        await store.seed([first, second])
        let controller = makeController(store: store)
        await controller.refreshRecents()
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(controller.nextCyclicItem(now: start)?.id == first.id)
        #expect(controller.nextCyclicItem(now: start.addingTimeInterval(1))?.id == second.id)
        #expect(controller.nextCyclicItem(now: start.addingTimeInterval(2))?.id == first.id)
        #expect(controller.nextCyclicItem(now: start.addingTimeInterval(11))?.id == first.id)
    }

    @Test("Deletion hides immediately, stays filtered, then commits and reconciles")
    func deletionCommit() async {
        let store = ReuseStoreSpy()
        let item = clip("delete")
        await store.seed([item])
        let controller = makeController(store: store, deletionGrace: .zero)
        await controller.refreshRecents()

        controller.delete(item) { id in try? await store.delete(id: id) }
        #expect(controller.recentItems.isEmpty)
        #expect(controller.isDeletionPending(item.id))
        await controller.refreshRecents()
        #expect(controller.recentItems.isEmpty)

        await waitUntil { !controller.isDeletionPending(item.id) }

        #expect(await store.deletionCount() == 1)
        #expect(await store.storedIDs().isEmpty)
        #expect(controller.recentItems.isEmpty)
    }

    @Test("Undo cancels the destructive delete and restores the stored row")
    func undoDeletion() async {
        let store = ReuseStoreSpy()
        let item = clip("keep")
        await store.seed([item])
        let controller = makeController(store: store, deletionGrace: .seconds(60))
        await controller.refreshRecents()

        controller.delete(item) { id in try? await store.delete(id: id) }
        controller.undoDeletion(item.id)
        await waitUntil { controller.recentItems.contains { $0.id == item.id } }

        #expect(!controller.isDeletionPending(item.id))
        #expect(await store.deletionCount() == 0)
        #expect(controller.recentItems.map(\.id) == [item.id])
    }
}
