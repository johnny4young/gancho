import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum FakeScanError: Error { case failure }

private actor RemovalStoreSpy: ClipboardStore, ClipMutating, StoreMaintaining {
    private let scan: Result<[UUID], FakeScanError>
    private let syncedScan: [UUID]
    private(set) var plainDeletes: [UUID] = []
    private(set) var syncDeletes: [UUID] = []
    private(set) var localOnlyDeletes: [UUID] = []

    init(scan: Result<[UUID], FakeScanError>, syncedScan: [UUID] = []) {
        self.scan = scan
        self.syncedScan = syncedScan
    }

    func unrecoverableLocalClipIDs() async throws -> [UUID] { try scan.get() }
    func unrecoverableSyncedClipIDs() async throws -> [UUID] { syncedScan }
    func deleteLocalOnly(id: UUID) async throws { localOnlyDeletes.append(id) }
    func delete(id: UUID) async throws { plainDeletes.append(id) }
    func deleteForSync(id: UUID, now _: Date) async throws { syncDeletes.append(id) }

    // Unused requirements.
    @discardableResult
    func insert(_ item: ClipItem, content _: ClipContent?) async throws -> ClipItem { item }
    func items(offset _: Int, limit _: Int) async throws -> [ClipItem] { [] }
    func count() async throws -> Int { 0 }
    func content(for _: UUID) async throws -> ClipContent? { nil }
    func exportJSON() async throws -> Data { Data() }
    func exportCSV() async throws -> Data { Data() }
    @discardableResult
    func deleteAllSensitive() async throws -> Int { 0 }
    func setPinned(id _: UUID, _: Bool) async throws {}
    func recordUse(id _: UUID, now _: Date) async throws {}
    func importBatch(_: [(item: ClipItem, content: ClipContent?)]) async throws {}
    func backfillLegacyPreviews() async throws {}
    func vacuum() async throws {}
}

@Suite("Unrecoverable clip removal — this device only")
struct UnrecoverableClipRemovalTests {
    @Test("Flagged clips, synced ones too, are deleted locally and never tombstoned")
    func removesLocallyWithoutTombstones() async {
        let ids = [UUID(), UUID()]
        let synced = [UUID()]
        let store = RemovalStoreSpy(scan: .success(ids), syncedScan: synced)

        let outcome = await UnrecoverableClipRemoval().remove(scanner: store)

        #expect(outcome == .deleted(propagated: false))
        #expect(await store.localOnlyDeletes == ids + synced)
        #expect(await store.plainDeletes.isEmpty)
        #expect(await store.syncDeletes.isEmpty)
    }

    @Test("A failed scan deletes nothing")
    func failedScanDeletesNothing() async {
        let store = RemovalStoreSpy(scan: .failure(.failure))

        let outcome = await UnrecoverableClipRemoval().remove(scanner: store)

        #expect(outcome == nil)
        #expect(await store.localOnlyDeletes.isEmpty)
    }
}
