import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Search history — recall, cap, privacy clear")
struct SearchHistoryTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("search-history-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Repeating a search bumps it instead of duplicating")
    func upsertBumps() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.recordSearch("python", now: base)
        try await store.recordSearch("deploy", now: base.addingTimeInterval(10))
        try await store.recordSearch("python", now: base.addingTimeInterval(20))

        // python was re-used most recently → it leads, and there are only 2 rows.
        #expect(try await store.recentSearches() == ["python", "deploy"])
    }

    @Test("Empty and whitespace-only queries are never remembered")
    func emptyIgnored() async throws {
        let store = try makeStore()
        try await store.recordSearch("   ")
        try await store.recordSearch("")
        #expect(try await store.recentSearches().isEmpty)
        // Leading/trailing whitespace is trimmed before storing.
        try await store.recordSearch("  python  ")
        #expect(try await store.recentSearches() == ["python"])
    }

    @Test("The history trims to the cap, dropping the oldest by recency")
    func capTrims() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<(GRDBClipboardStore.searchHistoryCap + 10) {
            try await store.recordSearch(
                "query-\(index)", now: base.addingTimeInterval(Double(index)))
        }
        let all = try await store.recentSearches(limit: 1_000)
        #expect(all.count == GRDBClipboardStore.searchHistoryCap)
        #expect(all.first == "query-59", "newest survives")
        #expect(!all.contains("query-0"), "the oldest rows fall off")
    }

    @Test("clearSearchHistory forgets everything at once")
    func clearAll() async throws {
        let store = try makeStore()
        try await store.recordSearch("secret project name")
        try await store.recordSearch("deploy")
        try await store.clearSearchHistory()
        #expect(try await store.recentSearches().isEmpty)
    }

    @Test("recentSearches respects its limit, newest first")
    func recallOrder() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for (offset, query) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            try await store.recordSearch(query, now: base.addingTimeInterval(Double(offset)))
        }
        #expect(try await store.recentSearches(limit: 3) == ["f", "e", "d"])
    }
}
