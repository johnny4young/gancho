import CloudKit
import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

/// The adapter's shared apply path (`applyFetched`) and error classification —
/// the exact pipeline BOTH delivery mechanisms (the engine's push-fed fetch
/// events and `pollRemoteChanges`) funnel through. Records are built with the
/// real `ClipRecordMapper`, so these tests break if the mapper and the apply
/// path ever drift apart. Constructing the adapter never touches CloudKit
/// (documented on the actor), and `applyFetched` reaches only the store +
/// mappers + diagnostics, so no test needs entitlements or a network.
@Suite("CKSyncEngineAdapter — apply path and error classification")
struct CKSyncEngineAdapterTests {
    private let clipZone = CKRecordZone.ID(
        zoneName: ClipRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)
    private let boardZone = CKRecordZone.ID(
        zoneName: BoardRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)

    private func makeAdapter(
        store: RecordingStore, diagnostics: DiagnosticLog? = nil
    ) -> CKSyncEngineAdapter {
        CKSyncEngineAdapter(
            store: store,
            containerIdentifier: "iCloud.test.gancho",
            stateStore: SyncStateStore(load: { nil }, save: { _ in }),
            diagnostics: diagnostics)
    }

    @Test("A titled clip record applies — the enrichment fruit reaches the store")
    func titledRecordApplies() async throws {
        let store = RecordingStore()
        let adapter = makeAdapter(store: store)
        let boardID = UUID()
        let item = ClipItem(title: "Rotate the credentials", preview: "body", contentHash: "h")
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("body"), systemFields: nil, zoneID: clipZone,
                boardIDs: [boardID]))

        await adapter.applyFetched(records: [record], deletions: [])

        let upserts = await store.upserts
        #expect(upserts.map(\.id) == [item.id])
        #expect(upserts.first?.title == "Rotate the credentials")
        // The apply reported success, so membership from the record follows.
        #expect(await store.membershipSets == [[boardID]])
    }

    @Test("A stale remote (LWW skip) is NOT a failure and sets no membership")
    func lastWriterWinsSkipIsSilent() async throws {
        let store = RecordingStore()
        await store.setApplyResult(false)  // local copy is newer
        let log = DiagnosticLog()
        let adapter = makeAdapter(store: store, diagnostics: log)
        let record = try #require(
            ClipRecordMapper.record(
                for: ClipItem(preview: "old", contentHash: "h"), content: .text("old"),
                systemFields: nil, zoneID: clipZone))

        await adapter.applyFetched(records: [record], deletions: [])

        #expect(await store.membershipSets.isEmpty, "a losing remote must not touch boards")
        #expect(log.entries.isEmpty, "a normal LWW skip must not read as sync trouble")
    }

    @Test("A store error during apply surfaces content-free in the diagnostics")
    func applyFailureIsCounted() async throws {
        let store = RecordingStore()
        await store.setApplyError(RecordingStore.Failure.boom)
        let log = DiagnosticLog()
        let adapter = makeAdapter(store: store, diagnostics: log)
        let record = try #require(
            ClipRecordMapper.record(
                for: ClipItem(preview: "x", contentHash: "h"), content: .text("x"),
                systemFields: nil, zoneID: clipZone))

        await adapter.applyFetched(records: [record], deletions: [])

        let entry = try #require(log.entries.first)
        #expect(entry.category == "Sync")
        #expect(entry.message.contains("1 failed to apply"))
        #expect(!entry.message.contains("x"), "diagnostics must stay content-free")
    }

    @Test("An undecodable record surfaces as a decode failure, never silently")
    func decodeFailureIsCounted() async {
        let store = RecordingStore()
        let log = DiagnosticLog()
        let adapter = makeAdapter(store: store, diagnostics: log)
        // A clip-type record whose name is not a UUID cannot decode.
        let broken = CKRecord(
            recordType: ClipRecordMapper.recordType,
            recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: clipZone))

        await adapter.applyFetched(records: [broken], deletions: [])

        #expect(await store.upserts.isEmpty)
        #expect(log.entries.first?.message.contains("1 failed to decode") == true)
    }

    @Test("Deletions route by zone: clips to the clip store, boards to the board store")
    func deletionsRouteByZone() async {
        let store = RecordingStore()
        let adapter = makeAdapter(store: store)
        let clipID = UUID().uuidString
        let boardID = UUID().uuidString

        await adapter.applyFetched(
            records: [],
            deletions: [
                CKRecord.ID(recordName: clipID, zoneID: clipZone),
                CKRecord.ID(recordName: boardID, zoneID: boardZone)
            ])

        #expect(await store.clipDeletions == [clipID])
        #expect(await store.boardDeletions == [boardID])
    }

    @Test("Zone-missing classification: first-run fetches skip, real errors do not")
    func missingZoneClassification() {
        func ck(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> Error {
            NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo)
        }
        #expect(CloudKitSyncPolicy.isMissingZone(ck(.zoneNotFound)))
        #expect(CloudKitSyncPolicy.isMissingZone(ck(.userDeletedZone)))
        #expect(
            CloudKitSyncPolicy.isMissingZone(
                ck(
                    .partialFailure,
                    userInfo: [CKPartialErrorsByItemIDKey: ["zone": ck(.zoneNotFound)]])))
        #expect(!CloudKitSyncPolicy.isMissingZone(ck(.networkUnavailable)))
        #expect(
            !CloudKitSyncPolicy.isMissingZone(
                ck(
                    .partialFailure,
                    userInfo: [
                        CKPartialErrorsByItemIDKey: [
                            "a": ck(.zoneNotFound), "b": ck(.networkFailure)
                        ]
                    ])),
            "a partial failure with any non-zone error must not read as first-run")
        #expect(!CloudKitSyncPolicy.isMissingZone(RecordingStore.Failure.boom))
    }
}

/// Records what the adapter asks of the local store; scriptable success/skip/
/// throw for the upsert. An actor so the assertions read race-free.
private actor RecordingStore: SyncLocalStore {
    enum Failure: Error { case boom }

    private(set) var upserts: [ClipItem] = []
    private(set) var membershipSets: [Set<UUID>] = []
    private(set) var clipDeletions: [String] = []
    private(set) var boardDeletions: [String] = []
    private var applyResult = true
    private var applyError: Error?

    func setApplyResult(_ value: Bool) { applyResult = value }
    func setApplyError(_ error: Error?) { applyError = error }

    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    ) async throws -> Bool {
        if let applyError { throw applyError }
        upserts.append(item)
        return applyResult
    }
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws {
        membershipSets.append(boardIDs)
    }
    func applyRemoteDeletion(recordID: String) async throws { clipDeletions.append(recordID) }
    func applyRemoteBoardDeletion(recordID: String) async throws {
        boardDeletions.append(recordID)
    }

    // Unexercised by these tests — trivial conformances.
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] { [] }
    func pendingUploadCount() async throws -> Int { 0 }
    func pendingUploadIDs() async throws -> [UUID] { [] }
    func pendingUpload(id: UUID) async throws -> (item: ClipItem, content: ClipContent?)? { nil }
    func pendingDeletionRecordIDs() async throws -> [String] { [] }
    func markUploaded(id: UUID, systemFields: Data) async throws {}
    func systemFields(for id: UUID) async throws -> Data? { nil }
    func markNeedsUpload(id: UUID) async throws {}
    func clearTombstone(recordID: String) async throws {}
    func forgetAllSyncFields() async throws {}
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID> { [] }
    func pendingBoardUploads() async throws -> [Pinboard] { [] }
    func markBoardNeedsUpload(id: UUID) async throws {}
    func markBoardUploaded(id: UUID, systemFields: Data) async throws {}
    func boardSystemFields(for id: UUID) async throws -> Data? { nil }
    func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws {}
    func forgetAllBoardSyncFields() async throws {}
    func pendingBoardDeletionRecordIDs() async throws -> [String] { [] }
    func clearBoardTombstone(recordID: String) async throws {}
}
