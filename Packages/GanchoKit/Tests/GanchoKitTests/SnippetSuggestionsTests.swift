import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Suggested snippets — who earns one, and what Never and Dismiss do")
struct SnippetSuggestionsTests {
    private let threshold = SnippetLimits.promotionSuggestionUseThreshold

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("suggest-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @discardableResult
    private func insert(
        _ store: GRDBClipboardStore, _ name: String, uses: Int, isSensitive: Bool = false,
        kind: ClipContentKind = .text, expiresAt: Date? = nil
    ) async throws -> ClipItem {
        let item = ClipItem(
            kind: kind, preview: name, contentHash: "hash-\(name)", isSensitive: isSensitive,
            expiresAt: expiresAt, uses: uses)
        try await store.insert(item, content: .text(name))
        return item
    }

    private func use(_ store: GRDBClipboardStore, _ item: ClipItem) async throws -> ClipItem? {
        try await store.recordUseAndSnippetSuggestion(id: item.id, requiredUses: threshold)
    }

    @Test("From the threshold up, most used first, with the total past the limit")
    func ordersAndCounts() async throws {
        let store = try makeStore()
        try await insert(store, "below", uses: threshold - 1)
        let least = try await insert(store, "least", uses: threshold)
        let most = try await insert(store, "most", uses: threshold + 4)
        let middle = try await insert(store, "middle", uses: threshold + 1)

        let top = try await store.snippetSuggestions(limit: 2)
        #expect(top.items.map(\.id) == [most.id, middle.id])
        #expect(top.total == 3)
        let all = try await store.snippetSuggestions(limit: 10)
        #expect(all.items.map(\.id) == [most.id, middle.id, least.id])
    }

    @Test("Snippets, secrets, masked kinds, archived and expired clips never appear")
    func excludesTheIneligible() async throws {
        let store = try makeStore()
        let uses = threshold + 2
        let snippet = try await insert(store, "snippet", uses: uses)
        try await store.promoteToSnippet(id: snippet.id)
        try await insert(store, "secret", uses: uses, isSensitive: true)
        for kind in ClipContentKind.allCases where kind.prefersMaskedPreview {
            try await insert(store, "masked-\(kind.rawValue)", uses: uses, kind: kind)
        }
        let archived = try await insert(store, "archived", uses: uses)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }
        try await insert(store, "expired", uses: uses, expiresAt: .now.addingTimeInterval(-60))
        let eligible = try await insert(store, "eligible", uses: uses)

        let suggestions = try await store.snippetSuggestions(limit: 50)
        #expect(suggestions.items.map(\.id) == [eligible.id])
        #expect(suggestions.total == 1)
    }

    @Test("Never removes it for good, from the group and the use-time nudge")
    func neverIsForGood() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold - 1)
        #expect(try await use(store, item)?.id == item.id)

        try await store.decideSnippetSuggestion(id: item.id, .never)
        #expect(try await store.snippetSuggestions().total == 0)
        for _ in 0..<(threshold * 2) {
            #expect(try await use(store, item) == nil)
        }
        #expect(try await store.snippetSuggestions().total == 0)
    }

    @Test("Dismiss hides it until the threshold's worth of new uses, then it returns")
    func dismissReturnsLater() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold + 1)
        try await store.decideSnippetSuggestion(id: item.id, .dismissed)
        #expect(try await store.snippetSuggestions().total == 0)

        for _ in 0..<(threshold - 1) {
            #expect(try await use(store, item) == nil)
            #expect(try await store.snippetSuggestions().total == 0)
        }
        #expect(try await use(store, item)?.id == item.id, "the nudge returns once")
        #expect(try await store.snippetSuggestions().items.map(\.id) == [item.id])
        #expect(try await use(store, item) == nil)
        #expect(try await store.snippetSuggestions().total == 1, "the group stays")
    }

    @Test("A later choice replaces the first, and counts from the later uses")
    func laterDecisionWins() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold)
        try await store.decideSnippetSuggestion(id: item.id, .dismissed)
        for _ in 0..<threshold { _ = try await use(store, item) }
        try await store.decideSnippetSuggestion(id: item.id, .dismissed)
        #expect(try await store.snippetSuggestions().total == 0, "counts from the second")

        try await store.decideSnippetSuggestion(id: item.id, .never)
        for _ in 0..<threshold { #expect(try await use(store, item) == nil) }
        #expect(try await store.snippetSuggestions().total == 0)
    }

    @Test("Never stays Never, even if a late Dismiss lands after it")
    func neverWinsOverALateDismiss() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold)
        try await store.decideSnippetSuggestion(id: item.id, .never)
        try await store.decideSnippetSuggestion(id: item.id, .dismissed)
        for _ in 0..<(threshold * 2) { #expect(try await use(store, item) == nil) }
        #expect(try await store.snippetSuggestions().total == 0)
    }

    @Test("The use-time nudge never offers a secret or a masked kind")
    func nudgeExcludesTheIneligible() async throws {
        let store = try makeStore()
        let secret = try await insert(store, "secret", uses: threshold - 1, isSensitive: true)
        #expect(try await use(store, secret) == nil)
        for kind in ClipContentKind.allCases where kind.prefersMaskedPreview {
            let masked = try await insert(
                store, "masked-\(kind.rawValue)", uses: threshold - 1, kind: kind)
            #expect(try await use(store, masked) == nil, "\(kind)")
        }
    }

    @Test("Deleting the clip deletes its decision; an unknown clip records nothing")
    func decisionsFollowTheClip() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold)
        try await store.decideSnippetSuggestion(id: item.id, .never)
        try await store.decideSnippetSuggestion(id: UUID(), .never)
        #expect(try await rowCount(store) == 1)

        try await store.delete(id: item.id)
        #expect(try await rowCount(store) == 0)
    }

    @Test("Decisions never touch the clip, so nothing is queued to sync")
    func decisionsStayLocal() async throws {
        let store = try makeStore()
        let item = try await insert(store, "clip", uses: threshold)
        let needsUpload: () async throws -> Bool = {
            try await store.writer.read { db in
                try Bool.fetchOne(
                    db, sql: "SELECT needsUpload FROM clip WHERE id = ?",
                    arguments: [item.id.uuidString]) ?? false
            }
        }
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE clip SET needsUpload = 0")
        }
        try await store.decideSnippetSuggestion(id: item.id, .never)
        #expect(try await needsUpload() == false)
    }

    @Test("A non-positive limit returns nothing")
    func limitHygiene() async throws {
        let store = try makeStore()
        try await insert(store, "clip", uses: threshold)
        #expect(try await store.snippetSuggestions(limit: 0) == .empty)
        #expect(try await store.snippetSuggestions(limit: -1) == .empty)
    }

    private func rowCount(_ store: GRDBClipboardStore) async throws -> Int {
        try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snippet_suggestion") ?? 0
        }
    }
}
