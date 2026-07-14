import Foundation
import GRDB

/// Free-tier ceiling for the curated library (the merge decision: Free
/// includes 20 snippets).
public enum SnippetLimits {
    public static let freeMaxSnippets = 20
    /// The first point where repeated use has proven enough value to offer
    /// permanent curation. Equality, rather than `>=`, makes the nudge one-shot.
    public static let promotionSuggestionUseThreshold = 3

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

    /// Tier-1 enrichment: sets the title without touching content. Flags
    /// `needsUpload` so the on-device smart title reaches the other devices —
    /// enrichment runs per-device, but its FRUITS (title/OCR) sync.
    public func updateTitle(id: UUID, title: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET title = ?, updatedAt = ?, needsUpload = 1 WHERE id = ?",
                arguments: [title, Date(), id.uuidString])
        }
    }

    /// Generated titles are opportunistic enrichment, never authority over a
    /// user's curation. The predicate and write share one transaction so a
    /// manual title saved while the model was running always wins the race.
    @discardableResult
    public func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE clip SET title = ?, updatedAt = ?, needsUpload = 1
                    WHERE id = ? AND title = ''
                    """,
                arguments: [title, Date(), id.uuidString])
            return db.changesCount == 1
        }
    }

    /// OCR enrichment for image clips: extracted text lands in contentText
    /// (FTS-indexed → screenshots become searchable) without altering the
    /// preview or the blob. Flags `needsUpload` so the OCR fruit syncs.
    public func attachExtractedText(id: UUID, text: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET contentText = ?, updatedAt = ?, needsUpload = 1 WHERE id = ?",
                arguments: [text, Date(), id.uuidString])
        }
    }

    /// Edits a non-sensitive text-backed clip and recomputes its preview. The
    /// hash is left as-is on purpose: edits are curation, and re-copying the
    /// original must still dedupe against this row. Invalidates the stale
    /// semantic vector and flags `needsUpload` for cross-device propagation.
    /// The SQL predicates repeat the controller guards atomically so a row that
    /// becomes sensitive or binary while an editor is open cannot be replaced.
    public func updateClipText(id: UUID, text: String) async throws {
        // The rejected-kind list is derived from the shared editability policy
        // so the SQL belt can never drift from the app-layer guard — critically,
        // it excludes every masked-preview kind (secret/card/JWT), not just the
        // few a bare `isSensitive` check happens to catch.
        let rejectedKinds = ClipContentKind.textEditingRejectedKinds.map(\.rawValue)
        let kindPlaceholders = rejectedKinds.map { _ in "?" }.joined(separator: ", ")
        try await writer.write { db in
            var arguments: [any DatabaseValueConvertible] = [
                text, String(text.prefix(120)), Date(), id.uuidString
            ]
            arguments.append(contentsOf: rejectedKinds)
            arguments.append("public.file-url")
            try db.execute(
                sql: """
                    UPDATE clip
                    SET contentText = ?, preview = ?, updatedAt = ?, needsUpload = 1
                    WHERE id = ?
                      AND isSensitive = 0
                      AND kind NOT IN (\(kindPlaceholders))
                      AND contentText IS NOT NULL
                      AND contentBlobHash IS NULL
                      AND (contentTypeIdentifier IS NULL OR contentTypeIdentifier != ?)
                    """,
                arguments: StatementArguments(arguments))
            guard db.changesCount == 1 else { throw ClipTextEditError.readOnly }
            try db.execute(
                sql: "DELETE FROM clip_embedding WHERE clipID = ?",
                arguments: [id.uuidString])
        }
    }

    /// Creates a snippet from scratch (the `gancho save` / editor-import path),
    /// bypassing the capture pipeline. Lands directly in the curated world
    /// (`isSnippet`), exempt from retention. The source language is recorded
    /// as a `lang:<id>` tag (no schema/sync change) so the Library can show
    /// and search by it. No dedupe: an explicit save is always intentional.
    @discardableResult
    public func saveSnippet(
        title: String, text: String, language: String? = nil
    ) async throws
        -> ClipItem
    {
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (trimmedLanguage?.isEmpty == false) ? ["lang:\(trimmedLanguage!)"] : []
        let item = ClipItem(
            kind: .code, title: title, preview: String(text.prefix(120)),
            contentHash: ClipItem.hash(of: text, kind: .code), tags: tags)
        var row = ClipRow(item: item)
        row.contentText = text
        row.isSnippet = true
        let finalRow = row
        try await writer.write { db in try finalRow.insert(db) }
        return item
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

    /// Sets (or clears, with nil/blank) a snippet's invocation keyword.
    public func setKeyword(id: UUID, keyword: String?) async throws {
        let trimmed = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET keyword = ?, updatedAt = ? WHERE id = ? AND isSnippet = 1",
                arguments: [(trimmed?.isEmpty == false) ? trimmed : nil, Date(), id.uuidString])
        }
    }

    /// Bumps the usage counter — call when a snippet is inserted.
    public func incrementUses(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET uses = uses + 1 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Records a paste/copy of any clip: bumps `uses` and freshens `lastUsedAt`
    /// (what the frecency re-rank reads; `idx_clip_frecency` covers the pair).
    /// Deliberately does NOT set `needsUpload` — one sync cycle per paste would
    /// be a storm; the freshened `lastUsedAt` rides along with the clip's next
    /// real change instead (accepted, documented drift).
    public func recordUse(id: UUID, now: Date = .now) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET uses = uses + 1, lastUsedAt = ? WHERE id = ?",
                arguments: [now, id.uuidString])
        }
    }

    /// Records one successful reuse and resolves a one-shot promotion candidate
    /// in the same write transaction. The query returns metadata only; content
    /// is neither loaded nor logged. Exact equality means dismissing the nudge
    /// needs no persistent flag — the next use advances past the threshold.
    @discardableResult
    public func recordUseAndSnippetSuggestion(
        id: UUID, now: Date = .now,
        requiredUses: Int = SnippetLimits.promotionSuggestionUseThreshold
    ) async throws -> ClipItem? {
        // Never nudge the user to permanently retain and sync a masked-preview
        // kind (secret/card/JWT): promotion would outlive the short sensitive
        // lifetime and cross devices. `isSensitive` alone misses a bare JWT.
        let maskedKinds = ClipContentKind.allCases.filter(\.prefersMaskedPreview).map(\.rawValue)
        let kindPlaceholders = maskedKinds.map { _ in "?" }.joined(separator: ", ")
        return try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET uses = uses + 1, lastUsedAt = ? WHERE id = ?",
                arguments: [now, id.uuidString])
            var arguments: [any DatabaseValueConvertible] = [id.uuidString, requiredUses]
            arguments.append(contentsOf: maskedKinds)
            return try ClipRow.filter(
                sql: """
                    id = ? AND uses = ? AND isSnippet = 0
                    AND isSensitive = 0 AND isArchived = 0
                    AND kind NOT IN (\(kindPlaceholders))
                    """,
                arguments: StatementArguments(arguments)
            ).fetchOne(db)?.item
        }
    }

    /// The snippet invoked by an exact keyword (case-insensitive), if any — the
    /// in-app keyword expansion path.
    public func snippet(matchingKeyword keyword: String) async throws -> ClipItem? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try await writer.read { db in
            try ClipRow.filter(
                sql: "isSnippet = 1 AND keyword = ? COLLATE NOCASE", arguments: [trimmed]
            ).fetchOne(db)?.item
        }
    }
}

private enum ClipTextEditError: Error {
    case readOnly
}
