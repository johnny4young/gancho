import CloudKit
import CryptoKit
import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

private enum FetchFailure: Error { case offline }

private actor RepairSpy {
    var unreadable: [UUID]
    private(set) var fetchedChunks: [[CKRecord.ID]] = []
    private(set) var applied: [CKRecord.ID] = []

    init(unreadable: [UUID]) { self.unreadable = unreadable }

    func fetched(_ ids: [CKRecord.ID]) { fetchedChunks.append(ids) }

    /// Applying a record heals its clip, as the store does.
    func apply(_ records: [CKRecord]) {
        applied += records.map(\.recordID)
        let healed = Set(records.compactMap { UUID(uuidString: $0.recordID.recordName) })
        unreadable.removeAll { healed.contains($0) }
    }
}

@Suite("Unreadable synced clips — restored from the server copy")
struct SyncUnreadableRepairTests {
    private let zone = CKRecordZone.ID(
        zoneName: ClipRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)

    private func repair(
        _ spy: RepairSpy,
        missing: Set<UUID> = [],
        fetchError: (any Error)? = nil
    ) -> SyncUnreadableRepair {
        let zone = zone
        return SyncUnreadableRepair(
            zoneID: zone,
            unreadable: { await spy.unreadable },
            fetch: { ids in
                await spy.fetched(ids)
                if let fetchError { throw fetchError }
                var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
                for id in ids {
                    let missingRecord =
                        UUID(uuidString: id.recordName).map(missing.contains) ?? true
                    results[id] =
                        missingRecord
                        ? .failure(CKError(.unknownItem))
                        : .success(CKRecord(recordType: ClipRecordMapper.recordType, recordID: id))
                }
                return results
            },
            apply: { await spy.apply($0) })
    }

    @Test("Nothing unreadable fetches nothing")
    func nothingToRestore() async throws {
        let spy = RepairSpy(unreadable: [])

        #expect(try await repair(spy).run() == nil)
        #expect(await spy.fetchedChunks.isEmpty)
    }

    @Test("Records come in bounded chunks and a missing one stays unreadable")
    func chunksAndMissingRecords() async throws {
        let size = SyncUnreadableRepair.fetchChunkSize
        let ids = (0..<size + 50).map { _ in UUID() }
        let spy = RepairSpy(unreadable: ids)

        let outcome = try await repair(spy, missing: [ids[0]]).run()

        #expect(outcome == .init(restored: ids.count - 1, remaining: 1))
        #expect(await spy.fetchedChunks.map(\.count) == [size, 50])
        #expect(await spy.fetchedChunks.flatMap { $0 }.allSatisfy { $0.zoneID == zone })
        #expect(await spy.unreadable == [ids[0]])
    }

    @Test("A failed fetch throws and applies nothing")
    func failedFetchThrows() async {
        let spy = RepairSpy(unreadable: [UUID()])

        await #expect(throws: FetchFailure.self) {
            try await repair(spy, fetchError: FetchFailure.offline).run()
        }
        #expect(await spy.applied.isEmpty)
    }

    @Test("The adapter heals a synced clip from its fetched record, logging counts only")
    func adapterRestoresSyncedClip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data("restore-fixture".utf8) + Data([0, 1, 2])
        let content = ClipContent.binary(data: payload, typeIdentifier: "public.data")
        let store = try GRDBClipboardStore(directory: dir, passphrase: "restore-test-passphrase")
        let item = try await store.insert(
            ClipItem(
                kind: .image, preview: "Image",
                contentHash: ClipItem.hash(of: payload, kind: .image)),
            content: content)
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try SealedEnvelope.seal(payload, key: Data(SHA256.hash(data: Data(UUID().uuidString.utf8))))
            .write(to: dir.appendingPathComponent("blobs").appendingPathComponent(hash))
        #expect(try await store.unrecoverableSyncedClipIDs() == [item.id])

        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: content, systemFields: nil, zoneID: zone))
        defer { ClipRecordMapper.removeStagedAsset(for: record) }
        let log = DiagnosticLog()
        let adapter = CKSyncEngineAdapter(
            store: store, containerIdentifier: "iCloud.test.gancho",
            stateStore: SyncStateStore(load: { nil }, save: { _ in }), diagnostics: log,
            fetchRecords: { ids in
                Dictionary(uniqueKeysWithValues: ids.map { ($0, .success(record)) })
            })

        await adapter.restoreUnreadableSyncedClips()

        #expect(try await store.unrecoverableSyncedClipIDs().isEmpty)
        #expect(try await store.content(for: item.id) == content)
        let messages = log.entries.map(\.message)
        #expect(messages.contains { $0.contains("Restored 1 unreadable clip") })
        #expect(!messages.contains { $0.contains(hash) || $0.contains(item.id.uuidString) })
    }
}
