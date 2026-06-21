import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Snippet library — the two-world bridge")
struct SnippetLibraryTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("snip-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Promote keeps the clip alive through retention AND tier archiving")
    func promoteSurvivesEverything() async throws {
        let store = try makeStore()
        let old = ClipItem(
            createdAt: now.addingTimeInterval(-400 * 86_400), preview: "keeper",
            contentHash: "hk")
        try await store.insert(old, content: .text("keeper"))
        try await store.promoteToSnippet(id: old.id, title: "My snippet")

        try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .day), now: now)
        try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        let snippets = try await store.snippets()
        #expect(snippets.map(\.title) == ["My snippet"])
        #expect(try await store.count() == 1, "snippet stays visible")
    }

    @Test("save creates a code snippet with language, searchable, in the Library")
    func saveSnippetLandsInLibrary() async throws {
        let store = try makeStore()
        let saved = try await store.saveSnippet(
            title: "Greeting", text: "func hello() { print(\"hi\") }", language: "swift")

        let snippet = try await store.snippets().first { $0.id == saved.id }
        #expect(snippet != nil)
        #expect(snippet?.kind == .code)
        #expect(snippet?.tags == ["lang:swift"])
        #expect(try await store.snippetCount() == 1)

        // Content is FTS-indexed → the snippet is searchable by its body.
        let hits = try await store.search(ClipSearchQuery(text: "hello", mode: .fuzzy), limit: 10)
        #expect(hits.contains { $0.id == saved.id })
    }

    @Test("save without a language records no language tag")
    func saveSnippetNoLanguage() async throws {
        let store = try makeStore()
        let saved = try await store.saveSnippet(title: "Plain", text: "just text", language: nil)
        let snippet = try await store.snippets().first { $0.id == saved.id }
        #expect(snippet?.tags.isEmpty == true)
    }

    @Test("Demote returns the clip to retention's reach")
    func demoteReturnsToHistory() async throws {
        let store = try makeStore()
        let item = ClipItem(
            createdAt: now.addingTimeInterval(-400 * 86_400), preview: "temp", contentHash: "ht")
        try await store.insert(item, content: .text("temp"))
        try await store.promoteToSnippet(id: item.id)
        try await store.demoteFromSnippet(id: item.id)

        try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .day), now: now)
        #expect(try await store.count() == 0)
    }

    @Test("Snippet editing updates title, content, preview — and search follows")
    func editing() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "draft", contentHash: "hd")
        try await store.insert(item, content: .text("draft"))
        try await store.promoteToSnippet(id: item.id)

        try await store.updateSnippet(
            id: item.id, title: "Standup template", text: "Yesterday / Today / Blockers")

        let snippet = try #require(try await store.snippets().first)
        #expect(snippet.title == "Standup template")
        #expect(snippet.preview == "Yesterday / Today / Blockers")
        #expect(try await store.search(ClipSearchQuery(text: "Blockers")).count == 1)
    }

    @Test("Keyword: set, match case-insensitively, and count uses")
    func keywordAndUses() async throws {
        let store = try makeStore()
        let snippet = try await store.saveSnippet(title: "Signature", text: "Best,\n{name}")
        try await store.setKeyword(id: snippet.id, keyword: "  firma  ")  // trimmed

        let matched = try await store.snippet(matchingKeyword: "FIRMA")  // case-insensitive
        #expect(matched?.id == snippet.id)
        #expect(matched?.keyword == "firma")
        #expect(try await store.snippet(matchingKeyword: "nope") == nil)

        try await store.incrementUses(id: snippet.id)
        try await store.incrementUses(id: snippet.id)
        #expect(try await store.snippets().first(where: { $0.id == snippet.id })?.uses == 2)
    }

    @Test("Free ceiling: 20 snippets, Pro unlimited")
    func freeCeiling() {
        #expect(SnippetLimits.canPromote(currentSnippetCount: 19, isPro: false))
        #expect(!SnippetLimits.canPromote(currentSnippetCount: 20, isPro: false))
        #expect(SnippetLimits.canPromote(currentSnippetCount: 500, isPro: true))
    }
}
