import Foundation
import GRDB

/// Optional capability for background work derived from an earlier text snapshot.
/// The legacy ClipEnriching surface stays source-compatible; asynchronous producers
/// require this capability rather than falling back to an unconditional vector write.
public protocol ContentBoundEmbeddingStoring: Sendable {
    /// Stores a vector only while the exact source body is still eligible and current.
    /// Title/keyword-only edits do not invalidate a body-derived vector. Returning to
    /// the same body is safe: the vector depends on that body, not its edit history.
    @discardableResult
    func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool
}

extension GRDBClipboardStore {
    /// Kinds background embedding never indexes: every masked-preview kind and the
    /// payloads without a free-text body. Shared by the guarded write and the stale
    /// refresh queue, so the queue never offers a row the write must reject.
    static let embeddingIneligibleKinds: [String] = ClipContentKind.allCases.filter {
        $0.prefersMaskedPreview || $0 == .image || $0 == .fileReference
    }.map(\.rawValue)
}

extension GRDBClipboardStore: ContentBoundEmbeddingStoring {
    public func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool {
        try Task.checkCancellation()
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let excludedKinds = Self.embeddingIneligibleKinds
        let placeholders = excludedKinds.map { _ in "?" }.joined(separator: ", ")
        return try await writer.write { db in
            try Task.checkCancellation()
            var arguments: [any DatabaseValueConvertible] = [
                vector.count, data, EmbeddingModelInfo.currentVersion, clipID.uuidString,
                expectedText, Date.now, "public.file-url"
            ]
            arguments.append(contentsOf: excludedKinds)
            // Visibility uses the shared read predicate: an expired row that
            // retention keeps (pinned, boarded, or a snippet) stays searchable,
            // so its current body must stay indexable too.
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO clip_embedding (clipID, dimension, vector, modelVersion)
                    SELECT clip.id, ?, ?, ? FROM clip
                    WHERE clip.id = ? AND clip.contentText = ? AND clip.contentBlobHash IS NULL
                      AND clip.isSensitive = 0 AND clip.isArchived = 0
                      AND \(Self.unexpiredPredicate)
                      AND (clip.contentTypeIdentifier IS NULL OR clip.contentTypeIdentifier != ?)
                      AND clip.kind NOT IN (\(placeholders))
                    """,
                arguments: StatementArguments(arguments))
            return db.changesCount == 1
        }
    }
}
