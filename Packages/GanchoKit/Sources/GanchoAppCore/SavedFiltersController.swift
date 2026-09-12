import Foundation
import GanchoKit
import Observation

@MainActor @Observable public final class SavedFiltersController {
    public private(set) var rules: [SmartCollectionRule] = []
    public private(set) var failed = false
    private let store: (any SavedFilterStoring)?
    @ObservationIgnored private var loadID = UUID()

    public init(store: (any SavedFilterStoring)?) { self.store = store }

    public func load(migrating defaults: UserDefaults? = nil) async {
        let request = UUID()
        loadID = request
        guard let store else {
            failed = true
            return
        }
        do {
            if let defaults { try await SavedFilterMigration.migrate(from: defaults, to: store) }
            let loaded = try await store.savedFilters()
            guard request == loadID, !Task.isCancelled else { return }
            rules = loaded
            failed = false
        } catch {
            guard request == loadID, !Task.isCancelled else { return }
            failed = true
        }
    }

    public func save(_ rule: SmartCollectionRule) async -> Bool {
        guard let store else { return false }
        do {
            try await store.saveFilter(rule)
            await load()
            return !failed
        } catch {
            failed = true
            return false
        }
    }

    public func delete(_ id: UUID) async {
        guard let store else { return }
        do {
            try await store.deleteFilter(id: id)
            await load()
        } catch { failed = true }
    }
}
