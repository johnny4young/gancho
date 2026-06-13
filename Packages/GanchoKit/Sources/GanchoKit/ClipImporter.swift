import Foundation
import GRDB

/// Imports from competing tools and generic formats into the store, riding
/// the same dedupe and (for foreign databases) read-only access. Every
/// importer returns counts; nothing is ever modified at the source.
public enum ClipImporter {
    public struct Summary: Sendable, Equatable {
        public var imported: Int
        public var skippedDuplicates: Int

        public init(imported: Int = 0, skippedDuplicates: Int = 0) {
            self.imported = imported
            self.skippedDuplicates = skippedDuplicates
        }
    }

    public enum ImportError: Error, Equatable {
        case unreadable(String)
    }

    /// Generic CSV: header must include `text` (optional `title`, `pinned`).
    public static func importCSV(
        _ data: Data, into store: GRDBClipboardStore
    ) async throws -> Summary {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadable("not UTF-8")
        }
        var lines = parseCSV(content)
        guard let header = lines.first else { throw ImportError.unreadable("empty CSV") }
        lines.removeFirst()
        guard let textIndex = header.firstIndex(of: "text") else {
            throw ImportError.unreadable("missing 'text' column")
        }
        let titleIndex = header.firstIndex(of: "title")
        let pinnedIndex = header.firstIndex(of: "pinned")

        var summary = Summary()
        for row in lines where row.count > textIndex {
            let text = row[textIndex]
            guard !text.isEmpty else { continue }
            let item = ClipItem(
                title: titleIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "",
                preview: String(text.prefix(120)),
                contentHash: ClipItem.hash(of: text, kind: .text),
                isPinned: pinnedIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }
                    == "true")
            let stored = try await store.insert(item, content: .text(text))
            if stored.id == item.id {
                summary.imported += 1
            } else {
                summary.skippedDuplicates += 1
            }
        }
        return summary
    }

    /// Maccy: read-only over its SQLite (HistoryItem/HistoryItemContent,
    /// plain-text contents only — images carry no portable provenance).
    public static func importMaccy(
        databaseAt url: URL, into store: GRDBClipboardStore
    ) async throws -> Summary {
        let source: DatabaseQueue
        do {
            var config = Configuration()
            config.readonly = true
            source = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            throw ImportError.unreadable("cannot open Maccy database")
        }

        let texts: [String]
        do {
            texts = try await source.read { db in
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT CAST(ZVALUE AS TEXT) FROM ZHISTORYITEMCONTENT
                        WHERE ZTYPE = 'public.utf8-plain-text' AND ZVALUE IS NOT NULL
                        """)
            }
        } catch {
            throw ImportError.unreadable("unexpected Maccy schema")
        }

        var summary = Summary()
        for text in texts where !text.isEmpty {
            let item = ClipItem(
                preview: String(text.prefix(120)),
                contentHash: ClipItem.hash(of: text, kind: .text))
            let stored = try await store.insert(item, content: .text(text))
            if stored.id == item.id {
                summary.imported += 1
            } else {
                summary.skippedDuplicates += 1
            }
        }
        return summary
    }

    /// Minimal RFC-4180 parser (quotes, escaped quotes, newlines in quotes).
    static func parseCSV(_ content: String) -> [[String]] {
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
        endRow()
        return rows
    }
}
