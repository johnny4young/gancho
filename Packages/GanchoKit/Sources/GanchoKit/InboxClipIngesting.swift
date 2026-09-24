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

    /// The original row, if it still exists, without recency or dedupe writes.
    /// A deleted clip stays deleted on replay.
    func itemForInboxDelivery(id: String) async throws -> ClipItem?

    /// Drops receipts committed before `date`; returns how many were removed.
    @discardableResult
    func pruneInboxReceipts(committedBefore date: Date) async throws -> Int
}

public enum InboxReceiptRetention {
    /// Well past the inbox's own retry window, so only receipts whose file
    /// has long been acknowledged or discarded are removed.
    public static let lifetime: TimeInterval = 90 * 24 * 60 * 60
}
