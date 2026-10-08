import Darwin
import Foundation
import GRDB

/// Durable logical ownership, not a kernel lock. Transactions contain only
/// metadata; no transaction/file lock survives a return or an async suspension.
/// The sidecar holds no key, clip content, hash or path from a clipboard item.
final class StoreProcessOwnership: @unchecked Sendable {
    enum Scope: String, Sendable, Equatable { case generation, blob }
    enum ProcessState: Sendable, Equatable { case live, exited, unverifiable }
    enum Failure: Error { case busy, suspended, malformedMetadata }

    static let fileName = ".store-ownership.sqlite"
    static let processToken = UUID().uuidString
    struct Identity: Sendable {
        var pid: Int32
        var token: String
        /// `kern.bootsessionuuid` when the claim was made; empty when unknown.
        var bootSession = ""
        /// Process start in microseconds since 1970; 0 when unknown.
        var startTime: Int64 = 0
        static var current: Self {
            Self(
                pid: getpid(), token: processToken, bootSession: currentBootSession,
                startTime: currentStartTime)
        }
    }
    /// A validated ledger row.
    private struct OwnerClaim {
        var stamp: Identity
        var scope: Scope
        var exclusive: Bool
    }
    private struct Owner: Decodable, FetchableRecord {
        var token: String
        var processToken: String
        var pid: Int64
        var scope: String
        var exclusive: Int
        /// Nil for a claim migrated from the version-1 ledger.
        var bootSession: String?
        var startTime: Int64?

        /// Any malformed field fails the whole ledger closed.
        func validated() throws -> OwnerClaim {
            guard pid > 0, pid <= Int64(Int32.max), UUID(uuidString: token) != nil,
                UUID(uuidString: processToken) != nil,
                let parsedScope = Scope(rawValue: self.scope),
                exclusive == 0 || exclusive == 1
            else { throw Failure.malformedMetadata }
            let stamp = Identity(
                pid: Int32(pid), token: processToken, bootSession: bootSession ?? "",
                startTime: startTime ?? 0)
            guard stamp.hasValidStamp else { throw Failure.malformedMetadata }
            return OwnerClaim(stamp: stamp, scope: parsedScope, exclusive: exclusive == 1)
        }
    }
    private let queue: DatabaseQueue
    private let lifecycle: StoreOwnershipLifecycle
    private let directory: URL
    private let token: String
    private let owner: String
    private let mutex = NSLock()
    private var released = false
    private var exclusive: Bool

    private init(
        queue: DatabaseQueue, directory: URL, token: String, owner: String,
        exclusive: Bool, lifecycle: StoreOwnershipLifecycle
    ) {
        self.queue = queue
        self.lifecycle = lifecycle
        self.directory = directory
        self.token = token
        self.owner = owner
        self.exclusive = exclusive
    }

    static func acquire(
        in directory: URL, scope: Scope, exclusive: Bool,
        identity: Identity = .current,
        probe: @Sendable (Int32) -> ProcessState = processState,
        liveness: Liveness = .system,
        lifecycle: StoreOwnershipLifecycle = .shared
    ) throws -> StoreProcessOwnership? {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let pid = identity.pid
        let owner = identity.token
        guard pid > 0, UUID(uuidString: owner) != nil, identity.hasValidStamp
        else { throw Failure.malformedMetadata }
        return try lifecycle.withActive {
            let queue = try makeQueue(in: directory)
            var retained = false
            defer { if !retained { lifecycle.closeOrDefer(queue) } }
            let token = UUID().uuidString
            let acquired = try queue.write { db in
                try prepareSchema(db)
                try lifecycle.drainPending(in: db, directory: directory)
                let rows = try Owner.fetchAll(db, sql: ownerQuery)
                for row in rows {
                    let other = try row.validated()
                    if isStale(other.stamp, probe: probe, liveness: liveness) {
                        try db.execute(
                            sql: "DELETE FROM owner WHERE token = ?", arguments: [row.token])
                        continue
                    }
                    // Recovery is exclusive over both scopes. Blob work also
                    // checks recovery, including injected stores without a pin.
                    let recovering = scope == .generation && exclusive
                    let otherRecovering = other.scope == .generation && other.exclusive
                    if recovering || otherRecovering
                        || (scope == .blob && other.scope == .blob)
                    {
                        return false
                    }
                }
                try removeOrphanIdentities(in: db)
                try db.execute(
                    sql: "INSERT INTO owner VALUES (?, ?, ?, ?, ?)",
                    arguments: [token, owner, pid, scope.rawValue, exclusive ? 1 : 0])
                try db.execute(
                    sql: "INSERT INTO owner_identity VALUES (?, ?, ?)",
                    arguments: [token, identity.bootSession, identity.startTime])
                return true
            }
            lifecycle.didCommitPending(in: directory)
            guard acquired else { return nil }
            retained = true
            return StoreProcessOwnership(
                queue: queue, directory: directory, token: token, owner: owner,
                exclusive: exclusive, lifecycle: lifecycle)
        }
    }

    func downgrade() throws {
        mutex.lock()
        defer { mutex.unlock() }
        guard !released else { throw Failure.malformedMetadata }
        // A shared claim has nothing to downgrade. Skipping the write keeps a
        // steady-state open from failing on a busy or suspended ledger.
        guard exclusive else { return }
        try lifecycle.withActive {
            try queue.write { db in
                try db.execute(
                    sql: "UPDATE owner SET exclusive = 0 WHERE token = ? AND processToken = ?",
                    arguments: [token, owner])
                guard db.changesCount == 1 else { throw Failure.malformedMetadata }
            }
        }
        exclusive = false
    }

    func release() {
        mutex.lock()
        defer { mutex.unlock() }
        guard !released else { return }
        released = true
        // Only a finished operation enters pending release. A suspended or
        // interrupted metadata write preserves the claim until a safe retry.
        lifecycle.release(
            token: token, owner: owner, in: directory, queue: queue)
    }

    deinit { release() }

    static func processState(_ pid: Int32) -> ProcessState {
        guard pid > 0 else { return .unverifiable }
        // Signal zero sends no signal. ESRCH is the only documented proof of
        // absence; sandbox/permission errors keep the claim. PID reuse is
        // judged separately by the boot session and process start time.
        if kill(pid, 0) == 0 { return .live }
        return errno == ESRCH ? .exited : .unverifiable
    }

    fileprivate static func makeQueue(in directory: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.busyMode = .timeout(0.1)
        configuration.journalMode = .wal
        #if os(iOS)
            configuration.automaticMemoryManagement = false
            configuration.observesSuspensionNotifications = true
        #endif
        let path = directory.appendingPathComponent(fileName).path
        return try DatabaseQueue(path: path, configuration: configuration)
    }
}

/// Serializes only short coordinator transactions against the iOS suspension
/// boundary. suspend() cannot return with such a transaction still in flight;
/// opening a new observer after suspension is rejected too. Logical ownership
/// remains durable while the process is suspended, without holding a file lock.
final class StoreOwnershipLifecycle: @unchecked Sendable {
    static let shared = StoreOwnershipLifecycle()
    private struct Release: Hashable {
        var token: String
        var owner: String
    }
    private let mutex = NSLock()
    private var suspended = false
    private var pending: [URL: Set<Release>] = [:]
    private var pendingQueues: [URL: [DatabaseQueue]] = [:]
    private var deferredClose: [DatabaseQueue] = []

    func withActive<T>(_ body: () throws -> T) throws -> T {
        mutex.lock()
        defer { mutex.unlock() }
        guard !suspended else { throw StoreProcessOwnership.Failure.suspended }
        let closing = deferredClose
        deferredClose = []
        for queue in closing { closeOrDefer(queue) }
        return try body()
    }

    func suspend() {
        mutex.lock()
        suspended = true
        mutex.unlock()
    }

    func resume() {
        mutex.lock()
        suspended = false
        mutex.unlock()
    }

    fileprivate func drainPending(in db: Database, directory: URL) throws {
        // Caller already holds the lifecycle fence and a writer transaction.
        // The fence prevents concurrent additions. Acknowledge this exact
        // pending set only after the writer call has successfully committed.
        for release in pending[directory] ?? [] {
            try db.execute(
                sql: "DELETE FROM owner WHERE token = ? AND processToken = ?",
                arguments: [release.token, release.owner])
        }
        try StoreProcessOwnership.removeOrphanIdentities(in: db)
    }

    fileprivate func didCommitPending(in directory: URL) {
        pending.removeValue(forKey: directory)
        for queue in pendingQueues.removeValue(forKey: directory) ?? [] {
            closeOrDefer(queue)
        }
    }

    fileprivate func closeOrDefer(_ queue: DatabaseQueue) {
        // The caller holds the active fence. WAL checkpoint-on-close must
        // finish here too, not in a later property deinitialization.
        do { try queue.close() } catch { deferredClose.append(queue) }
    }

    fileprivate func release(
        token: String, owner: String, in directory: URL, queue: DatabaseQueue
    ) {
        mutex.lock()
        defer { mutex.unlock() }
        pending[directory, default: []].insert(Release(token: token, owner: owner))
        pendingQueues[directory, default: []].append(queue)
        guard !suspended else { return }
        flush(in: directory, queue: queue)
    }

    private func flush(in directory: URL, queue: DatabaseQueue) {
        do {
            try queue.write { db in try drainPending(in: db, directory: directory) }
            didCommitPending(in: directory)
        } catch {
            // No bytes are deleted and the exact known-finished claim is retried.
        }
    }

    func flushPending() {
        mutex.lock()
        defer { mutex.unlock() }
        guard !suspended else { return }
        let closing = deferredClose
        deferredClose = []
        for queue in closing { closeOrDefer(queue) }
        for directory in Array(pending.keys).prefix(128) {
            if let queue = try? StoreProcessOwnership.makeQueue(in: directory) {
                flush(in: directory, queue: queue)
                closeOrDefer(queue)
            }
        }
    }
}
