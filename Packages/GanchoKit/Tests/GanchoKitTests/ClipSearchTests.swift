import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("FTS5 search — modes, sanitization, filters")
struct ClipSearchTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("fts-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private func seed(_ store: GRDBClipboardStore) async throws {
        let clips: [(String, ClipContentKind, String?, Date)] = [
            (
                "call the dentist about the appointment", .text, "com.apple.Notes",
                Date(timeIntervalSince1970: 1_700_000_000)
            ),
            (
                "https://example.com/dental-plans", .url, "com.apple.Safari",
                Date(timeIntervalSince1970: 1_700_100_000)
            ),
            (
                "SELECT * FROM appointments WHERE day = 'tuesday'", .code, "com.apple.dt.Xcode",
                Date(timeIntervalSince1970: 1_700_200_000)
            ),
            (
                "the quarterly dental report is ready", .text, "com.tinyspeck.slackmacgap",
                Date(timeIntervalSince1970: 1_700_300_000)
            ),
        ]
        for (text, kind, app, date) in clips {
            try await store.insert(
                ClipItem(
                    createdAt: date, kind: kind, preview: String(text.prefix(120)),
                    contentHash: ClipItem.hash(of: text, kind: kind),
                    sourceAppBundleID: app),
                content: .text(text))
        }
    }

    @Test("Fuzzy prefix-matches from the first keystroke")
    func fuzzyPrefix() async throws {
        let store = try makeStore()
        try await seed(store)

        let hits = try await store.search(ClipSearchQuery(text: "dent"))
        #expect(hits.count == 3, "dentist, dental-plans, dental all prefix-match")

        let single = try await store.search(ClipSearchQuery(text: "quarterly dent"))
        #expect(single.count == 1)
        #expect(single.first?.preview.contains("quarterly") == true)
    }

    @Test("Exact mode matches the phrase in order")
    func exactPhrase() async throws {
        let store = try makeStore()
        try await seed(store)

        let hits = try await store.search(
            ClipSearchQuery(text: "call the dentist", mode: .exact))
        #expect(hits.count == 1)

        let reversed = try await store.search(
            ClipSearchQuery(text: "dentist the call", mode: .exact))
        #expect(reversed.isEmpty)
    }

    @Test(
        "Hostile input never breaks the query",
        arguments: [
            "\"unclosed quote", "AND OR NOT", "wild*card", "(paren", "col:filter",
            "^caret", "semi;colon", "emoji 🪝 search", "-", "\"\"\"",
        ])
    func sanitization(hostile: String) async throws {
        let store = try makeStore()
        try await seed(store)
        // Must not throw, whatever comes back.
        _ = try await store.search(ClipSearchQuery(text: hostile))
        _ = try await store.search(ClipSearchQuery(text: hostile, mode: .exact))
    }

    @Test("Sanitized operators are matched literally, not interpreted")
    func operatorsAreLiteral() async throws {
        let store = try makeStore()
        try await store.insert(
            ClipItem(
                preview: "x AND y", contentHash: ClipItem.hash(of: "x AND y", kind: .text)),
            content: .text("x AND y"))
        try await store.insert(
            ClipItem(preview: "plain x", contentHash: ClipItem.hash(of: "plain x", kind: .text)),
            content: .text("plain x"))

        // If AND were interpreted as an operator this would match both rows.
        let hits = try await store.search(ClipSearchQuery(text: "x AND y", mode: .exact))
        #expect(hits.count == 1)
        #expect(hits.first?.preview == "x AND y")
    }

    @Test("Regex mode scans content; invalid patterns throw a typed error")
    func regexMode() async throws {
        let store = try makeStore()
        try await seed(store)

        let hits = try await store.search(
            ClipSearchQuery(text: #"SELECT \* FROM \w+"#, mode: .regex))
        #expect(hits.count == 1)
        #expect(hits.first?.kind == .code)

        await #expect(throws: ClipSearchError.invalidRegularExpression) {
            _ = try await store.search(ClipSearchQuery(text: "([unclosed", mode: .regex))
        }
    }

    @Test("Filters narrow by kind, source app, and date")
    func filters() async throws {
        let store = try makeStore()
        try await seed(store)

        let urlOnly = try await store.search(
            ClipSearchQuery(text: "dent", kinds: [.url]))
        #expect(urlOnly.map(\.kind) == [.url])

        let slackOnly = try await store.search(
            ClipSearchQuery(text: "dent", sourceAppBundleID: "com.tinyspeck.slackmacgap"))
        #expect(slackOnly.count == 1)

        let early = Date(timeIntervalSince1970: 1_699_999_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_150_000)
        let dated = try await store.search(
            ClipSearchQuery(text: "dent", dateRange: early...cutoff))
        #expect(dated.count == 2, "only the two clips created before the cutoff")
    }

    @Test("Search index follows updates and deletes")
    func indexFollowsWrites() async throws {
        let store = try makeStore()
        let item = ClipItem(
            preview: "ephemeral", contentHash: ClipItem.hash(of: "ephemeral", kind: .text))
        try await store.insert(item, content: .text("ephemeral"))

        #expect(try await store.search(ClipSearchQuery(text: "ephemeral")).count == 1)
        try await store.delete(id: item.id)
        #expect(try await store.search(ClipSearchQuery(text: "ephemeral")).isEmpty)
    }
}
