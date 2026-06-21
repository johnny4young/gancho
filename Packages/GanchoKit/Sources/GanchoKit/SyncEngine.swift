import Foundation

/// What sync is doing right now, surfaced to the UI — state and counts only,
/// never clip content. `idle` means sync is off (free tier or signed out of
/// iCloud); `paused`/`failed` carry a short, user-readable cause.
public enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case upToDate(at: Date?)
    case pending(Int)
    case paused(SyncInterruption)
    case failed(SyncInterruption)
}

/// Why sync paused or failed — structured so the UI localizes the cause and a
/// suggested action. No content.
public enum SyncInterruption: String, Sendable, Equatable, Codable, CaseIterable {
    case iCloudFull
    case notSignedIn
    case offline
    case unknown
}

/// The sync boundary: the core never talks to CloudKit
/// directly. Production implementation is CKSyncEngine over the private
/// database with encrypted fields (validated by the sync spike). Keeping
/// this protocol thin is what makes a future LAN-P2P or self-hosted backend
/// a new implementation instead of a rewrite.
public protocol SyncEngine: Sendable {
    func start() async throws
    func stop() async
    /// Local changes the engine should propagate.
    func enqueue(_ items: [ClipItem]) async
    /// Tombstones for deletions (CloudKit-compatible delete semantics).
    func enqueueDeletion(ids: [UUID]) async
    /// Board metadata to propagate (name/glyph). Membership rides the clips.
    func enqueue(boards: [Pinboard]) async
}

/// Free tier / tests: sync disabled.
public struct NoopSyncEngine: SyncEngine {
    public init() {}
    public func start() async throws {}
    public func stop() async {}
    public func enqueue(_ items: [ClipItem]) async {}
    public func enqueueDeletion(ids: [UUID]) async {}
    public func enqueue(boards: [Pinboard]) async {}
}
