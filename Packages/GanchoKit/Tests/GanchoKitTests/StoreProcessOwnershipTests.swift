import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Durable ownership — suspension, identity, and crash boundaries")
struct StoreProcessOwnershipTests {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("Idle ownership has no transaction lock and its coordinator is WAL")
    func idleClaimIsLogical() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let heldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: false)
        let held = try #require(heldClaim)
        defer { held.release() }
        let queue = try DatabaseQueue(path: root.appendingPathComponent(
            StoreProcessOwnership.fileName).path)
        let mode = try queue.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
        // A completely independent writer can commit while the logical pin is
        // retained. A retained SQLite write transaction would prevent it;
        // removal of the independent flock protocol is a source-level check.
        try queue.write { db in try db.execute(sql: "CREATE TABLE independent (id INTEGER)") }
        let blocked = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: true)
        #expect(blocked == nil)
        blocked?.release()
    }

    @Test("Recovery excludes blob work and registration until it downgrades")
    func unifiedConflictBoundary() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let heldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: true)
        let held = try #require(heldClaim)
        defer { held.release() }
        let blob = try StoreProcessOwnership.acquire(in: root, scope: .blob, exclusive: true)
        let opener = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: false)
        #expect(blob == nil && opener == nil)
        blob?.release()
        opener?.release()
        try held.downgrade()
        let allowedClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true)
        let allowed = try #require(allowedClaim)
        allowed.release()
    }

    @Test("Suspended, unverifiable, and reused PIDs are retained; only proven exit reclaims")
    func conservativeIdentity() throws {
        for state in [StoreProcessOwnership.ProcessState.live, .unverifiable, .exited] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let heldClaim = try StoreProcessOwnership.acquire(
                in: root, scope: .generation, exclusive: false,
                identity: .init(pid: 42, token: UUID().uuidString), probe: { _ in .live })
            let held = try #require(heldClaim)
            defer { held.release() }
            let contender = try StoreProcessOwnership.acquire(
                in: root, scope: .generation, exclusive: true, probe: { _ in state })
            #expect((contender != nil) == (state == .exited))
            contender?.release()
        }
    }

    @Test("A delayed old release cannot remove the next operation's token")
    func exactReleaseIdentity() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true,
            identity: .init(pid: 42, token: UUID().uuidString))
        let old = try #require(oldClaim)
        let newerClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, probe: { _ in .exited })
        let newer = try #require(newerClaim)
        defer { newer.release() }
        old.release()
        old.release()
        let contender = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, probe: { _ in .live })
        #expect(contender == nil)
        contender?.release()
    }

    @Test("Lifecycle rejects late observers and retries finished-operation releases")
    func lifecycleStateMachine() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lifecycle = StoreOwnershipLifecycle()
        let heldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, lifecycle: lifecycle)
        let held = try #require(heldClaim)
        let queue = try DatabaseQueue(path: root.appendingPathComponent(
            StoreProcessOwnership.fileName).path)
        lifecycle.suspend()
        held.release()
        let retained = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner")
        }
        #expect(retained == 1)
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true, lifecycle: lifecycle)
        }
        lifecycle.resume()
        lifecycle.flushPending()
        let cleared = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner")
        }
        #expect(cleared == 0)
        let nextClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, lifecycle: lifecycle)
        let next = try #require(nextClaim)
        next.release()
    }

    @Test("An interrupted release keeps its token until the next committed metadata write")
    func retryFailedRelease() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lifecycle = StoreOwnershipLifecycle()
        let heldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, lifecycle: lifecycle)
        let held = try #require(heldClaim)
        let competing = try DatabaseQueue(path: root.appendingPathComponent(
            StoreProcessOwnership.fileName).path)
        try competing.writeWithoutTransaction { db in
            try db.execute(sql: "BEGIN IMMEDIATE")
            defer { try? db.execute(sql: "ROLLBACK") }
            held.release()
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner") == 1)
        }
        let nextClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .blob, exclusive: true, lifecycle: lifecycle)
        let next = try #require(nextClaim)
        next.release()
        #expect(try competing.read {
            db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner")
        } == 0)
    }

    @Test("Missing or unknown versioned coordinator schema fails closed")
    func damagedCoordinatorIsNotReset() throws {
        for version in [1, 2] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let queue = try DatabaseQueue(path: root.appendingPathComponent(
                StoreProcessOwnership.fileName).path)
            try queue.write { db in try db.execute(sql: "PRAGMA user_version = \(version)") }
            #expect(throws: StoreProcessOwnership.Failure.self) {
                try StoreProcessOwnership.acquire(in: root, scope: .blob, exclusive: true)
            }
            #expect(try queue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE name = 'owner'")
            } == 0)
        }
    }

    @Test("Invalid process identities never become reclamation candidates")
    func invalidIdentity() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true,
                identity: .init(pid: 0, token: UUID().uuidString))
        }
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true,
                identity: .init(pid: 42, token: "not-a-process-identity"))
        }
    }
}
