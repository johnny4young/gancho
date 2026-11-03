import Foundation
import GRDB

/// The write behind a double-copy merge.
public protocol ClipMerging: Sendable {
    /// Replaces a clip's text with a merge of it, sets its parts, kind and hash,
    /// optionally moves it to the top and marks it for upload. False when the
    /// text is no longer `current`, the clip is sensitive, masked, a snippet or
    /// not plain text, or `kind` is not editable text.
    func mergeClipText(
        id: UUID, expecting current: String, text: String, parts: ClipParts,
        kind: ClipContentKind, movesToTop: Bool
    ) async throws -> Bool

    /// The same merge into a rich text clip: its RTF is dropped and it becomes
    /// plain text. False unless the clip still holds RTF with `contentHash`.
    func mergeRichClipText(
        id: UUID, expectingHash contentHash: String, text: String, parts: ClipParts,
        kind: ClipContentKind, movesToTop: Bool
    ) async throws -> Bool
}

extension ClipMerging {
    public func mergeClipText(
        id: UUID, expecting current: String, text: String, parts: ClipParts,
        kind: ClipContentKind
    ) async throws -> Bool {
        try await mergeClipText(
            id: id, expecting: current, text: text, parts: parts, kind: kind, movesToTop: true)
    }
}

private struct ClipMergeWrite: Sendable {
    let id: UUID
    let text: String
    let parts: ClipParts
    let kind: ClipContentKind
    let movesToTop: Bool
}

extension GRDBClipboardStore: ClipMerging {
    public func mergeClipText(
        id: UUID, expecting current: String, text: String, parts: ClipParts,
        kind: ClipContentKind, movesToTop: Bool
    ) async throws -> Bool {
        try await writeMerge(
            ClipMergeWrite(
                id: id, text: text, parts: parts, kind: kind, movesToTop: movesToTop),
            clearing: "",
            matching: """
                contentText = ? AND contentBlobHash IS NULL
                AND (contentTypeIdentifier IS NULL OR contentTypeIdentifier != 'public.file-url')
                """,
            arguments: [current])
    }

    public func mergeRichClipText(
        id: UUID, expectingHash contentHash: String, text: String, parts: ClipParts,
        kind: ClipContentKind, movesToTop: Bool
    ) async throws -> Bool {
        let blobHash = try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)?.contentBlobHash
        }
        guard let blobHash else { return false }
        let merged = try await writeMerge(
            ClipMergeWrite(
                id: id, text: text, parts: parts, kind: kind, movesToTop: movesToTop),
            clearing: ", contentBlobHash = NULL, contentTypeIdentifier = NULL",
            matching: """
                contentHash = ? AND contentBlobHash = ? AND contentTypeIdentifier = 'public.rtf'
                """,
            arguments: [contentHash, blobHash])
        if merged { await removeBlobIfOrphaned(blobHash) }
        return merged
    }

    private func writeMerge(
        _ merge: ClipMergeWrite, clearing: String, matching predicate: String, arguments: [String]
    ) async throws -> Bool {
        guard merge.parts.split(merge.text) != nil, merge.kind.allowsTextEditing else {
            return false
        }
        let rejectedKinds = ClipContentKind.textEditingRejectedKinds.map(\.rawValue)
        let kindPlaceholders = rejectedKinds.map { _ in "?" }.joined(separator: ", ")
        let now = Date()
        // A recopy of the first part must not dedupe into the merged clip.
        let hash = ClipItem.hash(
            of: ContentNormalizer.canonicalText(merge.text, kind: merge.kind), kind: merge.kind)
        return try await writer.write { db in
            var statementArguments: [any DatabaseValueConvertible] = [
                merge.text, String(merge.text.prefix(120)), merge.kind.rawValue, hash,
                merge.parts.encoded, now, merge.movesToTop, now, merge.id.uuidString
            ]
            statementArguments.append(contentsOf: arguments)
            statementArguments.append(contentsOf: rejectedKinds)
            try db.execute(
                sql: """
                    UPDATE clip
                    SET contentText = ?, preview = ?, kind = ?, contentHash = ?, parts = ?,
                        updatedAt = ?, lastUsedAt = CASE WHEN ? THEN ? ELSE lastUsedAt END,
                        needsUpload = 1\(clearing)
                    WHERE id = ? AND \(predicate)
                      AND isSensitive = 0 AND isSnippet = 0
                      AND kind NOT IN (\(kindPlaceholders))
                    """,
                arguments: StatementArguments(statementArguments))
            guard db.changesCount == 1 else { return false }
            try db.execute(
                sql: "DELETE FROM clip_embedding WHERE clipID = ?",
                arguments: [merge.id.uuidString])
            return true
        }
    }
}
