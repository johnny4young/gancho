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

extension GRDBClipboardStore: ContentBoundEmbeddingStoring {
    public func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool {
        try Task.checkCancellation()
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let excludedKinds = ClipContentKind.allCases.filter {
            $0.prefersMaskedPreview || $0 == .image || $0 == .fileReference
        }.map(\.rawValue)
        let placeholders = excludedKinds.map { _ in "?" }.joined(separator: ", ")
        return try await writer.write { db in
            try Task.checkCancellation()
            var arguments: [any DatabaseValueConvertible] = [
                vector.count, data, EmbeddingModelInfo.currentVersion, clipID.uuidString,
                expectedText, Date.now, "public.file-url"
            ]
            arguments.append(contentsOf: excludedKinds)
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO clip_embedding (clipID, dimension, vector, modelVersion)
                    SELECT id, ?, ?, ? FROM clip
                    WHERE id = ? AND contentText = ? AND contentBlobHash IS NULL
                      AND isSensitive = 0 AND isArchived = 0
                      AND (expiresAt IS NULL OR expiresAt > ?)
                      AND (contentTypeIdentifier IS NULL OR contentTypeIdentifier != ?)
                      AND kind NOT IN (\(placeholders))
                    """,
                arguments: StatementArguments(arguments))
            return db.changesCount == 1
        }
    }
}
