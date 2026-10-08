import Foundation
import GRDB

public enum SnippetDraftSaveError: Error, Equatable {
    case protectedContent, freeLimitReached
}

/// Atomic edits and explicit recovery, without exposing database operations.
public protocol SnippetDraftStoring: Sendable {
    /// Returns false when the original no longer exists as a snippet.
    func updateSnippetDraft(
        id: UUID, title: String, text: String, keyword: String?
    ) async throws
        -> Bool
    /// Inserts a freshly classified, safe item with a new identity; never deduplicates.
    func saveRecoveredSnippet(
        item: ClipItem, text: String, keyword: String?, isPro: Bool
    ) async throws
        -> ClipItem
}

extension GRDBClipboardStore: SnippetDraftStoring {
    public func updateSnippetDraft(
        id: UUID, title: String, text: String, keyword: String?
    ) async throws -> Bool {
        try Task.checkCancellation()
        let trimmed = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await writer.write { db in
            try Task.checkCancellation()
            let now = Date.now
            guard let row = try ClipRow.fetchOne(db, key: id.uuidString), row.isSnippet else {
                return false
            }
            guard !ClipSafePresentation.requiresMasking(row.item), !row.isArchived,
                row.expiresAt.map({ $0 > now }) ?? true,
                row.contentText != nil, row.contentBlobHash == nil
            else { throw SnippetDraftSaveError.protectedContent }
            try Self.writeSnippetEdit(
                row, title: title, text: text, keyword: trimmed?.isEmpty == false ? trimmed : nil,
                now: now, in: db)
            return true
        }
    }

    public func saveRecoveredSnippet(
        item: ClipItem, text: String, keyword: String?, isPro: Bool
    ) async throws -> ClipItem {
        try Task.checkCancellation()
        guard !ClipSafePresentation.requiresMasking(item),
            item.expiresAt.map({ $0 > .now }) ?? true
        else { throw SnippetDraftSaveError.protectedContent }
        let trimmed = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        var row = ClipRow(item: item)
        row.contentText = text
        row.isSnippet = true
        row.keyword = trimmed?.isEmpty == false ? trimmed : nil
        let recovered = row
        try await writer.write { db in
            try Task.checkCancellation()
            guard recovered.expiresAt.map({ $0 > .now }) ?? true else {
                throw SnippetDraftSaveError.protectedContent
            }
            let count =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE isSnippet = 1") ?? 0
            guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: isPro) else {
                throw SnippetDraftSaveError.freeLimitReached
            }
            try recovered.insert(db)
        }
        return recovered.item
    }
}
