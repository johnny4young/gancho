import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Drives the sync enablement state machine deterministically, with a fake
/// engine injected through the controller's `makeEngine` seam so no test ever
/// touches CloudKit. The controller only ever hands the store to `makeEngine`
/// (it never calls a store method itself), so the fake store is a trivial
/// conformer; the real behavior under test is the enable/disable transitions,
/// the engine swap, the raw idle assignment, and the status routing.
@Suite("Sync controller — engine lifecycle")
@MainActor
struct SyncControllerTests {
    @Test("A disabling tier leaves sync off and the engine unstarted")
    func disabledTierStaysOff() async {
        let fake = FakeSyncEngine()
        // Probes both say "sync is possible"; only the free tier blocks it — so
        // this proves the tier gate, not a missing account.
        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: Self.tempURL(),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            makeEngine: { _, _, _, _, _, _, _ in fake })

        controller.configure(tier: .free)

        #expect(!controller.isEnabled)
        // The engine was never rebuilt (enable stayed false == initial), so it
        // is still the constructor's Noop, and the fake was never started.
        #expect(controller.engine is NoopSyncEngine)
        #expect(await fake.startCount == 0)
    }

    @Test("Enabling flips isEnabled, arms the fake engine, and starts it")
    func enableFlipArmsAndStarts() async {
        let fake = FakeSyncEngine()
        var idleFired = false
        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: Self.tempURL(),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            onIdle: { idleFired = true },
            makeEngine: { _, _, _, _, _, _, _ in fake })

        controller.configure(tier: .pro)

        #expect(controller.isEnabled)
        // The engine swap is synchronous, so this is race-free.
        #expect(controller.engine is FakeSyncEngine)
        // Enabling starts the engine and must NOT take the idle branch.
        #expect(!idleFired)
        await Self.until { await fake.startCount == 1 }
        #expect(await fake.startCount == 1)
        #expect(await fake.stopCount == 0)
    }

    @Test("Disabling stops the previous engine and takes the raw idle branch")
    func disableFlipStopsAndGoesIdle() async {
        let fake = FakeSyncEngine()
        var idleCount = 0
        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: Self.tempURL(),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            onIdle: { idleCount += 1 },
            makeEngine: { _, _, _, _, _, _, _ in fake })

        controller.configure(tier: .pro)  // arm
        controller.configure(tier: .free)  // disarm

        #expect(!controller.isEnabled)
        // The disable branch assigns `.idle` raw (via onIdle), never through the
        // status mapping — exactly once for this single flip.
        #expect(idleCount == 1)
        await Self.until { await fake.stopCount == 1 }
        #expect(await fake.stopCount == 1)
    }

    @Test("An engine status is routed to the shell's onStatus mapping")
    func statusRoutesToOnStatus() async {
        let fake = FakeSyncEngine()
        // Capture the @Sendable status sink the controller wires into make().
        var sink: (@Sendable (SyncStatus) -> Void)?
        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: Self.tempURL(),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            makeEngine: { _, _, _, _, _, onStatus, _ in
                sink = onStatus
                return fake
            })
        var received: [SyncStatus] = []
        controller.onStatus = { received.append($0) }

        controller.configure(tier: .pro)
        // Simulate the engine emitting a settled status; the controller's sink
        // hops to the main actor and forwards to `onStatus`.
        sink?(.upToDate(at: nil))

        await Self.until { !received.isEmpty }
        #expect(received == [.upToDate(at: nil)])
    }

    @Test("The shell's diagnostics log is handed to the engine factory")
    func diagnosticsThreadThroughToTheFactory() async {
        let fake = FakeSyncEngine()
        let log = DiagnosticLog()
        var receivedLog: DiagnosticLog?
        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: Self.tempURL(),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            makeEngine: { _, _, _, _, _, _, diagnostics in
                receivedLog = diagnostics
                return fake
            })
        // Set post-init, exactly like the shells wire it (beside onStatus).
        controller.diagnostics = log

        controller.configure(tier: .pro)

        // The factory received the SAME log instance the shell surfaces in its
        // Privacy Center — the adapter's content-free entries land there.
        #expect(receivedLog === log)
    }

    @Test("reset() deletes the persisted state file and re-arms sync")
    func resetDeletesStateAndReconfigures() async {
        let fake = FakeSyncEngine()
        let url = Self.tempURL()
        try? Data("token".utf8).write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let controller = SyncController(
            store: FakeSyncLocalStore(),
            stateStoreURL: url,
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            makeEngine: { _, _, _, _, _, _, _ in fake })
        controller.configure(tier: .pro)  // arm over the existing file

        controller.reset(tier: .pro)

        // The state file is gone and sync is armed again from scratch.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(controller.isEnabled)
        #expect(controller.engine is FakeSyncEngine)
    }

    /// A unique, unused temp path for the injected state store.
    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-\(UUID().uuidString).plist")
    }

    /// Spin the cooperative pool until `condition` holds or a bound is reached,
    /// so a fire-and-forget `Task { … start() }` can be observed without an
    /// arbitrary sleep and without risking an unbounded hang on failure.
    private static func until(_ condition: () async -> Bool) async {
        for _ in 0..<1_000 {
            if await condition() { return }
            await Task.yield()
        }
    }
}

/// Records the lifecycle calls the controller fires fire-and-forget. An actor
/// so the counters are read race-free from the test's main-actor assertions.
private actor FakeSyncEngine: SyncEngine {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async throws { startCount += 1 }
    func stop() async { stopCount += 1 }
    func enqueue(_ items: [ClipItem]) async {}
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

/// Minimal conformer — the controller only forwards it to `makeEngine`, so no
/// method here is ever called; they exist solely to satisfy the protocol.
private struct FakeSyncLocalStore: SyncLocalStore {
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] { [] }
    func pendingUploadCount() async throws -> Int { 0 }
    func pendingUploadIDs() async throws -> [UUID] { [] }
    func pendingUpload(id: UUID) async throws -> (item: ClipItem, content: ClipContent?)? { nil }
    func pendingDeletionRecordIDs() async throws -> [String] { [] }
    func markUploaded(id: UUID, systemFields: Data) async throws {}
    func systemFields(for id: UUID) async throws -> Data? { nil }
    func markNeedsUpload(id: UUID) async throws {}
    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    ) async throws -> Bool { true }
    func applyRemoteDeletion(recordID: String) async throws {}
    func clearTombstone(recordID: String) async throws {}
    func forgetAllSyncFields() async throws {}
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID> { [] }
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws {}
    func pendingBoardUploads() async throws -> [Pinboard] { [] }
    func markBoardNeedsUpload(id: UUID) async throws {}
    func markBoardUploaded(id: UUID, systemFields: Data) async throws {}
    func boardSystemFields(for id: UUID) async throws -> Data? { nil }
    func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws {}
    func forgetAllBoardSyncFields() async throws {}
    func pendingBoardDeletionRecordIDs() async throws -> [String] { [] }
    func applyRemoteBoardDeletion(recordID: String) async throws {}
    func clearBoardTombstone(recordID: String) async throws {}
}
