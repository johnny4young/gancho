import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Snippet placeholders — the grammar, the fill, and what stays as it was")
struct SnippetPlaceholderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func placeholders(_ template: String) -> [SnippetTemplate.Placeholder] {
        SnippetTemplate.tokens(in: template).map(\.placeholder)
    }

    private func dateText(dayOffset: Int) -> String {
        SnippetTemplate.defaultDate(dayOffset: dayOffset, now: now, calendar: calendar)
            .formatted(date: .abbreviated, time: .omitted)
    }

    private func render(_ template: String, clipboard: [Int: String] = [:]) -> String {
        SnippetTemplate.render(template, clipboard: clipboard, now: now, calendar: calendar).text
    }

    @Test(
        "Each self-filling placeholder parses",
        arguments: [
            ("{clipboard}", SnippetTemplate.Placeholder.clipboard(offset: 0)),
            ("{clipboard offset=1}", .clipboard(offset: 1)),
            ("{clipboard offset=12}", .clipboard(offset: 12)),
            ("{date}", .date(dayOffset: 0)),
            ("{date +2d}", .date(dayOffset: 2)),
            ("{date -7d}", .date(dayOffset: -7)),
            ("{cursor}", .cursor),
            ("{ date }", .date(dayOffset: 0))
        ])
    func parses(_ template: String, _ expected: SnippetTemplate.Placeholder) {
        #expect(placeholders(template) == [expected])
    }

    @Test(
        "Near misses stay literal",
        arguments: [
            "{clipboard offset=x}", "{clipboard offset=-1}", "{clipboard offset=1234}",
            "{date +2x}", "{date +d}", "{date *2d}", "{cursor | trim}", "{name | shout}", "{}",
            "{not-a-field}"
        ])
    func stayLiteral(_ template: String) {
        #expect(placeholders(template).isEmpty)
        #expect(render(template) == template)
    }

    @Test("Old fields keep working, reserved names with a default among them")
    func oldFieldsUnchanged() {
        #expect(
            placeholders("{name}{full name}{name:World}{date:today}{cursor:x}{clipboard foo}") == [
                .field(name: "name", defaultValue: nil),
                .field(name: "full name", defaultValue: nil),
                .field(name: "name", defaultValue: "World"),
                .field(name: "date", defaultValue: "today"),
                .field(name: "cursor", defaultValue: "x"),
                .field(name: "clipboard foo", defaultValue: nil)
            ])
        #expect(placeholders("{Date}") == [.field(name: "Date", defaultValue: nil)])
        #expect(
            placeholders("{name: spaced }") == [.field(name: "name", defaultValue: " spaced ")])
        #expect(placeholders("{name:a|b}") == [.field(name: "name", defaultValue: "a|b")])
        #expect(placeholders("{ }") == [.field(name: "", defaultValue: nil)])
        #expect(render("a{ }b") == "ab", "a blank field never leaves braces")
    }

    @Test("Reserved names aren't fields; the sheet is needed only to type or pick")
    func fieldsAndFilling() {
        let template = "{name} {clipboard} {date} {cursor} {date +2d} {date}"
        #expect(SnippetTemplate.fields(in: template).map(\.name) == ["name"])
        #expect(SnippetTemplate.dateOffsets(in: template) == [0, 2])
        #expect(SnippetTemplate.clipboardOffsets(in: "{clipboard offset=1}{clipboard}") == [1, 0])
        #expect(SnippetTemplate.needsFilling(template))
        #expect(SnippetTemplate.needsFilling("{date}"))
        #expect(SnippetTemplate.needsFilling("{a}"))
        #expect(!SnippetTemplate.needsFilling("{clipboard} {cursor}"))
        #expect(SnippetTemplate.isTemplate("{cursor}"))
        #expect(!SnippetTemplate.isTemplate("plain { text! }"))
    }

    @Test("Modifiers run in order, on any placeholder but the cursor")
    func modifiers() {
        #expect(render("{clipboard | trim}", clipboard: [0: "  hi \n"]) == "hi")
        #expect(render("{clipboard | uppercase}", clipboard: [0: "hi"]) == "HI")
        #expect(render("[{clipboard | trim | uppercase}]", clipboard: [0: " hi "]) == "[HI]")
        #expect(render("{clipboard|trim}", clipboard: [0: " hi "]) == "hi")
        #expect(render("{name:ana | uppercase}") == "ANA")
        #expect(
            SnippetTemplate.render("{name | uppercase}", values: ["name": "ana"]).text == "ANA")
        #expect(render("{date | uppercase}") == dateText(dayOffset: 0).uppercased())
    }

    @Test("Clipboard offsets fill separately; a missing one is empty, never braces")
    func clipboardValues() {
        let template = "{clipboard}/{clipboard offset=1}/{clipboard offset=2}"
        #expect(render(template, clipboard: [0: "now", 1: "before"]) == "now/before/")
    }

    @Test("Dates default to today plus the offset; a picked date wins")
    func dates() {
        #expect(render("{date}") == dateText(dayOffset: 0))
        #expect(render("{date +2d}") == dateText(dayOffset: 2))
        #expect(render("{date -1d}") == dateText(dayOffset: -1))
        let picked = now.addingTimeInterval(30 * 86_400)
        let rendered = SnippetTemplate.render(
            "{date +2d} {date}", dates: [2: picked], now: now, calendar: calendar)
        #expect(
            rendered.text
                == "\(picked.formatted(date: .abbreviated, time: .omitted)) \(dateText(dayOffset: 0))"
        )
        #expect(SnippetTemplate.dateLabel(dayOffset: 0) == "{date}")
        #expect(SnippetTemplate.dateLabel(dayOffset: 2) == "{date +2d}")
        #expect(SnippetTemplate.dateLabel(dayOffset: -3) == "{date -3d}")
    }

    @Test("The first cursor sets the caret; every cursor leaves the text")
    func cursor() {
        let rendered = SnippetTemplate.render("Hi {cursor}there{cursor}!")
        #expect(rendered.text == "Hi there!")
        #expect(rendered.charactersAfterCursor == 6)
        #expect(SnippetTemplate.render("no caret").charactersAfterCursor == nil)
        #expect(SnippetTemplate.render("end{cursor}").charactersAfterCursor == 0)
        #expect(
            SnippetTemplate.render("{cursor}👩‍💻é\nx").charactersAfterCursor == 4,
            "characters, as the left arrow moves")
        let filled = SnippetTemplate.render("{cursor}{clipboard}", clipboard: [0: "abc"])
        #expect(filled.charactersAfterCursor == 3, "counts what was filled in")
    }

    @Test("A preview keeps the clipboard and the cursor as written, and reads nothing")
    func previewDefers() {
        let rendered = SnippetTemplate.render(
            "{name} {clipboard | trim} {cursor}", values: ["name": "Ana"],
            clipboard: [0: "should not appear"], keepingDeferred: true)
        #expect(rendered.text == "Ana {clipboard | trim} {cursor}")
        #expect(rendered.charactersAfterCursor == nil)
    }

    @Test("A modifier goes before the brace of the placeholder at the caret")
    func modifierPoint() {
        let text = "ab {date} cd {cursor} {x}"
        let point = { SnippetTemplate.modifierInsertionPoint(in: text, caret: $0) }
        #expect(point(2) == nil, "outside")
        #expect(point(3) == nil, "before the brace")
        #expect(point(4) == 8, "inside")
        #expect(point(9) == 8, "right after")
        #expect(point(10) == nil)
        #expect(point(15) == nil, "the cursor takes none")
        #expect(point(25) == 24)
    }

    // MARK: - History

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("placeholders-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @discardableResult
    private func insert(
        _ store: GRDBClipboardStore, _ text: String, minutesAgo: Double,
        kind: ClipContentKind = .text, isSensitive: Bool = false, isPinned: Bool = false,
        expiresAt: Date? = nil
    ) async throws -> ClipItem {
        let item = ClipItem(
            createdAt: Date.now.addingTimeInterval(-minutesAgo * 60), kind: kind, preview: text,
            contentHash: "hash-\(text)", isPinned: isPinned, isSensitive: isSensitive,
            expiresAt: expiresAt)
        try await store.insert(item, content: .text(text))
        return item
    }

    @Test("History offsets count back by recency, pins at their own time, past snippets")
    func historyOrder() async throws {
        let store = try makeStore()
        try await insert(store, "newest", minutesAgo: 1)
        try await insert(store, "pinned old", minutesAgo: 5, isPinned: true)
        let snippet = try await insert(store, "a snippet", minutesAgo: 2)
        try await store.promoteToSnippet(id: snippet.id)
        try await insert(store, "middle", minutesAgo: 3)

        #expect(try await store.historyTextForSnippet(offset: 0) == "newest")
        #expect(try await store.historyTextForSnippet(offset: 1) == "middle")
        #expect(try await store.historyTextForSnippet(offset: 2) == "pinned old")
        #expect(try await store.historyTextForSnippet(offset: 3) == nil)
        #expect(try await store.historyTextForSnippet(offset: -1) == nil)
    }

    @Test("A secret, a masked kind or a non-text clip gives nothing, not the next clip")
    func historyRefuses() async throws {
        let store = try makeStore()
        try await insert(store, "synthetic-secret", minutesAgo: 1, isSensitive: true)
        var minutes = 2.0
        for kind in ClipContentKind.allCases where kind.prefersMaskedPreview {
            try await insert(store, "masked-\(kind.rawValue)", minutesAgo: minutes, kind: kind)
            minutes += 1
        }
        let maskedCount = Int(minutes) - 1
        for offset in 0..<maskedCount {
            #expect(try await store.historyTextForSnippet(offset: offset) == nil)
        }
        try await insert(store, "plain", minutesAgo: minutes)
        #expect(try await store.historyTextForSnippet(offset: maskedCount) == "plain")

        let binary = ClipItem(
            createdAt: Date.now.addingTimeInterval(-3_600), kind: .image, preview: "image",
            contentHash: "hash-image")
        try await store.insert(
            binary, content: .binary(data: Data([1, 2, 3]), typeIdentifier: "public.png"))
        #expect(try await store.historyTextForSnippet(offset: maskedCount + 1) == nil)
    }

    @Test("Archived clips are skipped")
    func historyArchived() async throws {
        let store = try makeStore()
        let archived = try await insert(store, "archived", minutesAgo: 1)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }
        try await insert(store, "here", minutesAgo: 2)
        #expect(try await store.historyTextForSnippet(offset: 0) == "here")
    }

    @Test("Expired clips are skipped")
    func historyExpired() async throws {
        let store = try makeStore()
        try await insert(
            store, "gone", minutesAgo: 1, expiresAt: Date.now.addingTimeInterval(-60))
        try await insert(store, "here", minutesAgo: 2)
        #expect(try await store.historyTextForSnippet(offset: 0) == "here")
    }
}
