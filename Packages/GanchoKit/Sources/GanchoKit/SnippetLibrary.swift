import Foundation
import GRDB

/// Free-tier ceiling for the curated library (the merge decision: Free
/// includes 20 snippets).
public enum SnippetLimits {
    public static let freeMaxSnippets = 20

    public static func canPromote(currentSnippetCount: Int, isPro: Bool) -> Bool {
        isPro || currentSnippetCount < freeMaxSnippets
    }
}

extension GRDBClipboardStore {
    /// The bridge between worlds: one gesture turns an ephemeral clip into
    /// a permanent snippet (optionally titled). Exempt from retention and
    /// archiving by schema.
    public func promoteToSnippet(id: UUID, title: String? = nil) async throws {
        try await writer.write { db in
            if let title {
                try db.execute(
                    sql: "UPDATE clip SET isSnippet = 1, title = ?, updatedAt = ? WHERE id = ?",
                    arguments: [title, Date(), id.uuidString])
            } else {
                try db.execute(
                    sql: "UPDATE clip SET isSnippet = 1, updatedAt = ? WHERE id = ?",
                    arguments: [Date(), id.uuidString])
            }
        }
    }

    /// Back to plain history (retention applies again).
    public func demoteFromSnippet(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isSnippet = 0, updatedAt = ? WHERE id = ?",
                arguments: [Date(), id.uuidString])
        }
    }

    public func snippets() async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow.filter(Column("isSnippet") == true)
                .order(Column("updatedAt").desc)
                .fetchAll(db).map(\.item)
        }
    }

    public func snippetCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE isSnippet = 1") ?? 0
        }
    }

    /// Tier-1 enrichment: sets the title without touching content.
    public func updateTitle(id: UUID, title: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET title = ?, updatedAt = ? WHERE id = ?",
                arguments: [title, Date(), id.uuidString])
        }
    }

    /// OCR enrichment for image clips: extracted text lands in contentText
    /// (FTS-indexed → screenshots become searchable) without altering the
    /// preview or the blob.
    public func attachExtractedText(id: UUID, text: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET contentText = ?, updatedAt = ? WHERE id = ?",
                arguments: [text, Date(), id.uuidString])
        }
    }

    /// Edits ANY text clip's content (Quick Look editing); recomputes the
    /// preview. The hash is left as-is on purpose: edits are curation, and
    /// re-copying the original must still dedupe against this row.
    public func updateClipText(id: UUID, text: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET contentText = ?, preview = ?, updatedAt = ? WHERE id = ?",
                arguments: [text, String(text.prefix(120)), Date(), id.uuidString])
        }
    }

    /// Edits a snippet's title and full text content (the editor surface).
    public func updateSnippet(id: UUID, title: String, text: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE clip SET title = ?, contentText = ?, preview = ?, updatedAt = ?
                    WHERE id = ? AND isSnippet = 1
                    """,
                arguments: [title, text, String(text.prefix(120)), Date(), id.uuidString])
        }
    }
}
