import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

@Suite("Sync enablement policy and engine selection")
struct SyncEnablementTests {
    @Test("Sync runs only for Pro on an iCloud-signed-in device")
    func truthTable() {
        #expect(SyncEnablement.shouldEnable(tier: .pro, iCloudAvailable: true))
        #expect(!SyncEnablement.shouldEnable(tier: .pro, iCloudAvailable: false))
        #expect(!SyncEnablement.shouldEnable(tier: .free, iCloudAvailable: true))
        #expect(!SyncEnablement.shouldEnable(tier: .free, iCloudAvailable: false))
    }

    @Test("Factory returns Noop unless enabled, the adapter when it is")
    func factorySelection() {
        let store = StubSyncLocalStore()
        let stateStore = SyncStateStore(load: { nil }, save: { _ in })

        let disabled = SyncEngineFactory.make(
            store: store, tier: .free, iCloudAvailable: true, stateStore: stateStore)
        #expect(disabled is NoopSyncEngine)

        let enabled = SyncEngineFactory.make(
            store: store, tier: .pro, iCloudAvailable: true, stateStore: stateStore)
        #expect(enabled is CKSyncEngineAdapter)
    }
}

/// Minimal in-memory conformer — the factory only needs *a* store; building
/// the adapter must not touch CloudKit, which this proves on CI (no iCloud).
private struct StubSyncLocalStore: SyncLocalStore {
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] { [] }
    func pendingDeletionRecordIDs() async throws -> [String] { [] }
    func markUploaded(id: UUID, systemFields: Data) async throws {}
    func systemFields(for id: UUID) async throws -> Data? { nil }
    func markNeedsUpload(id: UUID) async throws {}
    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    )
        async throws
    {}
    func applyRemoteDeletion(recordID: String) async throws {}
    func clearTombstone(recordID: String) async throws {}
    func forgetAllSyncFields() async throws {}
}
