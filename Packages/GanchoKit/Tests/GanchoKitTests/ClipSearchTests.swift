import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("FTS5 search — modes, sanitization, filters")
struct ClipSearchTests {
    private struct SeedClip {
        let text: String
        let kind: ClipContentKind
        let app: String?
        let createdAt: Date
    }

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
        let clips: [SeedClip] = [
            SeedClip(
                text: "call the dentist about the appointment",
                kind: .text,
                app: "com.apple.Notes",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            SeedClip(
                text: "https://example.com/dental-plans",
                kind: .url,
                app: "com.apple.Safari",
                createdAt: Date(timeIntervalSince1970: 1_700_100_000)),
            SeedClip(
                text: "SELECT * FROM appointments WHERE day = 'tuesday'",
                kind: .code,
                app: "com.apple.dt.Xcode",
                createdAt: Date(timeIntervalSince1970: 1_700_200_000)),
            SeedClip(
                text: "the quarterly dental report is ready",
                kind: .text,
                app: "com.tinyspeck.slackmacgap",
                createdAt: Date(timeIntervalSince1970: 1_700_300_000))
        ]
        for clip in clips {
            try await store.insert(
                ClipItem(
                    createdAt: clip.createdAt, kind: clip.kind,
                    preview: String(clip.text.prefix(120)),
                    contentHash: ClipItem.hash(of: clip.text, kind: clip.kind),
                    sourceAppBundleID: clip.app),
                content: .text(clip.text))
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
            "^caret", "semi;colon", "emoji 🪝 search", "-", "\"\"\""
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

    @Test("Regex scan honors the row ceiling — best-effort over recent items")
    func regexScanCeiling() async throws {
        let store = try makeStore()
        let ceiling = GRDBClipboardStore.regexScanCeiling
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var entries: [(item: ClipItem, content: ClipContent?)] = []
        entries.reserveCapacity(ceiling + 2)
        // The oldest row is the ONLY "ancient-marker" match — and it sits
        // beyond the scan ceiling, so a regex pass must never reach it.
        entries.append(
            (
                item: ClipItem(
                    createdAt: base.addingTimeInterval(-1), preview: "ancient-marker",
                    contentHash: "h-ancient"),
                content: .text("ancient-marker")
            ))
        for index in 0..<ceiling {
            entries.append(
                (
                    item: ClipItem(
                        createdAt: base.addingTimeInterval(Double(index)),
                        preview: "filler \(index)", contentHash: "h-\(index)"),
                    content: .text("filler \(index)")
                ))
        }
        entries.append(
            (
                item: ClipItem(
                    createdAt: base.addingTimeInterval(Double(ceiling)),
                    preview: "newest-marker", contentHash: "h-newest"),
                content: .text("newest-marker")
            ))
        try await store.importBatch(entries)

        // The newest row is inside the scan window even though the table
        // exceeds the ceiling.
        let newest = try await store.search(
            ClipSearchQuery(text: "newest-marker", mode: .regex))
        #expect(newest.count == 1)

        // A pattern matching only the row PAST the ceiling comes back empty:
        // the scan stopped instead of walking the whole table.
        let ancient = try await store.search(
            ClipSearchQuery(text: "ancient-marker", mode: .regex))
        #expect(ancient.isEmpty, "rows beyond the scan ceiling are not examined")
    }

    @Test("Regex matches oversized contentText on a bounded prefix only")
    func regexOversizedHaystack() async throws {
        let store = try makeStore()
        let padding = String(
            repeating: "x", count: GRDBClipboardStore.regexHaystackLimit + 50_000)
        try await store.insert(
            ClipItem(preview: "huge clip", contentHash: "h-huge"),
            content: .text("prefix-marker " + padding + " tail-marker"))

        let inPrefix = try await store.search(
            ClipSearchQuery(text: "prefix-marker", mode: .regex))
        #expect(inPrefix.count == 1, "matches inside the bounded prefix still hit")

        let inTail = try await store.search(
            ClipSearchQuery(text: "tail-marker", mode: .regex))
        #expect(inTail.isEmpty, "content beyond the haystack cap is not scanned")
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
