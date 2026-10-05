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
        static var current: Self { Self(pid: getpid(), token: processToken) }
    }
    private struct Owner: Decodable, FetchableRecord {
        var token: String
        var processToken: String
        var pid: Int64
        var scope: String
        var exclusive: Int
    }
    private let queue: DatabaseQueue
    private let lifecycle: StoreOwnershipLifecycle
    private let directory: URL
    private let token: String
    private let owner: String
    private let mutex = NSLock()
    private var released = false

    private init(
        queue: DatabaseQueue, directory: URL, token: String, owner: String,
        lifecycle: StoreOwnershipLifecycle
    ) {
        self.queue = queue
        self.lifecycle = lifecycle
        self.directory = directory
        self.token = token
        self.owner = owner
    }

    static func acquire(
        in directory: URL, scope: Scope, exclusive: Bool,
        identity: Identity = .current,
        probe: @Sendable (Int32) -> ProcessState = processState,
        lifecycle: StoreOwnershipLifecycle = .shared
    ) throws -> StoreProcessOwnership? {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let pid = identity.pid
        let owner = identity.token
        guard pid > 0, UUID(uuidString: owner) != nil else { throw Failure.malformedMetadata }
        return try lifecycle.withActive {
            let queue = try makeQueue(in: directory)
            var retained = false
            defer { if !retained { lifecycle.closeOrDefer(queue) } }
            let token = UUID().uuidString
            let acquired = try queue.write { db in
                try prepareSchema(db)
                try lifecycle.drainPending(in: db, directory: directory)
                let rows = try Owner.fetchAll(
                    db, sql: "SELECT token, processToken, pid, scope, exclusive FROM owner")
                for row in rows {
                    let storedPID = row.pid
                    let storedToken = row.token
                    let storedOwner = row.processToken
                    let storedScope = row.scope
                    let storedExclusive = row.exclusive
                    guard storedPID > 0, storedPID <= Int64(Int32.max),
                        UUID(uuidString: storedToken) != nil, UUID(uuidString: storedOwner) != nil,
                        let otherScope = Scope(rawValue: storedScope),
                        storedExclusive == 0 || storedExclusive == 1
                    else { throw Failure.malformedMetadata }
                    if probe(Int32(storedPID)) == .exited {
                        try db.execute(
                            sql: "DELETE FROM owner WHERE token = ?", arguments: [storedToken])
                        continue
                    }
                    // Recovery is exclusive over both scopes. Blob work also
                    // checks recovery, including injected stores without a pin.
                    let recovering = scope == .generation && exclusive
                    let otherRecovering = otherScope == .generation && storedExclusive == 1
                    if recovering || otherRecovering
                        || (scope == .blob && otherScope == .blob)
                    {
                        return false
                    }
                }
                try db.execute(
                    sql: "INSERT INTO owner VALUES (?, ?, ?, ?, ?)",
                    arguments: [token, owner, pid, scope.rawValue, exclusive ? 1 : 0])
                return true
            }
            lifecycle.didCommitPending(in: directory)
            guard acquired else { return nil }
            retained = true
            return StoreProcessOwnership(
                queue: queue, directory: directory, token: token, owner: owner,
                lifecycle: lifecycle)
        }
    }

    func downgrade() throws {
        mutex.lock()
        defer { mutex.unlock() }
        guard !released else { throw Failure.malformedMetadata }
        try lifecycle.withActive {
            try queue.write { db in
                try db.execute(
                    sql: "UPDATE owner SET exclusive = 0 WHERE token = ? AND processToken = ?",
                    arguments: [token, owner])
                guard db.changesCount == 1 else { throw Failure.malformedMetadata }
            }
        }
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
        // absence; sandbox/permission errors and PID reuse keep the claim.
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

    private static func prepareSchema(_ db: Database) throws {
        let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        guard version == 0 || version == 1 else { throw Failure.malformedMetadata }
        let schema = """
            CREATE TABLE owner (
                token TEXT PRIMARY KEY NOT NULL,
                processToken TEXT NOT NULL,
                pid INTEGER NOT NULL CHECK (pid > 0 AND pid <= 2147483647),
                scope TEXT NOT NULL CHECK (scope IN ('generation', 'blob')),
                exclusive INTEGER NOT NULL CHECK (exclusive IN (0, 1))
            )
            """
        let existing = try String.fetchOne(
            db, sql: "SELECT sql FROM sqlite_master WHERE name = 'owner' AND type = 'table'")
        if version == 0 {
            let query = "SELECT COUNT(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
            let objects = try Int.fetchOne(db, sql: query) ?? 0
            guard existing == nil, objects == 0 else { throw Failure.malformedMetadata }
            try db.execute(sql: schema)
            try db.execute(sql: "PRAGMA user_version = 1")
        } else {
            // Never recreate a missing/versioned ledger or accept a different
            // schema: that could erase knowledge of an active logical owner.
            guard let existing,
                existing.split(whereSeparator: \.isWhitespace)
                    == schema.split(whereSeparator: \.isWhitespace)
            else { throw Failure.malformedMetadata }
        }
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
