import Foundation
import GanchoKit
import Observation

/// The saved-filter definitions the Library shows, read from the encrypted
/// store. `failed` means the definitions themselves could not be read;
/// `legacyImportFailed` means the one-time preferences import could not
/// decode its source — that source stays in place for recovery, and the
/// definitions already in the store still load, so a valid filter is never
/// hidden by unrelated legacy bytes.
@MainActor @Observable public final class SavedFiltersController {
    public private(set) var rules: [SmartCollectionRule] = []
    public private(set) var failed = false
    public private(set) var legacyImportFailed = false
    private let store: (any SavedFilterStoring)?
    @ObservationIgnored private var loadID = UUID()

    public init(store: (any SavedFilterStoring)?) { self.store = store }

    /// Reads the definitions; with `defaults`, first retries the legacy
    /// import. Every caller that presents the Library may call this again —
    /// a transient read failure is recovered by the next load, not a relaunch.
    public func load(migrating defaults: UserDefaults? = nil) async {
        let request = UUID()
        loadID = request
        guard let store else {
            failed = true
            return
        }
        if let defaults {
            var importFailed = false
            do { try await SavedFilterMigration.migrate(from: defaults, to: store) } catch {
                importFailed = true
            }
            guard request == loadID, !Task.isCancelled else { return }
            legacyImportFailed = importFailed
        }
        do {
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
