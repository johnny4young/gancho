import Foundation

/// A receipt is local-only and survives deletion of its clip. Replaying an old
/// queue file must never resurrect user-deleted content or bump recency again.
public enum InboxInsertResult: Sendable, Equatable {
    case inserted(ClipItem)
    case alreadyCommitted
}

public protocol InboxClipIngesting: Sendable {
    /// Commits the deduplicated row and receipt in ONE database transaction.
    func insertInboxDelivery(
        id: String, item: ClipItem, content: ClipContent?
    ) async throws -> InboxInsertResult
}
