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
        let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
        let queue = try DatabaseQueue(path: coordinator.path)
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
        let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
        let queue = try DatabaseQueue(path: coordinator.path)
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
        let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
        let competing = try DatabaseQueue(path: coordinator.path)
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
        let remaining = try competing.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner")
        }
        #expect(remaining == 0)
    }

    @Test("Missing or unknown versioned coordinator schema fails closed")
    func damagedCoordinatorIsNotReset() throws {
        for version in [1, 2, 3] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
            let queue = try DatabaseQueue(path: coordinator.path)
            try queue.write { db in try db.execute(sql: "PRAGMA user_version = \(version)") }
            #expect(throws: StoreProcessOwnership.Failure.self) {
                try StoreProcessOwnership.acquire(in: root, scope: .blob, exclusive: true)
            }
            let query = "SELECT COUNT(*) FROM sqlite_master WHERE name = 'owner'"
            let objects = try queue.read { db in try Int.fetchOne(db, sql: query) }
            #expect(objects == 0)
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

    @Test("A claim from an earlier boot is stale even when its PID looks alive")
    func earlierBootClaimIsReclaimed() throws {
        let bootA = UUID().uuidString
        for (currentBoot, reclaimed) in [(UUID().uuidString, true), (bootA, false), ("", false)] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let heldClaim = try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true,
                identity: .init(pid: 42, token: UUID().uuidString, bootSession: bootA))
            let held = try #require(heldClaim)
            defer { held.release() }
            let contender = try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true, probe: { _ in .live },
                liveness: .init(bootSession: currentBoot, startTime: { _ in nil }))
            #expect((contender != nil) == reclaimed)
            contender?.release()
        }
    }

    @Test("A reused PID is detected by start time only when the process can be inspected")
    func reusedPIDIsReclaimed() throws {
        let boot = UUID().uuidString
        let cases: [(StoreProcessOwnership.ProcessState, Int64?, Bool)] = [
            (.live, 2_000, true),  // same PID, different process
            (.live, 1_000, false),  // the claimant itself
            (.live, nil, false),  // start time withheld
            (.unverifiable, 2_000, false)  // cannot signal it: never inferred
        ]
        for (state, observed, reclaimed) in cases {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let heldClaim = try StoreProcessOwnership.acquire(
                in: root, scope: .generation, exclusive: false,
                identity: .init(
                    pid: 42, token: UUID().uuidString, bootSession: boot, startTime: 1_000))
            let held = try #require(heldClaim)
            defer { held.release() }
            let contender = try StoreProcessOwnership.acquire(
                in: root, scope: .generation, exclusive: true, probe: { _ in state },
                liveness: .init(bootSession: boot, startTime: { _ in observed }))
            #expect((contender != nil) == reclaimed)
            contender?.release()
        }
    }

    @Test("A version-1 ledger migrates in place and keeps its claims")
    func versionOneLedgerMigrates() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
        let queue = try DatabaseQueue(path: coordinator.path)
        try queue.write { db in
            try db.execute(sql: StoreProcessOwnership.ownerSchema)
            try db.execute(
                sql: "INSERT INTO owner VALUES (?, ?, 42, 'generation', 0)",
                arguments: [UUID().uuidString, UUID().uuidString])
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        // The legacy claim has no identity stamp, so only its PID judges it.
        let blocked = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: true, probe: { _ in .live },
            liveness: .init(bootSession: UUID().uuidString, startTime: { _ in 7 }))
        #expect(blocked == nil)
        blocked?.release()
        let (version, identityTables) = try queue.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE name = 'owner_identity'")
            )
        }
        #expect(version == 2 && identityTables == 1)
        let reclaimedClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: true, probe: { _ in .exited })
        let reclaimed = try #require(reclaimedClaim)
        reclaimed.release()
        let leftovers = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM owner_identity")
        }
        #expect(leftovers == 0)
    }

    @Test("Malformed identity stamps are rejected on write and on read")
    func malformedStamp() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreProcessOwnership.acquire(
                in: root, scope: .blob, exclusive: true,
                identity: .init(pid: 42, token: UUID().uuidString, bootSession: "not-a-boot"))
        }
        let heldClaim = try StoreProcessOwnership.acquire(
            in: root, scope: .generation, exclusive: false)
        let held = try #require(heldClaim)
        defer { held.release() }
        let coordinator = root.appendingPathComponent(StoreProcessOwnership.fileName)
        let queue = try DatabaseQueue(path: coordinator.path)
        try queue.write { db in
            try db.execute(sql: "UPDATE owner_identity SET bootSession = 'garbage'")
        }
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreProcessOwnership.acquire(in: root, scope: .blob, exclusive: true)
        }
    }

    @Test("This process stamps its claims with the boot session and its start time")
    func currentIdentityIsStamped() {
        let current = StoreProcessOwnership.Identity.current
        #expect(current.hasValidStamp)
        #expect(UUID(uuidString: current.bootSession) != nil)
        #expect(current.startTime > 0)
        #expect(StoreProcessOwnership.processStartTime(getpid()) == current.startTime)
    }
}
