import Foundation
import GRDB

/// The write behind a double-copy merge.
public protocol ClipMerging: Sendable {
    /// Replaces a clip's text with a merge of it, sets its parts, kind and hash, moves
    /// it to the top and marks it for upload. False when the text is no longer
    /// `current`, the clip is sensitive, masked, a snippet or not plain text, or
    /// `kind` is not editable text.
    func mergeClipText(
        id: UUID, expecting current: String, text: String, parts: ClipParts,
        kind: ClipContentKind
    ) async throws -> Bool
}

extension GRDBClipboardStore: ClipMerging {
    public func mergeClipText(
        id: UUID, expecting current: String, text: String, parts: ClipParts,
        kind: ClipContentKind
    ) async throws -> Bool {
        guard parts.split(text) != nil, kind.allowsTextEditing else { return false }
        let rejectedKinds = ClipContentKind.textEditingRejectedKinds.map(\.rawValue)
        let kindPlaceholders = rejectedKinds.map { _ in "?" }.joined(separator: ", ")
        let now = Date()
        // A recopy of the first part must not dedupe into the merged clip.
        let hash = ClipItem.hash(of: ContentNormalizer.canonicalText(text, kind: kind), kind: kind)
        return try await writer.write { db in
            var arguments: [any DatabaseValueConvertible] = [
                text, String(text.prefix(120)), kind.rawValue, hash, parts.encoded, now, now,
                id.uuidString, current
            ]
            arguments.append(contentsOf: rejectedKinds)
            try db.execute(
                sql: """
                    UPDATE clip
                    SET contentText = ?, preview = ?, kind = ?, contentHash = ?, parts = ?,
                        updatedAt = ?, lastUsedAt = ?, needsUpload = 1
                    WHERE id = ? AND contentText = ?
                      AND isSensitive = 0 AND isSnippet = 0
                      AND kind NOT IN (\(kindPlaceholders))
                      AND contentBlobHash IS NULL
                      AND (contentTypeIdentifier IS NULL OR contentTypeIdentifier != 'public.file-url')
                    """,
                arguments: StatementArguments(arguments))
            guard db.changesCount == 1 else { return false }
            try db.execute(
                sql: "DELETE FROM clip_embedding WHERE clipID = ?", arguments: [id.uuidString])
            return true
        }
    }
}
