import CloudKit
import Foundation
import GanchoKit
import GanchoSync
import Testing

/// The live sync-pipeline harness: two independent `CKSyncEngineAdapter`s in
/// this one (entitled, signed, iCloud-signed-in) process play "device A" and
/// "device B" against the REAL development container — the pattern Apple's own
/// CKSyncEngine sample uses for its tests. It exercises the exact paths every
/// silent breakage of 2026-07-06 lived in: upload, the explicit pull
/// (`pollRemoteChanges` — a test process receives no push), the second-save
/// enrichment fruit with its conflict re-queue, and tombstone deletion.
///
/// OWNER-GATED: talks to the real dev container and briefly writes a probe
/// clip there (real devices polling meanwhile may see it flash before the
/// cleanup tombstone removes it). Run with `make test-sync-e2e`; skips unless
/// the env gate, an iCloud account, and CloudKit entitlements are present — so
/// CI and a stray full-scheme test run stay inert.
@Suite(
    "Sync pipeline E2E — live CloudKit",
    .enabled(
        if: ProcessInfo.processInfo.environment["GANCHO_SYNC_E2E"] == "1"
            && FileManager.default.ubiquityIdentityToken != nil
            && CloudKitEntitlements.currentTaskAllowsSync()),
    .serialized)
struct SyncPipelineE2ETests {
    /// One simulated device: its own encrypted store and adapter, with engine
    /// and poll state isolated in a throwaway directory.
    private struct Device {
        let store: GRDBClipboardStore
        let adapter: CKSyncEngineAdapter

        init(name: String) throws {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("gancho-sync-e2e-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            store = try GRDBClipboardStore.encrypted(directory: dir)
            let state = dir.appendingPathComponent("engine-state.plist")
            adapter = CKSyncEngineAdapter(
                store: store,
                containerIdentifier: SyncEnablement.defaultContainerIdentifier,
                stateStore: .file(at: state),
                pollStateStore: .file(at: state.appendingPathExtension("poll")))
        }
    }

    private struct Timeout: Error, CustomStringConvertible {
        let what: String
        var description: String { "timed out waiting for: \(what)" }
    }

    /// Bounded retry: server-side propagation is fast but not synchronous.
    private func eventually(
        _ what: String, tries: Int = 12, delay: Duration = .seconds(5),
        _ condition: () async throws -> Bool
    ) async throws {
        for attempt in 1...tries {
            if try await condition() { return }
            if attempt < tries { try await Task.sleep(for: delay) }
        }
        throw Timeout(what: what)
    }

    @Test("Clip, enrichment fruit, and deletion cross between two live engines")
    func clipFruitAndDeletionCrossBetweenTwoLiveEngines() async throws {
        let a = try Device(name: "a")
        let b = try Device(name: "b")

        // Device A captures a clip and uploads it (first save).
        let marker = "gancho e2e probe \(UUID().uuidString)"
        let item = ClipItem(kind: .text, preview: marker, contentHash: marker)
        _ = try await a.store.insert(item, content: .text(marker))
        await a.adapter.enqueue([item])
        try await a.adapter.start()

        // Device B pulls it — the explicit-pull path, exactly what the macOS
        // agent relies on in production.
        try await eventually("the clip reaches device B") {
            try await b.adapter.start()
            return try await b.store.item(id: item.id) != nil
        }
        let received = try await b.store.item(id: item.id)
        #expect(received?.preview == marker)

        // Device A writes the enrichment fruit — the SECOND save of the same
        // record (the exact shape of the smart-title race, conflict re-queue
        // included).
        try await a.store.updateTitle(id: item.id, title: "E2E fruit")
        await a.adapter.enqueue([item])
        try await a.adapter.start()

        try await eventually("the enrichment title reaches device B") {
            try await b.adapter.start()
            return try await b.store.item(id: item.id)?.title == "E2E fruit"
        }

        // Cleanup that is itself an assertion: tombstone-delete the probe so
        // the server (and any real device that pulled it meanwhile) forgets it.
        try await a.store.deleteForSync(id: item.id)
        await a.adapter.enqueueDeletion(ids: [item.id])
        try await a.adapter.start()

        try await eventually("the deletion reaches device B") {
            try await b.adapter.start()
            return try await b.store.item(id: item.id) == nil
        }
    }
}
