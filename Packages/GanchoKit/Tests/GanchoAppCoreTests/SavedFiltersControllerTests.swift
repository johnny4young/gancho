import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor DelayedSavedFilterStore: SavedFilterStoring {
    private var rules: [SmartCollectionRule]
    private var pending: CheckedContinuation<[SmartCollectionRule], any Error>?
    private var delayedSnapshot: [SmartCollectionRule] = []
    private var shouldDelay = true

    init(rule: SmartCollectionRule) { rules = [rule] }
    func savedFilters() async throws -> [SmartCollectionRule] {
        guard shouldDelay else { return rules }
        shouldDelay = false
        delayedSnapshot = rules
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitUntilReading() async { while pending == nil { await Task.yield() } }
    func release(failing: Bool) {
        if failing {
            pending?.resume(throwing: SavedFilterError.invalidLegacyData)
        } else {
            pending?.resume(returning: delayedSnapshot)
        }
        pending = nil
    }
    func saveFilter(_ rule: SmartCollectionRule) async throws { rules = [rule] }
    func deleteFilter(id: UUID) async throws { rules.removeAll { $0.id == id } }
    func importLegacyFilters(_ rules: [SmartCollectionRule]) async throws { self.rules = rules }
}

@Suite("Saved filter refresh ownership") @MainActor
struct SavedFiltersControllerTests {
    @Test("An old reload cannot undo a deletion or publish a stale error", arguments: [true, false])
    func staleReload(failing: Bool) async {
        let rule = SmartCollectionRule(name: "Synthetic filter")
        let store = DelayedSavedFilterStore(rule: rule)
        let model = SavedFiltersController(store: store)
        let oldLoad = Task { await model.load() }
        await store.waitUntilReading()
        await model.delete(rule.id)
        #expect(model.rules.isEmpty)
        #expect(!model.failed)
        await store.release(failing: failing)
        await oldLoad.value
        #expect(model.rules.isEmpty)
        #expect(!model.failed)
    }

    @Test("Canceling a load never publishes its delayed snapshot")
    func canceledReload() async {
        let store = DelayedSavedFilterStore(rule: SmartCollectionRule(name: "Synthetic filter"))
        let model = SavedFiltersController(store: store)
        let task = Task { await model.load() }
        await store.waitUntilReading()
        task.cancel()
        await store.release(failing: false)
        await task.value
        #expect(model.rules.isEmpty)
        #expect(!model.failed)
    }
}
