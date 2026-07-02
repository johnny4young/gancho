import CloudKit
import Foundation
import GanchoKit

/// Drives CloudKit's `CKSyncEngine` over the private database — the live
/// implementation of the `SyncEngine` boundary, and (with `ClipRecordMapper`)
/// the only place the app talks to CloudKit. End-to-end encrypted: all
/// content rides `encryptedValues`/`CKAsset`, never plain fields.
///
/// An `actor` so the engine's serial event stream and the app's `enqueue`
/// calls share one consistent view. The `CKSyncEngine` is created lazily on
/// first use, so *constructing* the adapter never touches the network —
/// free-tier and signed-out paths build it and simply never call `start()`.
public actor CKSyncEngineAdapter: SyncEngine {
    private let store: any SyncLocalStore
    private let containerIdentifier: String
    private let stateStore: SyncStateStore
    private let maxAssetBytes: Int
    private let zoneID = CKRecordZone.ID(
        zoneName: ClipRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)
    /// Boards live in their own zone — cleaner separation, and the unit a
    /// future `CKShare` would share.
    private let boardZoneID = CKRecordZone.ID(
        zoneName: BoardRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?
    /// Set when CloudKit reports the account is out of storage; cleared on the
    /// next explicit `start()`. While paused we stop feeding new changes — the
    /// visible-sync-status work surfaces this to the user.
    private var isPaused = false

    /// Status sink for the UI (set by the factory). Receives `SyncStatus`
    /// values only — state and counts, never clip content.
    private let onStatus: (@Sendable (SyncStatus) -> Void)?

    private let stateEncoder = PropertyListEncoder()
    private let stateDecoder = PropertyListDecoder()

    public init(
        store: any SyncLocalStore,
        containerIdentifier: String,
        stateStore: SyncStateStore,
        maxAssetBytes: Int = ClipRecordMapper.defaultMaxAssetBytes,
        onStatus: (@Sendable (SyncStatus) -> Void)? = nil
    ) {
        self.store = store
        self.containerIdentifier = containerIdentifier
        self.stateStore = stateStore
        self.maxAssetBytes = maxAssetBytes
        self.onStatus = onStatus
    }

    // MARK: - SyncEngine boundary

    public func start() async throws {
        isPaused = false
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID)),
            .saveZone(CKRecordZone(zoneID: boardZoneID)),
        ])
        await reenqueuePendingWork(into: engine)
        await reconcilePendingChanges(in: engine)
        emit(.syncing)
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            emit(.failed(Self.interruption(error)))
            throw error
        }
        await emitCurrentStatus()
    }

    public func stop() async {
        // Dropping the engine ends its background sync; the persisted state
        // blob lets a later start() resume where we left off. Also breaks the
        // adapter ⇄ engine retain cycle (the engine holds this as its delegate).
        engine = nil
    }

    public func enqueue(_ items: [ClipItem]) async {
        guard !isPaused else { return }
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        for item in items {
            // Guarantee the row appears in pendingUploads() even for an edit of
            // an already-synced clip — the batch provider builds records from there.
            try? await store.markNeedsUpload(id: item.id)
        }
        engine.state.add(
            pendingRecordZoneChanges: items.map { .saveRecord(recordID(for: $0.id)) })
    }

    public func enqueueDeletion(ids: [UUID]) async {
        guard !isPaused else { return }
        let engine = ensureEngine()
        engine.state.add(
            pendingRecordZoneChanges: ids.map { .deleteRecord(recordID(for: $0)) })
    }

    public func enqueue(boards: [Pinboard]) async {
        guard !isPaused else { return }
        let engine = ensureEngine()
        engine.state.add(
            pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: boardZoneID))])
        for board in boards {
            try? await store.markBoardNeedsUpload(id: board.id)
        }
        engine.state.add(
            pendingRecordZoneChanges: boards.map { .saveRecord(boardRecordID(for: $0.id)) })
    }

    public func enqueueBoardDeletion(ids: [UUID]) async {
        guard !isPaused else { return }
        let engine = ensureEngine()
        engine.state.add(
            pendingRecordZoneChanges: ids.map { .deleteRecord(boardRecordID(for: $0)) })
    }

    // MARK: - Engine lifecycle

    private func ensureEngine() -> CKSyncEngine {
        if let engine { return engine }
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadSerialization(),
            delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        return engine
    }

    private func loadSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = stateStore.load() else { return nil }
        return try? stateDecoder.decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    private func boardRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: boardZoneID)
    }

    // MARK: - Status

    private func emit(_ status: SyncStatus) {
        onStatus?(status)
    }

    /// Recompute and emit the resting status after a cycle: paused if CloudKit
    /// reported the account is full, otherwise pending(N) or up-to-date.
    private func emitCurrentStatus() async {
        if isPaused {
            emit(.paused(.iCloudFull))
            return
        }
        let uploads = (try? await store.pendingUploads().count) ?? 0
        let deletions = (try? await store.pendingDeletionRecordIDs().count) ?? 0
        let boardUploads = (try? await store.pendingBoardUploads().count) ?? 0
        let boardDeletions = (try? await store.pendingBoardDeletionRecordIDs().count) ?? 0
        let pending = uploads + deletions + boardUploads + boardDeletions
        emit(pending > 0 ? .pending(pending) : .upToDate(at: Date()))
    }

    /// Maps a CloudKit error to a structured interruption the UI localizes.
    private static func interruption(_ error: Error) -> SyncInterruption {
        guard let ckError = error as? CKError else { return .unknown }
        switch ckError.code {
        case .notAuthenticated: return .notSignedIn
        case .networkUnavailable, .networkFailure: return .offline
        case .quotaExceeded: return .iCloudFull
        default: return .unknown
        }
    }

    /// Re-registers everything the local store still considers unsynced — used
    /// on a fresh start, after sign-in, and after a server zone reset.
    private func reenqueuePendingWork(into engine: CKSyncEngine) async {
        if let pending = try? await store.pendingUploads() {
            engine.state.add(
                pendingRecordZoneChanges: pending.map { .saveRecord(recordID(for: $0.item.id)) })
        }
        if let deletions = try? await store.pendingDeletionRecordIDs() {
            engine.state.add(
                pendingRecordZoneChanges: deletions.compactMap { name in
                    UUID(uuidString: name).map { .deleteRecord(recordID(for: $0)) }
                })
        }
        if let pendingBoards = try? await store.pendingBoardUploads() {
            engine.state.add(
                pendingRecordZoneChanges: pendingBoards.map {
                    .saveRecord(boardRecordID(for: $0.id))
                })
        }
        if let boardDeletions = try? await store.pendingBoardDeletionRecordIDs() {
            engine.state.add(
                pendingRecordZoneChanges: boardDeletions.compactMap { name in
                    UUID(uuidString: name).map { .deleteRecord(boardRecordID(for: $0)) }
                })
        }
    }

    /// Drop pending `.saveRecord` changes the store no longer wants uploaded. A
    /// resumed engine state can carry stale saves (e.g. a record uploaded under
    /// a state the engine then lost track of) that no provider can build — the
    /// send queue would jam on empty batches forever. Deletions are left alone:
    /// their record names are tombstones tracked separately from the clip rows.
    private func reconcilePendingChanges(in engine: CKSyncEngine) async {
        let validClipIDs = Set(
            ((try? await store.pendingUploads()) ?? []).map { recordID(for: $0.item.id) })
        let validBoardIDs = Set(
            ((try? await store.pendingBoardUploads()) ?? []).map { boardRecordID(for: $0.id) })
        let stale = engine.state.pendingRecordZoneChanges.filter { change in
            guard case .saveRecord(let id) = change else { return false }
            if id.zoneID.zoneName == zoneID.zoneName { return !validClipIDs.contains(id) }
            if id.zoneID.zoneName == boardZoneID.zoneName { return !validBoardIDs.contains(id) }
            return false
        }
        guard !stale.isEmpty else { return }
        engine.state.remove(pendingRecordZoneChanges: stale)
    }
}

// MARK: - CKSyncEngineDelegate

extension CKSyncEngineAdapter: CKSyncEngineDelegate {
    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
        guard !pendingChanges.isEmpty else { return nil }

        // The record provider is synchronous, but our store is async: build
        // every record up front, then hand the closure a plain dictionary
        // lookup. CKRecord is not Sendable, so the prefetched map crosses into
        // the closure inside an unchecked box — safe, as it is read-only.
        var built: [CKRecord.ID: CKRecord] = [:]
        if let pending = try? await store.pendingUploads() {
            for entry in pending {
                let systemFields = (try? await store.systemFields(for: entry.item.id)) ?? nil
                let boardIDs = (try? await store.boardIDs(forClip: entry.item.id)) ?? []
                if let record = ClipRecordMapper.record(
                    for: entry.item, content: entry.content, systemFields: systemFields,
                    zoneID: zoneID, maxAssetBytes: maxAssetBytes, boardIDs: Array(boardIDs))
                {
                    built[recordID(for: entry.item.id)] = record
                }
            }
        }
        if let pendingBoards = try? await store.pendingBoardUploads() {
            for board in pendingBoards {
                let systemFields = (try? await store.boardSystemFields(for: board.id)) ?? nil
                if let record = BoardRecordMapper.record(
                    for: board, systemFields: systemFields, zoneID: boardZoneID)
                {
                    built[boardRecordID(for: board.id)] = record
                }
            }
        }
        let records = UncheckedSendableBox(built)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) {
            recordID in records.value[recordID]
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            if let data = try? stateEncoder.encode(event.stateSerialization) {
                stateStore.save(data)
            }
        case .accountChange(let event):
            await handleAccountChange(event, syncEngine: syncEngine)
        case .fetchedDatabaseChanges(let event):
            await handleFetchedDatabaseChanges(event, syncEngine: syncEngine)
        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event)
        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            emit(.syncing)
        case .didFetchChanges, .didSendChanges:
            await emitCurrentStatus()
        default:
            // sentDatabaseChanges, will/didFetchRecordZoneChanges: no status change.
            break
        }
    }

    private func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange, syncEngine: CKSyncEngine
    ) async {
        switch event.changeType {
        case .signIn:
            emit(.syncing)
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID)),
                .saveZone(CKRecordZone(zoneID: boardZoneID)),
            ])
            await reenqueuePendingWork(into: syncEngine)
        case .signOut, .switchAccounts:
            // Forget the old account's record identities; keep local history.
            try? await store.forgetAllSyncFields()
            try? await store.forgetAllBoardSyncFields()
            emit(.idle)
        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges, syncEngine: CKSyncEngine
    ) async {
        let clipZoneReset = event.deletions.contains { $0.zoneID.zoneName == zoneID.zoneName }
        let boardZoneReset = event.deletions.contains { $0.zoneID.zoneName == boardZoneID.zoneName }
        guard clipZoneReset || boardZoneReset else { return }
        // A zone was reset/deleted server-side: drop the stale identities for
        // that zone and re-upload into a freshly recreated one.
        if clipZoneReset { try? await store.forgetAllSyncFields() }
        if boardZoneReset { try? await store.forgetAllBoardSyncFields() }
        syncEngine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID)),
            .saveZone(CKRecordZone(zoneID: boardZoneID)),
        ])
        await reenqueuePendingWork(into: syncEngine)
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async {
        for modification in event.modifications {
            let record = modification.record
            if record.recordType == BoardRecordMapper.recordType {
                if let board = BoardRecordMapper.decode(record) {
                    try? await store.applyRemoteBoardUpsert(
                        board, systemFields: BoardRecordMapper.encodeSystemFields(record))
                }
                continue
            }
            guard let decoded = ClipRecordMapper.decode(record) else { continue }
            // Membership rides the clip record, so it follows the same
            // last-writer-wins decision: a stale remote must not overwrite a
            // newer local board set (the store returns whether it applied).
            let applied =
                (try? await store.applyRemoteUpsert(
                    decoded.item, content: decoded.content,
                    systemFields: ClipRecordMapper.encodeSystemFields(record))) ?? false
            if applied {
                try? await store.setBoardMembership(
                    clipID: decoded.item.id,
                    boardIDs: Set(ClipRecordMapper.boardIDs(from: record)))
            }
        }
        for deletion in event.deletions {
            if deletion.recordID.zoneID.zoneName == boardZoneID.zoneName {
                try? await store.applyRemoteBoardDeletion(recordID: deletion.recordID.recordName)
            } else {
                try? await store.applyRemoteDeletion(recordID: deletion.recordID.recordName)
            }
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine
    ) async {
        for record in event.savedRecords {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            if record.recordType == BoardRecordMapper.recordType {
                try? await store.markBoardUploaded(
                    id: id, systemFields: BoardRecordMapper.encodeSystemFields(record))
            } else {
                try? await store.markUploaded(
                    id: id, systemFields: ClipRecordMapper.encodeSystemFields(record))
            }
        }
        for recordID in event.deletedRecordIDs {
            if recordID.zoneID.zoneName == boardZoneID.zoneName {
                try? await store.clearBoardTombstone(recordID: recordID.recordName)
            } else {
                try? await store.clearTombstone(recordID: recordID.recordName)
            }
        }
        for failure in event.failedRecordSaves {
            await handleFailedSave(failure, syncEngine: syncEngine)
        }
    }

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) async {
        let recordID = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            // Conflict — last-writer-wins: take the server copy. The upserts
            // keep whichever updatedAt is newer and record the server's tag.
            guard let serverRecord = failure.error.serverRecord else { break }
            if serverRecord.recordType == BoardRecordMapper.recordType {
                if let board = BoardRecordMapper.decode(serverRecord) {
                    try? await store.applyRemoteBoardUpsert(
                        board, systemFields: BoardRecordMapper.encodeSystemFields(serverRecord))
                }
            } else if let decoded = ClipRecordMapper.decode(serverRecord) {
                // Same LWW gate as the fetch path: only take the server's
                // board membership when the server copy actually won.
                let applied =
                    (try? await store.applyRemoteUpsert(
                        decoded.item, content: decoded.content,
                        systemFields: ClipRecordMapper.encodeSystemFields(serverRecord))) ?? false
                if applied {
                    try? await store.setBoardMembership(
                        clipID: decoded.item.id,
                        boardIDs: Set(ClipRecordMapper.boardIDs(from: serverRecord)))
                }
            }
        case .zoneNotFound, .userDeletedZone:
            // Recreate the failed record's own zone, then retry it.
            syncEngine.state.add(
                pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .quotaExceeded:
            isPaused = true
            emit(.paused(.iCloudFull))
        default:
            // Transient (network, rate limit, server busy): CKSyncEngine retries
            // on its own — nothing to do.
            break
        }
    }
}

/// Read-only handoff of a non-`Sendable` payload into a `Sendable` closure.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
