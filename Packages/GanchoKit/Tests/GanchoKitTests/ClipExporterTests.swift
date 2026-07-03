import Foundation
import Testing

@testable import GanchoKit

/// Pure formatting tests for ``ClipExporter`` — no database, no blob store, no
/// timers. They pin the byte-level layout the store delegates to (CSV header,
/// per-row escaping, one-shot JSON), independent of any DB read.
@Suite("ClipExporter — byte-exact CSV and JSON formatting")
struct ClipExporterTests {

    /// A row built the same way the store's write paths build one: from a
    /// `ClipItem`, with the text column set afterwards.
    private func row(
        id: String = "00000000-0000-0000-0000-000000000001",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        title: String = "t",
        preview: String = "a,b",
        contentHash: String = "h1",
        contentText: String? = "plain"
    ) -> ClipRow {
        let item = ClipItem(
            id: UUID(uuidString: id) ?? UUID(),
            createdAt: createdAt,
            kind: .text,
            title: title,
            preview: preview,
            contentHash: contentHash)
        var row = ClipRow(item: item)
        row.contentText = contentText
        return row
    }

    @Test("csvEscape leaves a plain field untouched")
    func csvEscapePlain() {
        #expect(ClipExporter.csvEscape("plain") == "plain")
    }

    @Test("csvEscape quotes commas, quotes and newlines per RFC-4180")
    func csvEscapeSpecialCharacters() {
        #expect(ClipExporter.csvEscape("a,b") == "\"a,b\"")
        #expect(ClipExporter.csvEscape("he said \"hi\"") == "\"he said \"\"hi\"\"\"")
        #expect(ClipExporter.csvEscape("line one\nline two") == "\"line one\nline two\"")
    }

    @Test("csvEscape neutralizes formula-injection leads exactly")
    func csvEscapeFormulaInjection() {
        // A leading = + - @ (or tab/CR) is prefixed with a single apostrophe.
        // With no other special character the field is NOT additionally quoted.
        #expect(ClipExporter.csvEscape("=SUM(A1:A9)") == "'=SUM(A1:A9)")
        #expect(ClipExporter.csvEscape("+1") == "'+1")
        #expect(ClipExporter.csvEscape("-1") == "'-1")
        #expect(ClipExporter.csvEscape("@cmd") == "'@cmd")
        #expect(ClipExporter.csvEscape("\tlead") == "'\tlead")
        #expect(ClipExporter.csvEscape("\rlead") == "'\rlead")
        // Apostrophe prefix happens BEFORE the RFC-4180 quoting: a formula lead
        // that also contains a quote gets both.
        #expect(
            ClipExporter.csvEscape("=HYPERLINK(\"x\")")
                == "\"'=HYPERLINK(\"\"x\"\")\"")
    }

    @Test("csvHeader is the exact frozen header line")
    func csvHeaderIsFrozen() {
        #expect(
            ClipExporter.csvHeader
                == "id,createdAt,kind,title,preview,contentHash,sourceApp,"
                + "isPinned,contentText,contentBlobHash\n")
    }

    @Test("csvLine renders the exact field order, escaping and trailing newline")
    func csvLineExactBytes() {
        let line = ClipExporter.csvLine(for: row())
        // id, ISO8601 createdAt, kind, title, escaped preview, hash, empty
        // sourceApp, isPinned=false, contentText, empty blob hash, "\n".
        #expect(
            line
                == "00000000-0000-0000-0000-000000000001,2023-11-14T22:13:20Z,"
                + "text,t,\"a,b\",h1,,false,plain,\n")
    }

    @Test("json wraps rows in a version-1 document and round-trips")
    func jsonRoundTrips() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = [
            row(
                id: "00000000-0000-0000-0000-000000000001",
                createdAt: exportedAt, preview: "first", contentHash: "h1",
                contentText: "first body"),
            row(
                id: "00000000-0000-0000-0000-000000000002",
                createdAt: exportedAt.addingTimeInterval(60), preview: "second",
                contentHash: "h2", contentText: "second body"),
        ]

        let data = try ClipExporter.json(rows: rows, exportedAt: exportedAt)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        #expect(document.version == 1)
        #expect(document.exportedAt == exportedAt)
        #expect(document.clips.count == 2)
        #expect(document.clips[0].contentText == "first body")
        #expect(document.clips[1].id == "00000000-0000-0000-0000-000000000002")
    }

    @Test("json uses sorted keys (clips < exportedAt < version)")
    func jsonSortsKeys() throws {
        let data = try ClipExporter.json(
            rows: [row()], exportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let text = String(decoding: data, as: UTF8.self)

        let clips = try #require(text.range(of: "\"clips\""))
        let exportedAt = try #require(text.range(of: "\"exportedAt\""))
        let version = try #require(text.range(of: "\"version\""))
        #expect(clips.lowerBound < exportedAt.lowerBound)
        #expect(exportedAt.lowerBound < version.lowerBound)
    }
}
