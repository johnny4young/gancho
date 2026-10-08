import Foundation
import GRDB

/// Reads supported migration sources without mutating either the source or the
/// destination. Classification, secret policy, deduplication, and persistence
/// belong to the app-layer migration coordinator so imports cannot bypass the
/// normal ingestion rules.
public enum ClipImporter {
    /// One portable text candidate decoded from a foreign source.
    public struct Candidate: Sendable, Equatable {
        public var text: String
        public var title: String?
        public var isPinned: Bool

        public init(text: String, title: String? = nil, isPinned: Bool = false) {
            self.text = text
            self.title = title
            self.isPinned = isPinned
        }
    }

    /// A decoded source plus the number of rows that Gancho deliberately
    /// cannot import. The document stays in memory until the user confirms or
    /// cancels; merely discovering a file never creates one.
    public struct Document: Sendable, Equatable {
        public var candidates: [Candidate]
        public var unsupportedCount: Int

        public init(candidates: [Candidate], unsupportedCount: Int = 0) {
            self.candidates = candidates
            self.unsupportedCount = unsupportedCount
        }
    }

    /// Stable, content-free reasons a source cannot be previewed. Callers map
    /// these cases to localized UI instead of displaying database errors that
    /// could include paths or schema fragments.
    public enum UnreadableReason: String, Error, Sendable, Equatable {
        case notUTF8
        case emptyCSV
        case missingTextColumn
        case unclosedQuotedField
        case cannotOpenCSVFile
        case cannotOpenMaccyDatabase
        case unexpectedMaccySchema
    }

    public enum ImportError: Error, Sendable, Equatable {
        case unreadable(UnreadableReason)
    }

    /// Decodes generic RFC-4180 CSV. The header must include `text`; `title`
    /// and `pinned` are optional. Empty or structurally short data rows are
    /// counted as unsupported rather than silently presented as importable.
    /// Gancho's own CSV export (`contentText`, `isPinned`) reads back too, with
    /// its formula-guard apostrophe removed.
    public static func readCSV(_ data: Data) throws -> Document {
        guard var content = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadable(.notUTF8)
        }
        if content.first == "\u{feff}" { content.removeFirst() }

        var header: CSVHeader?
        var candidates: [Candidate] = []
        var unsupportedCount = 0
        try forEachCSVRow(content) { rawRow in
            if header == nil {
                header = CSVHeader(rawRow)
                return
            }
            guard let header, header.textIndex != nil else { return }
            guard let text = header.field(header.textIndex, in: rawRow),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                unsupportedCount += 1
                return
            }
            let title = header.field(header.titleIndex, in: rawRow).flatMap { field -> String? in
                let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let pinned =
                header.field(header.pinnedIndex, in: rawRow).map { field in
                    switch field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "true", "1", "yes": true
                    default: false
                    }
                } ?? false
            candidates.append(Candidate(text: text, title: title, isPinned: pinned))
        }
        // Finish scanning before header validation, preserving syntax-error precedence.
        // A malformed tail must never expose the candidates already projected locally.
        guard let header else { throw ImportError.unreadable(.emptyCSV) }
        guard header.textIndex != nil else {
            throw ImportError.unreadable(.missingTextColumn)
        }
        return Document(candidates: candidates, unsupportedCount: unsupportedCount)
    }

    /// Reads Maccy's Core Data SQLite database through a read-only connection.
    /// Only portable plain text is decoded; images and foreign representations
    /// are reported as unsupported. SQLite errors are collapsed to stable
    /// reasons so no source path or content escapes into diagnostics.
    public static func readMaccy(databaseAt url: URL) async throws -> Document {
        let source: DatabaseQueue
        do {
            var configuration = Configuration()
            configuration.readonly = true
            source = try DatabaseQueue(path: url.path, configuration: configuration)
        } catch {
            throw ImportError.unreadable(.cannotOpenMaccyDatabase)
        }

        do {
            return try await source.read { database in
                let total =
                    try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM ZHISTORYITEMCONTENT WHERE ZVALUE IS NOT NULL"
                    ) ?? 0
                let values = try String.fetchAll(
                    database,
                    sql: """
                        SELECT CAST(ZVALUE AS TEXT) FROM ZHISTORYITEMCONTENT
                        WHERE ZTYPE = 'public.utf8-plain-text' AND ZVALUE IS NOT NULL
                        """)
                let candidates = values.compactMap { value -> Candidate? in
                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return Candidate(text: value)
                }
                return Document(
                    candidates: candidates,
                    unsupportedCount: max(0, total - candidates.count))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.unreadable(.unexpectedMaccySchema)
        }
    }

    /// Header interpretation stays separate from row scanning. The first matching
    /// column and the presence of `contentText` preserve the existing export policy.
    private struct CSVHeader {
        let textIndex: Int?
        let titleIndex: Int?
        let pinnedIndex: Int?
        let isGanchoExport: Bool

        init(_ row: [String]) {
            let names = row.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            textIndex = names.firstIndex(of: "text") ?? names.firstIndex(of: "contenttext")
            titleIndex = names.firstIndex(of: "title")
            pinnedIndex = names.firstIndex(of: "pinned") ?? names.firstIndex(of: "ispinned")
            isGanchoExport = names.contains("contenttext")
        }

        /// Decodes only the projected field, so Gancho exports never allocate a
        /// second, guard-stripped copy of every column in the row.
        func field(_ index: Int?, in row: [String]) -> String? {
            guard let index, row.indices.contains(index) else { return nil }
            return isGanchoExport ? ClipExporter.removingFormulaGuard(row[index]) : row[index]
        }
    }

    /// Scans quoted commas, escaped quotes, and quoted newlines using the existing
    /// character policy. Only one raw row is live at a time; the visitor cannot
    /// publish a result, and any unterminated field still fails the whole preview.
    private static func forEachCSVRow(_ content: String, visit: ([String]) -> Void) throws {
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = content.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { visit(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break
                default: field.append(character)
                }
            }
        }
        guard !inQuotes else {
            throw ImportError.unreadable(.unclosedQuotedField)
        }
        endRow()
    }
}
