import Foundation
import GRDB

/// Optional guarded capability for generated titles derived from an earlier body.
/// Retains the legacy ClipEnriching requirements for existing conformers.
public protocol ContentBoundTitleStoring: Sendable {
    @discardableResult
    func updateTitleIfEmptyAndCurrent(
        id: UUID, title: String, expectedText: String
    ) async throws -> Bool
}

extension GRDBClipboardStore {
    /// Kinds without a free-text body for a generated title to describe. Masked
    /// kinds stay titleable, as capture plans titles for every non-sensitive text
    /// clip: the model tier sees sanitized input and the heuristic tier emits
    /// fixed titles for them.
    static let titleIneligibleKinds: [String] = [
        ClipContentKind.image, .fileReference
    ].map(\.rawValue)
}

extension GRDBClipboardStore: ContentBoundTitleStoring {
    public func updateTitleIfEmptyAndCurrent(
        id: UUID, title: String, expectedText: String
    ) async throws -> Bool {
        try Task.checkCancellation()
        let excludedKinds = Self.titleIneligibleKinds
        let placeholders = excludedKinds.map { _ in "?" }.joined(separator: ", ")
        return try await writer.write { db in
            try Task.checkCancellation()
            let now = Date.now
            var arguments: [any DatabaseValueConvertible] = [
                title, now, id.uuidString, expectedText, now, "public.file-url"
            ]
            arguments.append(contentsOf: excludedKinds)
            // Visibility uses the shared read predicate: an expired row that
            // retention keeps (pinned, boarded, or a snippet) stays visible, so
            // its current body stays titleable too.
            try db.execute(
                sql: """
                    UPDATE clip SET title = ?, updatedAt = ?, needsUpload = 1
                    WHERE clip.id = ? AND clip.title = '' AND clip.contentText = ?
                      AND clip.contentBlobHash IS NULL AND clip.isSensitive = 0
                      AND clip.isArchived = 0
                      AND \(Self.unexpiredPredicate)
                      AND (clip.contentTypeIdentifier IS NULL OR clip.contentTypeIdentifier != ?)
                      AND clip.kind NOT IN (\(placeholders))
                    """,
                arguments: StatementArguments(arguments))
            return db.changesCount == 1
        }
    }
}
