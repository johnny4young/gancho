import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

@Suite("CloudKit sync engine selection")
struct SyncEnablementTests {
    @Test("Factory returns Noop unless enabled, the adapter when it is")
    func factorySelection() {
        let store = StubSyncLocalStore()
        let stateStore = SyncStateStore(load: { nil }, save: { _ in })

        let disabled = SyncEngineFactory.make(
            store: store, tier: .free, iCloudAvailable: true, stateStore: stateStore)
        #expect(disabled is NoopSyncEngine)

        let unsigned = SyncEngineFactory.make(
            store: store, tier: .pro, iCloudAvailable: true,
            hasCloudKitEntitlement: false, stateStore: stateStore)
        #expect(unsigned is NoopSyncEngine)

        let enabled = SyncEngineFactory.make(
            store: store, tier: .pro, iCloudAvailable: true, stateStore: stateStore)
        #expect(enabled is CKSyncEngineAdapter)
    }

    @Test("Entitlement parser accepts strings and arrays, rejects missing values")
    func entitlementParser() {
        #expect(CloudKitEntitlements.contains("CloudKit" as CFString, "CloudKit"))
        #expect(
            CloudKitEntitlements.contains(
                ["iCloud.com.johnny4young.gancho"] as CFArray,
                "iCloud.com.johnny4young.gancho"))
        #expect(!CloudKitEntitlements.contains(nil, "CloudKit"))
        #expect(!CloudKitEntitlements.contains(["CloudDocuments"] as CFArray, "CloudKit"))
    }
}

/// Minimal in-memory conformer — the factory only needs *a* store; building
/// the adapter must not touch CloudKit, which this proves on CI (no iCloud).
private struct StubSyncLocalStore: SyncLocalStore {
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] { [] }
    func pendingUploadCount() async throws -> Int { 0 }
    func pendingUploadIDs() async throws -> [UUID] { [] }
    func pendingUpload(id: UUID) async throws -> (item: ClipItem, content: ClipContent?)? {
        nil
    }
    func pendingDeletionRecordIDs() async throws -> [String] { [] }
    func markUploaded(id: UUID, systemFields: Data) async throws {}
    func systemFields(for id: UUID) async throws -> Data? { nil }
    func markNeedsUpload(id: UUID) async throws {}
    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    )
        async throws -> Bool
    { true }
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
