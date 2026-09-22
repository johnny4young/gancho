import CloudKit
import Foundation
import GRDB
import Synchronization
import Testing

@_spi(GanchoInternal) @testable import GanchoKit
@testable import GanchoSync

@Suite("Sync outbound durable outcomes")
struct SyncOutboundWorkTests {
    private struct Fixture {
        let writer: DatabaseQueue
        let store: GRDBClipboardStore
        let work: SyncOutboundWork
        let directory: URL

        init() throws {
            writer = try DatabaseQueue()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            store = GRDBClipboardStore(writer: writer, blobs: BlobStore(directory: directory))
            try store.migrate()
            work = SyncOutboundWork(
                store: store,
                clipZone: .init(
                    zoneName: ClipRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName),
                boardZone: .init(
                    zoneName: BoardRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName),
                maxAssetBytes: ClipRecordMapper.defaultMaxAssetBytes)
        }

        func record(_ item: ClipItem) throws -> CKRecord {
            try #require(
                ClipRecordMapper.record(
                    for: item, content: .text("synthetic"), systemFields: nil, zoneID: work.clipZone
                ))
        }

        func insert() async throws -> ClipItem {
            let item = ClipItem(
                updatedAt: Date(timeIntervalSince1970: 1000),
                preview: "synthetic", contentHash: UUID().uuidString)
            try await store.insert(item, content: .text("synthetic"))
            return item
        }

        func clean() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test("Failed reads cannot become empty pending work, zero count or missing records")
    func failedReads() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let id = try fixture.record(item).recordID
        try await fixture.writer.write { db in try db.execute(sql: "DROP TABLE sync_tombstone") }
        await #expect(throws: (any Error).self) { try await fixture.work.pending() }
        await #expect(throws: (any Error).self) { try await fixture.work.pendingCount() }
        try await fixture.writer.write { db in try db.execute(sql: "DROP TABLE clip") }
        await #expect(throws: (any Error).self) { try await fixture.work.prepare([id]) }
    }

    @Test("Ack failure retains durable dirty row; a later ack succeeds")
    func ackFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let record = try fixture.record(item)
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_ack BEFORE UPDATE OF syncSystemFields ON clip
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        await #expect(throws: (any Error).self) { try await fixture.work.acknowledge(record) }
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
        #expect(try await fixture.store.systemFields(for: item.id) == nil)
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_ack") }
        try await fixture.work.acknowledge(record)
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
    }

    @Test("An old upload ack stores its change tag without clearing a newer local edit")
    func lateClipAck() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let record = try fixture.record(item)
        try await fixture.store.updateTitle(id: item.id, title: "newer synthetic title")
        try await fixture.work.acknowledge(record)
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
        #expect(try await fixture.store.systemFields(for: item.id) != nil)
        let newest = try #require(try await fixture.store.pendingUpload(id: item.id)?.item)
        try await fixture.work.acknowledge(fixture.record(newest))
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
    }

    @Test("A pre-deletion clip ack cannot clear a removed board membership")
    func lateClipAckAfterBoardDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let board = try await fixture.store.createPinboard(name: "synthetic board")
        try await fixture.store.assign(clipID: item.id, toBoard: board.id)
        let recordID = try fixture.record(item).recordID
        let inFlight = try #require(try await fixture.work.prepare([recordID])[recordID])
        let uploadedAt = try #require(inFlight["updatedAt"] as? Date)
        #expect(ClipRecordMapper.boardIDs(from: inFlight) == [board.id])

        // The delete happens after preparation but can share its timestamp.
        try await fixture.store.deletePinboardForSync(id: board.id, now: uploadedAt)
        try await fixture.work.acknowledge(inFlight)

        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
        let newest = try #require(try await fixture.store.pendingUpload(id: item.id)?.item)
        #expect(newest.updatedAt > uploadedAt)
        let replacement = try #require(try await fixture.work.prepare([recordID])[recordID])
        #expect(ClipRecordMapper.boardIDs(from: replacement).isEmpty)
        try await fixture.work.acknowledge(replacement)
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
    }

    @Test("An old board ack preserves the renamed board as pending")
    func lateBoardAck() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let board = Pinboard(name: "synthetic", createdAt: Date(timeIntervalSince1970: 1000))
        try await fixture.store.applyRemoteBoardUpsert(board, systemFields: Data())
        let record = try #require(
            BoardRecordMapper.record(
                for: board, systemFields: nil, zoneID: fixture.work.boardZone))
        try await fixture.writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET name = 'newer', needsUpload = 1 WHERE id = ?",
                arguments: [board.id.uuidString])
        }
        try await fixture.work.acknowledge(record)
        #expect(try await fixture.store.pendingBoardUploads().map(\.id).contains(board.id))
        let newest = try #require(
            try await fixture.store.pendingBoardUploads().first { $0.id == board.id })
        let newestRecord = try #require(
            BoardRecordMapper.record(
                for: newest, systemFields: nil, zoneID: fixture.work.boardZone))
        try await fixture.work.acknowledge(newestRecord)
        #expect(try await !fixture.store.pendingBoardUploads().map(\.id).contains(board.id))
    }

    @Test("Failed deletion ack keeps tombstone across store reconstruction")
    func tombstoneFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.deleteForSync(id: item.id)
        let id = try fixture.record(item).recordID
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_delete BEFORE DELETE ON sync_tombstone
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        await #expect(throws: (any Error).self) { try await fixture.work.acknowledgeDeletion(id) }
        let reopened = GRDBClipboardStore(
            writer: fixture.writer, blobs: BlobStore(directory: fixture.directory))
        #expect(try await reopened.pendingDeletionRecordIDs() == [item.id.uuidString])
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_delete") }
        try await fixture.work.acknowledgeDeletion(id)
        #expect(try await reopened.pendingDeletionRecordIDs().isEmpty)
    }

    @Test("Conflict store failure throws, unlike a verified local or server win")
    func conflicts() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let record = try fixture.record(item)
        try await fixture.store.updateTitle(id: item.id, title: "newer")
        #expect(try await fixture.work.resolveConflict(record))
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_conflict BEFORE UPDATE ON clip
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        await #expect(throws: (any Error).self) { try await fixture.work.resolveConflict(record) }
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_conflict") }
        record["updatedAt"] = Date().addingTimeInterval(60)
        #expect(try await !fixture.work.resolveConflict(record))
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
    }

    @Test("Corrupt local system fields fail preparation without dropping the durable row")
    func corruptFields() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        try await fixture.store.markNeedsUpload(id: item.id)
        let id = try fixture.record(item).recordID
        await #expect(throws: (any Error).self) { try await fixture.work.prepare([id]) }
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
    }

    @Test("Adapter cannot report up-to-date after a local read failure")
    func truthfulStatus() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let statuses = Mutex<[SyncStatus]>([])
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }),
            onStatus: { status in statuses.withLock { $0.append(status) } })
        try await fixture.writer.write { db in try db.execute(sql: "DROP TABLE sync_tombstone") }
        await adapter.emitCurrentStatus()
        #expect(statuses.withLock { $0 } == [.failed(.unknown)])
    }
    @Test("Failed durable intent is not scheduled and remains visible until persisted")
    func intentFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        let statuses = Mutex<[SyncStatus]>([])
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }),
            onStatus: { status in statuses.withLock { $0.append(status) } })
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_intent BEFORE UPDATE OF needsUpload ON clip
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        // Failure returns before constructing CKSyncEngine: no account/network.
        await adapter.enqueue([item])
        await adapter.emitCurrentStatus()
        #expect(statuses.withLock { $0.last } == .failed(.unknown))
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_intent") }
        try await adapter.retryUploadIntents()
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
        await adapter.emitCurrentStatus()
        #expect(statuses.withLock { $0.last } == .pending(try await fixture.work.pendingCount()))
    }

    @Test("Identity reset journal survives a partial write and resumes after restart")
    func resetReplay() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        let bytes = Mutex<Data?>(nil)
        let journal = SyncStateStore(
            load: { bytes.withLock { $0 } },
            save: { data in bytes.withLock { $0 = data } })
        func adapter() -> CKSyncEngineAdapter {
            CKSyncEngineAdapter(
                store: fixture.store, containerIdentifier: "iCloud.test.gancho",
                stateStore: .init(load: { nil }, save: { _ in }), pollStateStore: journal)
        }
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_reset BEFORE UPDATE OF syncSystemFields ON pinboard
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        let zones: Set<String> = [fixture.work.clipZone.zoneName, fixture.work.boardZone.zoneName]
        await #expect(throws: (any Error).self) {
            try await adapter().beginIdentityReset(zones: zones)
        }
        #expect(SyncPollTokens.load(from: journal).identityResetZones == zones)
        #expect(try await fixture.store.systemFields(for: item.id) == nil)
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_reset") }
        try await adapter().completeIdentityReset()
        #expect(SyncPollTokens.load(from: journal).identityResetZones == nil)
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
    }

    @Test("A reset journal write failure prevents identity mutation")
    func resetJournalFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }),
            pollStateStore: .init(
                load: { nil }, save: { _ in throw SyncOutboundFailure.localWrite }))
        await #expect(throws: (any Error).self) {
            try await adapter.beginIdentityReset(zones: [fixture.work.clipZone.zoneName])
        }
        #expect(try await fixture.store.systemFields(for: item.id) == Data([1]))
        #expect(try await fixture.store.pendingUploadIDs().isEmpty)
    }

    @Test("Preparation distinguishes a confirmed missing row from a failed read")
    func preparationControls() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        let recordID = try fixture.record(item).recordID
        let records = try await fixture.work.prepare([recordID])
        #expect(records[recordID]?.encryptedValues["contentText"] as? String == "synthetic")
        try await fixture.store.deleteForSync(id: item.id)
        #expect(try await fixture.work.prepare([recordID]).isEmpty)
        #expect(try await fixture.work.pending().clipDeletionRecordNames == [item.id.uuidString])
    }

    @Test("Board acknowledgement and conflict write errors remain errors")
    func boardWriteFailures() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let board = Pinboard(name: "synthetic", createdAt: Date(timeIntervalSince1970: 1000))
        try await fixture.store.applyRemoteBoardUpsert(board, systemFields: Data())
        try await fixture.store.markBoardNeedsUpload(id: board.id)
        let record = try #require(
            BoardRecordMapper.record(
                for: board, systemFields: nil, zoneID: fixture.work.boardZone))
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_board BEFORE UPDATE ON pinboard
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        await #expect(throws: (any Error).self) { try await fixture.work.acknowledge(record) }
        await #expect(throws: (any Error).self) { try await fixture.work.resolveConflict(record) }
        #expect(try await fixture.store.pendingBoardUploads().map(\.id).contains(board.id))
        try await fixture.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_board") }
        #expect(try await !fixture.work.resolveConflict(record))
        #expect(try await !fixture.store.pendingBoardUploads().map(\.id).contains(board.id))
    }

    @Test("A persisted incomplete reset cannot report a resting success state")
    func resetStatus() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        var tokens = SyncPollTokens()
        tokens.identityResetZones = [fixture.work.clipZone.zoneName]
        let data = try PropertyListEncoder().encode(tokens)
        let statuses = Mutex<[SyncStatus]>([])
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }),
            onStatus: { status in statuses.withLock { $0.append(status) } },
            pollStateStore: .init(load: { data }, save: { _ in }))
        await adapter.emitCurrentStatus()
        #expect(statuses.withLock { $0 } == [.syncing])
    }

    @Test(
        "Polling deleted or missing zones re-flags local rows without a push callback",
        arguments: [false, true])
    func polledZoneReset(missing: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        let zone = fixture.work.clipZone.zoneName
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }))
        let driver = SyncPullDriver(
            databasePage: { _ in
                .init(
                    changedZones: missing ? [zone] : [],
                    deletedZones: missing ? [] : [zone], token: Data([3]))
            },
            zonePage: { _, _ in throw CKError(.zoneNotFound) },
            apply: { _, _ in Issue.record("a missing zone has no records to apply") },
            resetZones: { zones in
                try await adapter.beginIdentityReset(zones: zones, interruptReceive: false)
            })
        let checkpoint = SyncPollTokens(database: Data([1]), zones: [zone: Data([2])])
        let next = try await driver.pull(from: checkpoint, zones: [zone])
        #expect(next.database == Data([3]))
        #expect(next.zones[zone] == nil)
        #expect(try await fixture.store.systemFields(for: item.id) == nil)
        #expect(try await fixture.store.pendingUploadIDs() == [item.id])
    }

    @Test("A polled reset write failure cannot acknowledge the new database checkpoint")
    func polledResetFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let item = try await fixture.insert()
        try await fixture.store.markUploaded(id: item.id, systemFields: Data([1]))
        let zone = fixture.work.clipZone.zoneName
        let bytes = Mutex<Data?>(nil)
        let journal = SyncStateStore(
            load: { bytes.withLock { $0 } },
            save: { data in bytes.withLock { $0 = data } })
        let adapter = CKSyncEngineAdapter(
            store: fixture.store, containerIdentifier: "iCloud.test.gancho",
            stateStore: .init(load: { nil }, save: { _ in }), pollStateStore: journal)
        try await fixture.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_polled_reset BEFORE UPDATE OF syncSystemFields ON clip
                    BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                    """)
        }
        let driver = SyncPullDriver(
            databasePage: { _ in .init(changedZones: [], deletedZones: [zone], token: Data([3])) },
            zonePage: { _, _ in .init(records: [], token: Data([4])) },
            apply: { _, _ in },
            resetZones: { zones in
                try await adapter.beginIdentityReset(zones: zones, interruptReceive: false)
            })
        await #expect(throws: (any Error).self) {
            try await driver.pull(from: .init(database: Data([1])), zones: [zone])
        }
        #expect(SyncPollTokens.load(from: journal).database != Data([3]))
        #expect(SyncPollTokens.load(from: journal).identityResetZones == [zone])
        #expect(try await fixture.store.systemFields(for: item.id) == Data([1]))
    }

    @Test("Polling ignores identity resets for zones the adapter does not own")
    func unrelatedZoneDeletion() async throws {
        let driver = SyncPullDriver(
            databasePage: { _ in
                .init(changedZones: [], deletedZones: ["unrelated"], token: Data([3]))
            },
            zonePage: { _, _ in .init(records: [], token: Data([4])) },
            apply: { _, _ in },
            resetZones: { _ in Issue.record("unowned zone must not reset local data") })
        let next = try await driver.pull(from: .init(), zones: ["clips"])
        #expect(next.database == Data([3]))
    }

}
