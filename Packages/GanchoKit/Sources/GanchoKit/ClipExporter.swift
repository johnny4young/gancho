import Foundation

/// Pure export FORMATTING for clip rows: the byte-exact CSV and JSON
/// serializers, lifted out of ``GRDBClipboardStore`` so the layout logic is
/// unit-testable without a database, timers, or I/O.
///
/// The store still owns the row READ — a streaming `fetchCursor` for CSV, one
/// exactly-sized array for JSON (see ``GRDBClipboardStore/exportJSON(excludeSensitive:)``
/// and `.audit/21-store-finish.md`). This type only turns already-fetched rows
/// into bytes, and it is deliberately pure: the `exportedAt` timestamp is a
/// side value the store passes in (`.now`), never read here.
///
/// Internal to the module because the row-taking entry points speak `ClipRow`,
/// which is a storage detail. The wider URL-streaming reshape (a public facet)
/// is deferred (PR-K, `.audit/09` §8).
enum ClipExporter {
    /// The exact CSV header line, terminated by a newline. Field order and
    /// spelling are frozen: existing exports and their tests are byte-sensitive.
    static let csvHeader =
        "id,createdAt,kind,title,preview,contentHash,sourceApp,"
        + "isPinned,contentText,contentBlobHash\n"

    /// One escaped CSV record for `row`, terminated by a newline — same field
    /// order, escaping, and trailing newline the store emitted inline before.
    /// The `createdAt` value renders through a default ``ISO8601DateFormatter``,
    /// matching the store's per-read formatter byte-for-byte.
    static func csvLine(for row: ClipRow) -> String {
        let formatter = ISO8601DateFormatter()
        let fields = [
            row.id, formatter.string(from: row.createdAt), row.kind, row.title,
            row.preview, row.contentHash, row.sourceAppBundleID ?? "",
            row.isPinned ? "true" : "false", row.contentText ?? "",
            row.contentBlobHash ?? ""
        ]
        return fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    /// Versioned JSON document for `rows`, encoded in ONE shot with `.iso8601`
    /// dates and `[.prettyPrinted, .sortedKeys]`. Encoded whole — not streamed —
    /// on purpose: the pretty/sorted layout is implementation-defined Foundation
    /// behavior, and hand-assembling it would break existing exports' byte-compat
    /// (see `.audit/21-store-finish.md`). `exportedAt` is supplied by the caller
    /// so this stays pure and testable.
    static func json(rows: [ClipRow], exportedAt: Date) throws -> Data {
        let payload = ExportDocument(version: 1, exportedAt: exportedAt, clips: rows)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func csvEscape(_ field: String) -> String {
        // Formula-injection guard (OWASP CSV injection): clipboard text is
        // attacker-influenced by nature, and a field starting with = + - @
        // (or a leading tab/CR) executes as a formula when the CSV is opened
        // in Excel/Numbers/Sheets. Neutralize with a leading apostrophe —
        // spreadsheets then render the field as literal text.
        var field = field
        if let first = field.first, "=+-@\t\r".contains(first) {
            field = "'" + field
        }
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Export envelope — versioned so future schema changes stay importable.
struct ExportDocument: Codable {
    var version: Int
    var exportedAt: Date
    var clips: [ClipRow]
}
