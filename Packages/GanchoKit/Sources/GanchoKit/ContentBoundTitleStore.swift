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

extension GRDBClipboardStore: ContentBoundTitleStoring {
    public func updateTitleIfEmptyAndCurrent(
        id: UUID, title: String, expectedText: String
    ) async throws -> Bool {
        try Task.checkCancellation()
        let allowedKinds = ClipContentKind.allCases.filter {
            !$0.prefersMaskedPreview && $0 != .image && $0 != .fileReference
        }.map(\.rawValue)
        let placeholders = allowedKinds.map { _ in "?" }.joined(separator: ", ")
        return try await writer.write { db in
            try Task.checkCancellation()
            let now = Date.now
            var arguments: [any DatabaseValueConvertible] = [
                title, now, id.uuidString, expectedText, now, "public.file-url"
            ]
            arguments.append(contentsOf: allowedKinds)
            try db.execute(
                sql: """
                    UPDATE clip SET title = ?, updatedAt = ?, needsUpload = 1
                    WHERE id = ? AND title = '' AND contentText = ?
                      AND contentBlobHash IS NULL AND isSensitive = 0 AND isArchived = 0
                      AND (expiresAt IS NULL OR expiresAt > ?)
                      AND (contentTypeIdentifier IS NULL OR contentTypeIdentifier != ?)
                      AND kind IN (\(placeholders))
                    """,
                arguments: StatementArguments(arguments))
            return db.changesCount == 1
        }
    }
}
