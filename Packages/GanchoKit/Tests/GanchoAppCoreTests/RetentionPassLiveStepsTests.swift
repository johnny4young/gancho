import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A sync engine that records the deletions the live steps hand it.
private actor DeletionRecorder: SyncEngine {
    private(set) var deletions: [[UUID]] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async {}
    func enqueueDeletion(ids: [UUID]) async { deletions.append(ids) }
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

/// `RetentionPass.Steps.live` over a real store and a real `SyncController` —
/// the wiring the fake-driven suite cannot see. A mistyped store call or a
/// dropped sync gate would pass every test there and still leave an expired
/// secret's record in iCloud, so it is checked here end to end.
@MainActor
@Suite("Retention pass — live steps")
struct RetentionPassLiveStepsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> GRDBClipboardStore {
        try GRDBClipboardStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("retention-live-\(UUID().uuidString)", isDirectory: true))
    }

    private func makeController(
        store: GRDBClipboardStore, engine: any SyncEngine, tier: UserTier
    ) -> SyncController {
        let controller = SyncController(
            store: store,
            stateStoreURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("retention-live-\(UUID().uuidString).plist"),
            iCloudAvailable: { true },
            hasCloudKitEntitlement: { true },
            makeEngine: { _, _, _, _, _, _, _, _ in engine })
        controller.configure(tier: tier)
        return controller
    }

    /// A synced, sensitive clip older than the sensitive lifetime: the purge
    /// tombstones it (it carries system fields) and deletes it.
    private func seedExpiredSecret(in store: GRDBClipboardStore) async throws -> UUID {
        let clip = try await store.insert(
            ClipItem(
                createdAt: now.addingTimeInterval(-3_600), preview: "expired secret",
                contentHash: "expired-secret", isSensitive: true),
            content: .text("expired secret"))
        try await store.markUploaded(id: clip.id, systemFields: Data("system-fields".utf8))
        return clip.id
    }

    @Test("With sync on the clip is deleted, counted once, and its deletion reaches the engine")
    func livePassPurgesRecordsAndPropagates() async throws {
        let store = try makeStore()
        let id = try await seedExpiredSecret(in: store)
        let engine = DeletionRecorder()
        let sync = makeController(store: store, engine: engine, tier: .pro)
        #expect(sync.isEnabled)

        let changed = await RetentionPass(steps: .live(store: store, sync: sync))
            .run(policy: RetentionPolicy(), tier: { .pro }, now: now)

        #expect(changed)
        // Deleted, not merely counted.
        #expect(try await store.items().isEmpty)
        #expect(try await store.privateActivityReceipt(now: now).sensitiveItemsExpired == 1)
        #expect(await engine.deletions == [[id]])
    }

    /// The gate itself, asserted directly: with sync off the controller's engine
    /// is a `NoopSyncEngine`, so "no engine was asked" and "the Noop was asked"
    /// look identical from a recording spy. Only this distinguishes them.
    @Test("The live sync gate hands over an engine only while sync is on")
    func liveSyncGateFollowsTheController() throws {
        let store = try makeStore()
        let engine = DeletionRecorder()
        let off = makeController(store: store, engine: engine, tier: .free)
        let on = makeController(store: store, engine: engine, tier: .pro)

        #expect(RetentionPass.Steps.live(store: store, sync: off).syncEngine() == nil)
        let armed = try #require(RetentionPass.Steps.live(store: store, sync: on).syncEngine())
        #expect(armed is DeletionRecorder)
    }

    @Test("With sync off the clip is still deleted and counted, and no engine is asked")
    func livePassWithSyncOffTouchesNoEngine() async throws {
        let store = try makeStore()
        _ = try await seedExpiredSecret(in: store)
        let engine = DeletionRecorder()
        let sync = makeController(store: store, engine: engine, tier: .free)
        #expect(!sync.isEnabled)

        await RetentionPass(steps: .live(store: store, sync: sync))
            .run(policy: RetentionPolicy(), tier: { .free }, now: now)

        #expect(try await store.items().isEmpty)
        #expect(try await store.privateActivityReceipt(now: now).sensitiveItemsExpired == 1)
        #expect(await engine.deletions.isEmpty)
    }
}
