import CloudKit
import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

private actor PullScript {
    var databaseSteps: [Result<SyncPullDriver.DatabasePage, any Error>]
    var zoneSteps: [Result<SyncPullDriver.ZonePage, any Error>]
    var applyErrors: [CocoaError?]
    private(set) var databaseTokens: [Data?] = []
    private(set) var zoneTokens: [Data?] = []
    private(set) var applied = 0

    init(
        database: [Result<SyncPullDriver.DatabasePage, any Error>],
        zones: [Result<SyncPullDriver.ZonePage, any Error>], applyErrors: [CocoaError?] = []
    ) {
        databaseSteps = database
        zoneSteps = zones
        self.applyErrors = applyErrors
    }

    func database(_ token: Data?) throws -> SyncPullDriver.DatabasePage {
        databaseTokens.append(token)
        return try databaseSteps.removeFirst().get()
    }
    func zone(_ token: Data?) throws -> SyncPullDriver.ZonePage {
        zoneTokens.append(token)
        return try zoneSteps.removeFirst().get()
    }
    func apply() throws {
        applied += 1
        if !applyErrors.isEmpty, let error = applyErrors.removeFirst() { throw error }
    }
    nonisolated var driver: SyncPullDriver {
        .init(
            databasePage: { try await self.database($0) },
            zonePage: { _, token in try await self.zone(token) },
            apply: { _, _ in try await self.apply() }, resetZones: { _ in })
    }
}

private actor SuspendedZoneFetch {
    private var entered = false
    private var observer: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<SyncPullDriver.ZonePage, Never>?
    func fetch() async -> SyncPullDriver.ZonePage {
        entered = true
        observer?.resume()
        observer = nil
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForFetch() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() {
        continuation?.resume(returning: .init(records: [], token: Data([5])))
        continuation = nil
    }
}

private actor SkipCounter {
    private(set) var total = 0
    func add(_ count: Int) { total += count }
}

@Suite("Sync pull — complete-page checkpoint contract")
struct SyncPullDriverTests {
    private let initial = SyncPollTokens(database: Data([1]), zones: ["clips": Data([2])])
    private var database: SyncPullDriver.DatabasePage {
        .init(changedZones: ["clips"], token: Data([3]))
    }
    private var expired: CKError { CKError(.changeTokenExpired) }

    @Test("Multiple database and zone pages advance only after all applies")
    func completeCycle() async throws {
        let script = PullScript(
            database: [
                .success(.init(changedZones: ["clips"], token: Data([3]), moreComing: true)),
                .success(.init(changedZones: [], token: Data([4])))
            ],
            zones: [
                .success(.init(records: [], token: Data([5]), moreComing: true)),
                .success(.init(records: [], token: Data([6])))
            ])
        let result = try await script.driver.pull(from: initial, zones: ["clips"])
        #expect(result == SyncPollTokens(database: Data([4]), zones: ["clips": Data([6])]))
        #expect(await script.databaseTokens == [Data([1]), Data([3])])
        #expect(await script.zoneTokens == [Data([2]), Data([5])])
        #expect(await script.applied == 2)
    }

    @Test("A permanent per-record failure is skipped so the zone checkpoint advances")
    func permanentRecordFailureSkipped() async throws {
        let script = PullScript(
            database: [.success(database)],
            zones: [
                .success(
                    .init(
                        records: [
                            .success(CKRecord(recordType: "SyntheticClip")),
                            .failure(CKError(.unknownItem))
                        ], token: Data([5])))
            ])
        let skipped = SkipCounter()
        var driver = script.driver
        driver.skipped = { await skipped.add($0) }
        let result = try await driver.pull(from: initial, zones: ["clips"])
        #expect(result.zones["clips"] == Data([5]))
        #expect(await script.applied == 1)
        #expect(await skipped.total == 1)
    }

    @Test("A transient per-record failure rejects its page before any apply")
    func partialRecordFailure() async {
        let script = PullScript(
            database: [.success(database)],
            zones: [
                .success(
                    .init(
                        records: [
                            .success(CKRecord(recordType: "SyntheticClip")),
                            .failure(CKError(.networkFailure))
                        ], token: Data([5])))
            ])
        await #expect(throws: CKError.self) {
            try await script.driver.pull(from: initial, zones: ["clips"])
        }
        #expect(await script.applied == 0)
    }

    @Test(
        "A second-page store failure returns no new checkpoint; retry starts at the durable token")
    func partialApplyAndReplay() async throws {
        let first = SyncPullDriver.ZonePage(records: [], token: Data([5]), moreComing: true)
        let last = SyncPullDriver.ZonePage(records: [], token: Data([6]))
        let script = PullScript(
            database: [.success(database), .success(database)],
            zones: [.success(first), .success(last), .success(first), .success(last)],
            applyErrors: [nil, CocoaError(.fileWriteOutOfSpace)])
        await #expect(throws: CocoaError.self) {
            try await script.driver.pull(from: initial, zones: ["clips"])
        }
        let result = try await script.driver.pull(from: initial, zones: ["clips"])
        #expect(result.zones["clips"] == Data([6]))
        #expect(await script.zoneTokens == [Data([2]), Data([5]), Data([2]), Data([5])])
    }

    @Test("Database expiration performs one full rescan before reporting success")
    func expiredDatabase() async throws {
        let script = PullScript(
            database: [.failure(expired), .success(database)],
            zones: [.success(.init(records: [], token: Data([5])))])
        _ = try await script.driver.pull(from: initial, zones: ["clips"])
        #expect(await script.databaseTokens == [Data([1]), nil])
        #expect(await script.zoneTokens == [nil])
    }

    @Test("Zone expiration resets that zone exactly once")
    func expiredZone() async throws {
        let script = PullScript(
            database: [.success(database)],
            zones: [
                .failure(expired), .success(.init(records: [], token: Data([5])))
            ])
        _ = try await script.driver.pull(from: initial, zones: ["clips"])
        #expect(await script.zoneTokens == [Data([2]), nil])
        let broken = PullScript(
            database: [.success(database)], zones: [.failure(expired), .failure(expired)])
        await #expect(throws: CKError.self) {
            try await broken.driver.pull(from: initial, zones: ["clips"])
        }
        #expect(await broken.zoneTokens.count == 2)
    }

    @Test("Missing zone clears its checkpoint but network failure does not become empty")
    func missingZone() async throws {
        let missing = PullScript(
            database: [.success(database)], zones: [.failure(CKError(.zoneNotFound))])
        #expect(
            try await missing.driver.pull(from: initial, zones: ["clips"]).zones["clips"] == nil)
        let offline = PullScript(
            database: [.success(database)], zones: [.failure(CKError(.networkUnavailable))])
        await #expect(throws: CKError.self) {
            try await offline.driver.pull(from: initial, zones: ["clips"])
        }
    }

    @Test("Non-advancing page tokens fail instead of busy looping")
    func repeatedToken() async {
        let script = PullScript(
            database: [.success(.init(changedZones: [], token: Data([1]), moreComing: true))],
            zones: [])
        await #expect(throws: SyncReceiveFailure.nonAdvancingPage) {
            try await script.driver.pull(from: initial, zones: ["clips"])
        }
        #expect(await script.databaseTokens.count == 1)
    }

    @Test("Cancelled pulls never fetch or return a checkpoint")
    func cancelled() async {
        let script = PullScript(database: [], zones: [])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await script.driver.pull(from: initial, zones: ["clips"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await script.databaseTokens.isEmpty)
    }

    @Test("Cancellation while fetching discards the late page before applying")
    func cancelledSuspendedPage() async {
        let gate = SuspendedZoneFetch()
        let driver = SyncPullDriver(
            databasePage: { _ in database },
            zonePage: { _, _ in await gate.fetch() },
            apply: { _, _ in Issue.record("late cancelled page must not apply") },
            resetZones: { _ in Issue.record("late cancelled page must not reset identities") })
        let task = Task { try await driver.pull(from: initial, zones: ["clips"]) }
        await gate.waitForFetch()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Database zone deletions clear only the deleted zone checkpoint")
    func deletedZone() async throws {
        let script = PullScript(
            database: [
                .success(.init(changedZones: [], deletedZones: ["clips"], token: Data([3])))
            ], zones: [])
        let result = try await script.driver.pull(from: initial, zones: ["clips"])
        #expect(result.zones.isEmpty)
        #expect(await script.zoneTokens.isEmpty)
    }

    @Test("Checkpoint persistence failure is observable and leaves old durable bytes intact")
    func failedCheckpointSave() throws {
        let bytes = try PropertyListEncoder().encode(initial)
        let store = SyncStateStore(
            load: { bytes }, save: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        let candidate = SyncPollTokens(database: Data([9]), zones: ["clips": Data([10])])
        #expect(throws: CocoaError.self) { try candidate.save(to: store) }
        #expect(SyncPollTokens.load(from: store) == initial)
    }
}
