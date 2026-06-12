import Foundation

/// The sync boundary (backlog E3.1/E12.3): the core never talks to CloudKit
/// directly. Production implementation is CKSyncEngine over the private
/// database with encrypted fields (E4.1, validated by spike S0.2). Keeping
/// this protocol thin is what makes a future LAN-P2P or self-hosted backend
/// a new implementation instead of a rewrite.
public protocol SyncEngine: Sendable {
    func start() async throws
    func stop() async
    /// Local changes the engine should propagate.
    func enqueue(_ items: [ClipItem]) async
    /// Tombstones for deletions (CloudKit-compatible delete semantics).
    func enqueueDeletion(ids: [UUID]) async
}

/// Free tier / tests: sync disabled.
public struct NoopSyncEngine: SyncEngine {
    public init() {}
    public func start() async throws {}
    public func stop() async {}
    public func enqueue(_ items: [ClipItem]) async {}
    public func enqueueDeletion(ids: [UUID]) async {}
}
