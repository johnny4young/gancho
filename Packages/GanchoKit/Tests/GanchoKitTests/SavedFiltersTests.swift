import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Saved filters — local definitions and predicate parity")
struct SavedFiltersTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "filter-test-\(UUID())")))
        try GanchoDatabaseMigrator.make().migrate(store.writer)
        return store
    }

    @Test(
        "Pinned rows outside a general result limit remain discoverable",
        arguments: ClipSearchQuery.Mode.allCases)
    func pinnedBeforeLimit(_ mode: ClipSearchQuery.Mode) async throws {
        let store = try makeStore()
        for index in 0..<140 {
            let item = ClipItem(
                preview: "needle", contentHash: "filter-\(index)", isPinned: index == 139)
            _ = try await store.insert(item, content: .text("needle"))
        }
        let rule = SmartCollectionRule(
            name: "Pinned needle", textContains: "needle", pinnedOnly: true, searchMode: mode)
        let hits = try await store.items(matching: rule, limit: 1)
        #expect(hits.count == 1)
        #expect(hits.first?.isPinned == true)
        #expect(
            try await store.items(
                matching: SmartCollectionRule(name: "Pins", pinnedOnly: true), limit: 1
            ).first?.isPinned == true)
    }

    @Test("Board membership alone never satisfies pinned-only")
    func boardIsNotPinned() async throws {
        let store = try makeStore()
        let item = ClipItem(contentHash: "board-only")
        _ = try await store.insert(item, content: .text("needle"))
        let board = try await store.createPinboard(name: "Synthetic board", sfSymbol: "folder")
        try await store.assign(clipID: item.id, toBoard: board.id)
        let rule = SmartCollectionRule(
            name: "Pins in board", textContains: "needle", pinnedOnly: true, boardID: board.id)
        #expect(try await store.items(matching: rule, limit: 10).isEmpty)
    }

    @Test("Saving, updating and deleting definitions never materializes or deletes clips")
    func roundTrip() async throws {
        let store = try makeStore()
        _ = try await store.insert(
            ClipItem(contentHash: "unicode"), content: .text("Hola canción 世界"))
        var rule = SmartCollectionRule(
            name: "Quotes \" and 世界", textContains: "canción", searchMode: .exact)
        let before = try await store.items(matching: rule, limit: 10)
        try await store.saveFilter(rule)
        #expect(try await store.savedFilters() == [rule])
        let stored = try #require(try await store.savedFilters().first)
        #expect(try await store.items(matching: stored, limit: 10) == before)
        rule.name = "Renamed"
        try await store.saveFilter(rule)
        #expect(try await store.savedFilters() == [rule])
        try await store.deleteFilter(id: rule.id)
        #expect(try await store.savedFilters().isEmpty)
        #expect(try await store.count() == 1)
    }

    @Test("Missing boards and invalid regex never broaden saved scope")
    func invalidScope() async throws {
        let store = try makeStore()
        #expect(
            try await store.items(
                matching: SmartCollectionRule(name: "No types", kinds: []), limit: 10
            ).isEmpty)
        let missing = SmartCollectionRule(name: "Missing", boardID: UUID())
        await #expect(throws: SavedFilterError.missingBoard) {
            try await store.items(matching: missing, limit: 10)
        }
        let invalid = SmartCollectionRule(name: "Invalid", textContains: "[", searchMode: .regex)
        await #expect(throws: ClipSearchError.invalidRegularExpression) {
            try await store.items(matching: invalid, limit: 10)
        }
    }

    @Test("Legacy migration is retry-safe and retains invalid source data") @MainActor
    func migration() async throws {
        let store = try makeStore()
        let suite = "com.gancho.filter-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rule = SmartCollectionRule(name: "Legacy")
        SmartCollectionRule.saveAll([rule], to: defaults)
        try await SavedFilterMigration.migrate(from: defaults, to: store)
        #expect(defaults.data(forKey: "smart-collections") == nil)
        var edited = rule
        edited.name = "Edited after migration"
        try await store.saveFilter(edited)
        SmartCollectionRule.saveAll([rule], to: defaults)
        try await SavedFilterMigration.migrate(from: defaults, to: store)
        #expect(try await store.savedFilters() == [edited])
        defaults.set(Data([1, 2]), forKey: "smart-collections")
        await #expect(throws: SavedFilterError.invalidLegacyData) {
            try await SavedFilterMigration.migrate(from: defaults, to: store)
        }
        #expect(defaults.data(forKey: "smart-collections") == Data([1, 2]))
    }

    @Test("Legacy JSON without mode or board still decodes")
    func oldDefinition() throws {
        let json = """
            {"id":"11111111-1111-4111-8111-111111111111","name":"Old","pinnedOnly":true}
            """
        let rule = try JSONDecoder().decode(SmartCollectionRule.self, from: Data(json.utf8))
        #expect(rule.query.mode == .fuzzy)
        #expect(rule.query.pinnedOnly)
        #expect(rule.boardID == nil)
    }
}

@Suite("Saved-filter durable definitions")
struct SavedFilterPersistenceTests {
    @Test("Definitions survive reopening the same encrypted-capable store")
    func restart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "saved-filter-reopen-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let passphrase = UUID().uuidString
        let rule = SmartCollectionRule(
            name: "Synthetic persisted filter", textContains: "café", pinnedOnly: true)
        let first = try GRDBClipboardStore(directory: directory, passphrase: passphrase)
        try await first.saveFilter(rule)
        let reopened = try GRDBClipboardStore(directory: directory, passphrase: passphrase)
        #expect(try await reopened.savedFilters() == [rule])
    }
}
