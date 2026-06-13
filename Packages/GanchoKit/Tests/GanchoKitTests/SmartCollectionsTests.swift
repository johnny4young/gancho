import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Smart collections + replay suggestions")
struct SmartCollectionsTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("smart-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Rules filter by kind, app, text, and pinned — live, not materialized")
    func ruleEvaluation() async throws {
        let store = try makeStore()
        try await store.insert(
            ClipItem(
                kind: .url, preview: "https://api.example.com/docs", contentHash: "h1",
                sourceAppBundleID: "com.apple.Safari"),
            content: .text("https://api.example.com/docs"))
        try await store.insert(
            ClipItem(
                kind: .text, preview: "meeting notes", contentHash: "h2",
                sourceAppBundleID: "com.apple.Notes", isPinned: true),
            content: .text("meeting notes about the api"))

        let urlsFromSafari = SmartCollectionRule(
            name: "Safari links", kinds: [.url], sourceAppBundleID: "com.apple.Safari")
        #expect(try await store.items(matching: urlsFromSafari).count == 1)

        let apiText = SmartCollectionRule(name: "API stuff", textContains: "api")
        #expect(try await store.items(matching: apiText).count == 2)

        let pinnedOnly = SmartCollectionRule(name: "Pinned", pinnedOnly: true)
        #expect(try await store.items(matching: pinnedOnly).map(\.preview) == ["meeting notes"])
    }

    @Test("Rules persist through defaults")
    func rulePersistence() throws {
        let suite = "smart-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = [SmartCollectionRule(name: "Links", kinds: [.url])]
        SmartCollectionRule.saveAll(rules, to: defaults)
        #expect(SmartCollectionRule.loadAll(from: defaults) == rules)
    }

    @Test("Replay suggestions surface re-used, non-snippet, non-sensitive clips")
    func replaySuggestions() async throws {
        let store = try makeStore()
        let created = Date(timeIntervalSince1970: 1_750_000_000)
        // Re-used two days after creation → replay signal.
        let replayed = ClipItem(
            createdAt: created, lastUsedAt: created.addingTimeInterval(2 * 86_400),
            preview: "standup template", contentHash: "hr")
        // Fresh, never reused.
        let fresh = ClipItem(createdAt: created, preview: "one-off", contentHash: "hf")
        try await store.importBatch([(replayed, .text("standup")), (fresh, .text("x"))])

        let suggestions = try await SnippetSuggestor(store: store).suggestions()
        #expect(suggestions.map(\.preview) == ["standup template"])
    }
}
