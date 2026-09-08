import Foundation
import GRDB

/// Open export, kept beside the store rather than inside it.
///
/// Split out when the class body reached its size limit; the export
/// surface is self-contained and reads a snapshot rather than
/// participating in the store's query and write behavior, so it is the
/// cleanest seam available. Same pattern as `+Import` and `+SearchFilters`.
extension GRDBClipboardStore {
    /// Versioned JSON export: full metadata + text content; binary payloads
    /// referenced by content hash (the blobs directory travels alongside).
    public func exportJSON() async throws -> Data {
        try await exportJSON(excludeSensitive: false)
    }

    /// As ``exportJSON()``, optionally dropping detector-flagged sensitive
    /// clips — an export must not turn a short-expiry secret into permanent
    /// plaintext unless the caller explicitly opts in. (The zero-argument
    /// form keeps the `ClipboardStore` protocol contract unchanged.)
    ///
    /// Rows are gathered through a cursor into ONE exactly-sized array
    /// (capacity reserved from a COUNT in the same read), with sensitive rows
    /// skipped during the walk — no `fetchAll` growth over-allocation and no
    /// second filtered pass, so excluded rows never materialize at all. The
    /// document is still encoded in ONE shot, deliberately: streaming the
    /// encoder would mean hand-assembling the `.prettyPrinted`/`.sortedKeys`
    /// layout byte-for-byte, which is implementation-defined and would break
    /// byte compatibility with existing exports.
    /// ``exportCSV(excludeSensitive:)`` is the fully streamed format.
    public func exportJSON(excludeSensitive: Bool) async throws -> Data {
        let rows = try await writer.read { db -> [ClipRow] in
            var rows: [ClipRow] = []
            rows.reserveCapacity(try ClipRow.fetchCount(db))
            let cursor = try ClipRow.order(Column("createdAt").asc).fetchCursor(db)
            while let row = try cursor.next() {
                if excludeSensitive && row.isSensitive { continue }
                rows.append(row)
            }
            return rows
        }
        return try ClipExporter.json(rows: rows, exportedAt: .now)
    }

    /// RFC-4180 CSV: metadata + text content (binaries listed by reference).
    public func exportCSV() async throws -> Data {
        try await exportCSV(excludeSensitive: false)
    }

    /// As ``exportCSV()``, optionally dropping detector-flagged sensitive
    /// clips (see ``exportJSON(excludeSensitive:)``).
    ///
    /// Streams rows through a cursor instead of `fetchAll` so a 100k-row
    /// export never materializes every `ClipRow` at once — only the output
    /// text accumulates. Same bytes as before: same order, same escaping.
    public func exportCSV(excludeSensitive: Bool) async throws -> Data {
        // Field escaping/assembly is centralized in ``ClipExporter``; the cursor
        // walk stays here so streaming is preserved. Byte-identical to before.
        try await writer.read { db -> Data in
            var csv = ClipExporter.csvHeader
            let cursor = try ClipRow.order(Column("createdAt").asc).fetchCursor(db)
            while let row = try cursor.next() {
                if excludeSensitive && row.isSensitive { continue }
                csv += ClipExporter.csvLine(for: row)
            }
            return Data(csv.utf8)
        }
    }
}
