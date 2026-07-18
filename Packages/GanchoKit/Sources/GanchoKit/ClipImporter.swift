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
    public static func readCSV(_ data: Data) throws -> Document {
        guard var content = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadable(.notUTF8)
        }
        if content.first == "\u{feff}" { content.removeFirst() }

        var rows = try parseCSV(content)
        guard let rawHeader = rows.first else {
            throw ImportError.unreadable(.emptyCSV)
        }
        rows.removeFirst()
        let header = rawHeader.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let textIndex = header.firstIndex(of: "text") else {
            throw ImportError.unreadable(.missingTextColumn)
        }
        let titleIndex = header.firstIndex(of: "title")
        let pinnedIndex = header.firstIndex(of: "pinned")

        var candidates: [Candidate] = []
        var unsupportedCount = 0
        for row in rows {
            guard row.indices.contains(textIndex) else {
                unsupportedCount += 1
                continue
            }
            let text = row[textIndex]
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                unsupportedCount += 1
                continue
            }
            let title = titleIndex.flatMap { index -> String? in
                guard row.indices.contains(index) else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let pinned =
                pinnedIndex.flatMap { index -> Bool? in
                    guard row.indices.contains(index) else { return nil }
                    return
                        switch row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    {
                    case "true", "1", "yes": true
                    default: false
                    }
                } ?? false
            candidates.append(Candidate(text: text, title: title, isPinned: pinned))
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

    /// RFC-4180 parser with quoted commas, escaped quotes, and quoted newlines.
    /// It rejects unterminated quoted fields instead of importing a truncated
    /// document whose remaining rows would be impossible to account for.
    static func parseCSV(_ content: String) throws -> [[String]] {
        var rows: [[String]] = []
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
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
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
        return rows
    }
}
