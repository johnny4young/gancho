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

    @Test("A read that fails once is recovered by the next load, not a relaunch")
    func retryAfterFailedRead() async {
        let store = FlakySavedFilterStore(rules: [SmartCollectionRule(name: "Synthetic filter")])
        await store.failNextRead()
        let model = SavedFiltersController(store: store)
        await model.load()
        #expect(model.failed)
        #expect(model.rules.isEmpty)
        await model.load()
        #expect(!model.failed)
        #expect(model.rules.map(\.name) == ["Synthetic filter"])
    }

    @Test("Invalid legacy bytes stay in place and the stored definitions still load")
    func legacyImportFailureDoesNotHideStoredRules() async {
        let defaults = UserDefaults(suiteName: "saved-filters-tests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "") }
        let legacy = Data("not json".utf8)
        defaults.set(legacy, forKey: "smart-collections")
        let store = FlakySavedFilterStore(rules: [SmartCollectionRule(name: "Kept")])
        let model = SavedFiltersController(store: store)
        await model.load(migrating: defaults)
        #expect(model.legacyImportFailed)
        #expect(!model.failed)
        #expect(model.rules.map(\.name) == ["Kept"])
        #expect(defaults.data(forKey: "smart-collections") == legacy, "source kept for recovery")
        // A later reload without the migration keeps the warning; one with a
        // now-valid source clears it.
        await model.load()
        #expect(model.legacyImportFailed)
        defaults.removeObject(forKey: "smart-collections")
        await model.load(migrating: defaults)
        #expect(!model.legacyImportFailed)
        #expect(model.rules.map(\.name) == ["Kept"])
    }
}

private actor FlakySavedFilterStore: SavedFilterStoring {
    private var rules: [SmartCollectionRule]
    private var readsToFail = 0

    init(rules: [SmartCollectionRule]) { self.rules = rules }
    func failNextRead() { readsToFail += 1 }
    func savedFilters() async throws -> [SmartCollectionRule] {
        if readsToFail > 0 {
            readsToFail -= 1
            throw SavedFilterError.invalidLegacyData
        }
        return rules
    }
    func saveFilter(_ rule: SmartCollectionRule) async throws { rules.append(rule) }
    func deleteFilter(id: UUID) async throws { rules.removeAll { $0.id == id } }
    func importLegacyFilters(_ imported: [SmartCollectionRule]) async throws { rules += imported }
}
