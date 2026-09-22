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
    private var receiveHealth = SyncReceiveHealth()
    private var pollTask: Task<Void, any Error>?
    private var pollID: UUID?
    private var receiveRetryTask: Task<Void, Never>?
    private var receiveRetryID: UUID?
    private var statePersistenceFailed = false
    private var receiveGeneration = 0
    private var outboundFailures: Set<OutboundOperation> = []
    private var clipIntents: Set<UUID> = []
    private var boardIntents: Set<UUID> = []

    private enum OutboundOperation: Hashable {
        case pending, preparation, reset
        case acknowledgement(CKRecord.ID)
        case conflict(CKRecord.ID)
        case intent(CKRecord.ID)
    }

    private var outbound: SyncOutboundWork {
        SyncOutboundWork(
            store: store, clipZone: zoneID, boardZone: boardZoneID,
            maxAssetBytes: maxAssetBytes)
    }

    private func failOutbound(_ operation: OutboundOperation) {
        outboundFailures.insert(operation)
        diagnostics?.record(
            "Sync", "Local sync work could not be completed; retry remains pending.")
        emit(.failed(.unknown))
    }

    /// Status sink for the UI (set by the factory). Receives `SyncStatus`
    /// values only — state and counts, never clip content.
    private let onStatus: (@Sendable (SyncStatus) -> Void)?

    /// Content-free trail of sync trouble for the Privacy Center's "Recent
    /// issues" (categories + fixed messages + counts, never clip content).
    /// Without it a fetched record that fails to decode or apply vanishes
    /// silently — the failure mode that makes sync bugs undiagnosable.
    private let diagnostics: DiagnosticLog?

    /// Persistence for the explicit pull's change tokens (`pollRemoteChanges`)
    /// — a SEPARATE blob from the engine's opaque state. nil disables
    /// persistence: the poll then re-scans once per process, still correct
    /// (upserts are idempotent), just less efficient.
    private let pollStateStore: SyncStateStore?

    private let stateEncoder = PropertyListEncoder()
    private let stateDecoder = PropertyListDecoder()

    public init(
        store: any SyncLocalStore,
        containerIdentifier: String,
        stateStore: SyncStateStore,
        maxAssetBytes: Int = ClipRecordMapper.defaultMaxAssetBytes,
        onStatus: (@Sendable (SyncStatus) -> Void)? = nil,
        diagnostics: DiagnosticLog? = nil,
        pollStateStore: SyncStateStore? = nil
    ) {
        self.store = store
        self.containerIdentifier = containerIdentifier
        self.stateStore = stateStore
        self.maxAssetBytes = maxAssetBytes
        self.onStatus = onStatus
        self.diagnostics = diagnostics
        self.pollStateStore = pollStateStore
    }

    // MARK: - SyncEngine boundary

    public func start() async throws {
        let generation = receiveGeneration
        isPaused = false
        // Staged CKAsset files are plaintext clip content; each is deleted the
        // moment its record is reported sent. Sweep the stragglers a crash or
        // a failed send left behind — age-gated, so files a not-yet-sent batch
        // still needs are untouched.
        ClipRecordMapper.sweepStagedAssets()
        try await completeIdentityReset()
        try await retryUploadIntents()
        guard generation == receiveGeneration else { throw CancellationError() }
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID)),
            .saveZone(CKRecordZone(zoneID: boardZoneID))
        ])
        do {
            try await reenqueuePendingWork(into: engine)
            try await reconcilePendingChanges(in: engine)
            outboundFailures.remove(.pending)
        } catch {
            failOutbound(.pending)
            throw error
        }
        guard generation == receiveGeneration else { throw CancellationError() }
        emit(.syncing)
        do {
            // A REAL server check, then the engine's own cycle. The engine's
            // `fetchChanges()` only fetches zones IT believes have news — a
            // belief fed exclusively by push (verified: an explicit
            // `FetchChangesOptions(scope: .zoneIDs)` is a filter over that same
            // list, and the engine logs "no zone IDs needing to be fetched" and
            // skips the server). On a host that receives no push — the macOS
            // menu-bar agent — that list is permanently empty and remote clips
            // never arrive. `pollRemoteChanges()` asks the server directly
            // (one tiny database-changes call when idle) and applies through
            // the same code path as the engine's fetch events.
            do { try await pollRemoteChanges() } catch {
                scheduleReceiveRecovery(after: error)
                throw error
            }
            guard generation == receiveGeneration else { throw CancellationError() }
            try await engine.fetchChanges()
            guard generation == receiveGeneration else { throw CancellationError() }
            try await engine.sendChanges()
            guard generation == receiveGeneration else { throw CancellationError() }
        } catch {
            guard generation == receiveGeneration, !(error is CancellationError) else {
                throw CancellationError()
            }
            emit(.failed(CloudKitSyncPolicy.interruption(for: error)))
            throw error
        }
        await emitCurrentStatus()
    }

    // MARK: - Explicit pull (hosts that receive no push)

    /// Actor-owned cache; ``SyncPollTokens`` handles persistence.
    private var pollTokens: SyncPollTokens?

    private func loadPollTokens() -> SyncPollTokens {
        if let pollTokens { return pollTokens }
        let loaded = SyncPollTokens.load(from: pollStateStore)
        pollTokens = loaded
        return loaded
    }

    private func savePollTokens(_ tokens: SyncPollTokens) throws {
        try tokens.save(to: pollStateStore)
        pollTokens = tokens
    }

    /// Asks the SERVER whether our zones changed, and pulls + applies what did.
    /// One `databaseChanges` round-trip when idle; zone pulls only when the
    /// server reports news. Fetched batches flow through `applyFetched` — the
    /// exact code path the engine's own push-fed fetches use — so the two
    /// delivery mechanisms can never disagree on semantics. Zone-not-found is
    /// first-run (sendChanges creates the zones) and skips silently; an expired
    /// token drops to a full re-scan, which the LWW upserts make idempotent.
    private func pollRemoteChanges() async throws {
        if let pollTask { return try await pollTask.value }
        let id = UUID()
        let task = Task { try await self.performPoll() }
        pollID = id
        pollTask = task
        defer {
            if pollID == id {
                pollTask = nil
                pollID = nil
            }
        }
        try await task.value
    }

    private func performPoll() async throws {
        let generation = receiveGeneration
        let healthRevision = receiveHealth.revision
        guard loadPollTokens().identityResetZones == nil else {
            throw SyncOutboundFailure.localWrite
        }
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let driver = SyncPullDriver(
            databasePage: { token in
                let page = try await database.databaseChanges(
                    since: SyncPollTokens.unarchive(token))
                return .init(
                    changedZones: Set(page.modifications.map { $0.zoneID.zoneName }),
                    deletedZones: Set(page.deletions.map { $0.zoneID.zoneName }),
                    token: try Self.archiveCheckpoint(page.changeToken), moreComing: page.moreComing
                )
            },
            zonePage: { zone, token in
                let id = CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
                let page = try await database.recordZoneChanges(
                    inZoneWith: id, since: SyncPollTokens.unarchive(token))
                let records = page.modificationResultsByID.values.map { result in
                    result.map(\.record).mapError { $0 as any Error }
                }
                return .init(
                    records: records, deletions: page.deletions.map(\.recordID),
                    token: try Self.archiveCheckpoint(page.changeToken), moreComing: page.moreComing
                )
            },
            apply: { [weak self] records, deletions in
                guard let self else { throw CancellationError() }
                try await self.applyPolled(
                    records: records, deletions: deletions, generation: generation)
            })
        do {
            let candidate = try await driver.pull(
                from: loadPollTokens(), zones: [zoneID.zoneName, boardZoneID.zoneName])
            guard generation == receiveGeneration else { throw CancellationError() }
            try savePollTokens(candidate)
            guard receiveHealth.recover(since: healthRevision) else {
                throw SyncReceiveFailure.interruptedByNewFailure
            }
        } catch {
            if generation == receiveGeneration, !(error is CancellationError) {
                receiveHealth.fail(error)
                emit(.failed(receiveHealth.failure ?? .unknown))
            }
            throw error
        }
    }

    private func scheduleReceiveRecovery(after error: any Error) {
        guard engine != nil, receiveRetryTask == nil, SyncReceiveRecovery.shouldRetry(error) else {
            return
        }
        let id = UUID()
        receiveRetryID = id
        receiveRetryTask = Task { [weak self] in
            let recovered = await SyncReceiveRecovery.run(after: error) { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.pollRemoteChanges()
            }
            await self?.finishReceiveRecovery(id: id, recovered: recovered)
        }
    }

    private func finishReceiveRecovery(id: UUID, recovered: Bool) async {
        guard receiveRetryID == id else { return }
        receiveRetryTask = nil
        receiveRetryID = nil
        if recovered { await emitCurrentStatus() }
    }

    private static func archiveCheckpoint(_ token: CKServerChangeToken) throws -> Data {
        guard let data = SyncPollTokens.archive(token) else {
            throw SyncReceiveFailure.checkpointEncoding
        }
        return data
    }

    private func applyPolled(
        records: [CKRecord], deletions: [CKRecord.ID], generation: Int
    ) async throws {
        guard generation == receiveGeneration else { throw CancellationError() }
        try await applyFetched(records: records, deletions: deletions)
    }

    public func stop() async {
        receiveGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        pollID = nil
        receiveRetryTask?.cancel()
        receiveRetryTask = nil
        receiveRetryID = nil
        // Dropping the engine ends its background sync; the persisted state
        // blob lets a later start() resume where we left off. Also breaks the
        // adapter ⇄ engine retain cycle (the engine holds this as its delegate).
        engine = nil
    }

    public func enqueue(_ items: [ClipItem]) async {
        let generation = receiveGeneration
        clipIntents.formUnion(items.map(\.id))
        do { try await retryUploadIntents() } catch { return }
        guard generation == receiveGeneration, loadPollTokens().identityResetZones == nil else {
            return
        }
        guard !isPaused, !outboundFailures.contains(.reset) else { return }
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        engine.state.add(pendingRecordZoneChanges: items.map { .saveRecord(recordID(for: $0.id)) })
    }

    func retryUploadIntents() async throws {
        for id in clipIntents {
            let operation = OutboundOperation.intent(recordID(for: id))
            do { try await store.markNeedsUpload(id: id) } catch {
                failOutbound(operation)
                throw error
            }
            clipIntents.remove(id)
            outboundFailures.remove(operation)
        }
        for id in boardIntents {
            let operation = OutboundOperation.intent(boardRecordID(for: id))
            do { try await store.markBoardNeedsUpload(id: id) } catch {
                failOutbound(operation)
                throw error
            }
            boardIntents.remove(id)
            outboundFailures.remove(operation)
        }
    }

    public func enqueueDeletion(ids: [UUID]) async {
        guard !isPaused, !outboundFailures.contains(.reset) else { return }
        let engine = ensureEngine()
        engine.state.add(
            pendingRecordZoneChanges: ids.map { .deleteRecord(recordID(for: $0)) })
    }

    public func enqueue(boards: [Pinboard]) async {
        let generation = receiveGeneration
        boardIntents.formUnion(boards.map(\.id))
        do { try await retryUploadIntents() } catch { return }
        guard generation == receiveGeneration, loadPollTokens().identityResetZones == nil else {
            return
        }
        guard !isPaused, !outboundFailures.contains(.reset) else { return }
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: boardZoneID))])
        engine.state.add(
            pendingRecordZoneChanges: boards.map { .saveRecord(boardRecordID(for: $0.id)) })
    }

    public func enqueueBoardDeletion(ids: [UUID]) async {
        guard !isPaused, !outboundFailures.contains(.reset) else { return }
        let engine = ensureEngine()
        engine.state.add(
            pendingRecordZoneChanges: ids.map { .deleteRecord(boardRecordID(for: $0)) })
    }

    func beginIdentityReset(zones: Set<String>) async throws {
        receiveGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        pollID = nil
        receiveRetryTask?.cancel()
        receiveRetryTask = nil
        receiveRetryID = nil
        var tokens = loadPollTokens()
        tokens.database = nil
        for zone in zones { tokens.zones[zone] = nil }
        tokens.identityResetZones = (tokens.identityResetZones ?? []).union(zones)
        pollTokens = tokens
        try await completeIdentityReset()
    }

    func completeIdentityReset() async throws {
        let generation = receiveGeneration
        var tokens = loadPollTokens()
        guard let zones = tokens.identityResetZones, !zones.isEmpty else { return }
        do {
            try tokens.save(to: pollStateStore)  // Durable intent before local identity writes.
            if zones.contains(zoneID.zoneName) { try await store.forgetAllSyncFields() }
            if zones.contains(boardZoneID.zoneName) { try await store.forgetAllBoardSyncFields() }
            guard generation == receiveGeneration else { throw CancellationError() }
            tokens.identityResetZones = nil
            try savePollTokens(tokens)
            outboundFailures.remove(.reset)
        } catch {
            failOutbound(.reset)
            throw error
        }
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
    func emitCurrentStatus() async {
        if isPaused {
            emit(.paused(.iCloudFull))
            return
        }
        if let receiveFailure = receiveHealth.failure {
            emit(.failed(receiveFailure))
            return
        }
        if loadPollTokens().identityResetZones != nil {
            emit(outboundFailures.contains(.reset) ? .failed(.unknown) : .syncing)
            return
        }
        if statePersistenceFailed {
            emit(.failed(.unknown))
            return
        }
        if pollTask != nil {
            emit(.syncing)
            return
        }
        do {
            let pending = try await outbound.pendingCount()
            outboundFailures.remove(.pending)
            if pending == 0 {
                outboundFailures = outboundFailures.filter {
                    switch $0 {
                    case .preparation, .acknowledgement, .conflict: return false
                    default: return true
                    }
                }
            }
            guard outboundFailures.isEmpty else {
                emit(.failed(.unknown))
                return
            }
            emit(pending > 0 ? .pending(pending) : .upToDate(at: Date()))
        } catch { failOutbound(.pending) }
    }

    /// Re-registers everything the local store still considers unsynced — used
    /// on a fresh start, after sign-in, and after a server zone reset.
    private func reenqueuePendingWork(
        into engine: CKSyncEngine, only recordIDs: Set<CKRecord.ID>? = nil
    ) async throws {
        let work = try await outbound.pending()
        guard self.engine === engine else { throw CancellationError() }
        let changes = work.changes(clipZoneID: zoneID, boardZoneID: boardZoneID)
        engine.state.add(
            pendingRecordZoneChanges: changes.filter { change in
                guard let recordIDs else { return true }
                switch change {
                case .saveRecord(let id), .deleteRecord(let id): return recordIDs.contains(id)
                @unknown default: return false
                }
            })
    }

    /// Drop pending `.saveRecord` changes the store no longer wants uploaded. A
    /// resumed engine state can carry stale saves (e.g. a record uploaded under
    /// a state the engine then lost track of) that no provider can build — the
    /// send queue would jam on empty batches forever. Deletions are left alone:
    /// their record names are tombstones tracked separately from the clip rows.
    private func reconcilePendingChanges(in engine: CKSyncEngine) async throws {
        let work = try await outbound.pending()
        guard self.engine === engine else { throw CancellationError() }
        let stale = work.staleSaveChanges(
            in: engine.state.pendingRecordZoneChanges,
            clipZoneID: zoneID,
            boardZoneID: boardZoneID)
        guard !stale.isEmpty else { return }
        engine.state.remove(pendingRecordZoneChanges: stale)
    }

}

// MARK: - CKSyncEngineDelegate

extension CKSyncEngineAdapter: CKSyncEngineDelegate {
    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, !outboundFailures.contains(.reset),
            loadPollTokens().identityResetZones == nil
        else { return nil }
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
        guard !pendingChanges.isEmpty else { return nil }

        // The record provider is synchronous, but our store is async: build
        // records up front, then hand the closure a plain dictionary lookup —
        // but ONLY the records this batch's pending changes actually
        // reference, so a large backlog is hydrated (and decrypted) one batch
        // at a time, never in full. CKRecord is not Sendable, so the
        // prefetched map crosses into the closure inside an unchecked box —
        // safe, as it is read-only.
        let saveIDs = pendingChanges.compactMap { change -> CKRecord.ID? in
            guard case .saveRecord(let id) = change else { return nil }
            return id
        }
        let built: [CKRecord.ID: CKRecord]
        do {
            built = try await outbound.prepare(saveIDs)
            guard engine === syncEngine else {
                for record in built.values { ClipRecordMapper.removeStagedAsset(for: record) }
                return nil
            }
            outboundFailures.remove(.preparation)
        } catch {
            failOutbound(.preparation)
            return nil  // Returning a batch with nil providers would drop real work.
        }
        let records = UncheckedSendableBox(built)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) {
            recordID in records.value[recordID]
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        switch event {
        case .stateUpdate(let event):
            do {
                try stateStore.save(stateEncoder.encode(event.stateSerialization))
                statePersistenceFailed = false
            } catch {
                statePersistenceFailed = true
                diagnostics?.record(
                    "Sync", "Sync state could not be persisted; recovery remains pending.")
                emit(.failed(.unknown))
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
                .saveZone(CKRecordZone(zoneID: boardZoneID))
            ])
            do {
                try await completeIdentityReset()
                try await reenqueuePendingWork(into: syncEngine)
            } catch { failOutbound(.pending) }
        case .signOut, .switchAccounts:
            // Old-account callbacks must not restore identities after reset.
            await stop()
            // Forget the old account's record identities; keep local history.
            do {
                try await beginIdentityReset(zones: [zoneID.zoneName, boardZoneID.zoneName])
                emit(.idle)
            } catch { failOutbound(.reset) }
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
        let zones = Set(
            [
                clipZoneReset ? zoneID.zoneName : nil,
                boardZoneReset ? boardZoneID.zoneName : nil
            ].compactMap { $0 })
        do { try await beginIdentityReset(zones: zones) } catch {
            failOutbound(.reset)
            return
        }
        syncEngine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID)),
            .saveZone(CKRecordZone(zoneID: boardZoneID))
        ])
        do { try await reenqueuePendingWork(into: syncEngine) } catch { failOutbound(.pending) }
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async {
        let generation = receiveGeneration
        do {
            try await applyFetched(
                records: event.modifications.map(\.record),
                deletions: event.deletions.map(\.recordID))
        } catch {
            guard generation == receiveGeneration, !(error is CancellationError) else { return }
            // The engine may persist its opaque fetch token regardless. The
            // independent poll checkpoint has NOT moved and can replay it.
            receiveHealth.fail(error)
            emit(.failed(receiveHealth.failure ?? .unknown))
            scheduleReceiveRecovery(after: error)
        }
    }

    /// Applies a batch of fetched changes to the local store — shared by the
    /// engine's event handler (push-fed fetches) and `pollRemoteChanges()` (the
    /// explicit pull for hosts that receive no push). Incomplete batches throw,
    /// retaining the poll checkpoint for replay; diagnostics contain counts
    /// only, never the failed records or underlying database error text.
    func applyFetched(records: [CKRecord], deletions: [CKRecord.ID]) async throws {
        var decodeFailures = 0
        var clips: [RemoteClipChange] = []
        var boards: [RemoteBoardChange] = []
        for record in records {
            if record.recordType == BoardRecordMapper.recordType {
                if let board = BoardRecordMapper.decode(record) {
                    boards.append(
                        RemoteBoardChange(
                            board: board,
                            systemFields: BoardRecordMapper.encodeSystemFields(record)))
                } else {
                    decodeFailures += 1
                }
                continue
            }
            guard let decoded = ClipRecordMapper.decode(record) else {
                decodeFailures += 1
                continue
            }
            // Membership rides the clip record, so it follows the same
            // last-writer-wins decision: a stale remote must not overwrite a
            // newer local board set. The store applies it only when the remote
            // won, which is the `applied == false` skip that used to live here.
            clips.append(
                RemoteClipChange(
                    item: decoded.item, content: decoded.content,
                    systemFields: ClipRecordMapper.encodeSystemFields(record),
                    boardIDs: Set(ClipRecordMapper.boardIDs(from: record))))
        }
        if decodeFailures > 0 {
            diagnostics?.record(
                "Sync",
                "Fetched \(records.count + deletions.count) changes; \(decodeFailures) failed to decode, 0 failed to apply."
            )
            throw SyncReceiveFailure.undecodable(decodeFailures)
        }
        let boardZone = boardZoneID.zoneName
        let deletionIDs = Dictionary(
            grouping: deletions, by: { $0.zoneID.zoneName == boardZone }
        )
        .mapValues { $0.map(\.recordName) }

        // One transaction for the page instead of two per record. Decode
        // failures are counted here because a record that cannot be decoded
        // never reaches the store at all.
        let summary: RemoteApplySummary
        do {
            summary = try await store.applyRemoteChanges(
                clips: clips, boards: boards,
                clipDeletions: deletionIDs[false] ?? [], boardDeletions: deletionIDs[true] ?? [])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let count = clips.count + boards.count + deletions.count
            diagnostics?.record(
                "Sync", "Fetched \(count) changes; 0 failed to decode, \(count) failed to apply.")
            throw SyncReceiveFailure.apply(count)
        }
        if summary.failed > 0 {
            diagnostics?.record(
                "Sync",
                "Fetched \(records.count + deletions.count) changes; 0 failed to decode, \(summary.failed) failed to apply."
            )
            throw SyncReceiveFailure.apply(summary.failed)
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine
    ) async {
        var acknowledged: Set<CKRecord.ID> = []
        for record in event.savedRecords {
            let operation = OutboundOperation.acknowledgement(record.recordID)
            do {
                try await outbound.acknowledge(record)
                acknowledged.insert(record.recordID)
                outboundFailures.remove(operation)
            } catch {
                failOutbound(operation)
                // Durable dirty row retries on the next explicit start. Do not
                // hot-loop successful cloud uploads against a failing local DB.
            }
        }
        for recordID in event.deletedRecordIDs {
            let operation = OutboundOperation.acknowledgement(recordID)
            do {
                try await outbound.acknowledgeDeletion(recordID)
                outboundFailures.remove(operation)
            } catch {
                failOutbound(operation)
                // Tombstone survives for the next explicit start.
            }
        }
        // A late successful acknowledgement can leave a newer local edit dirty.
        if !acknowledged.isEmpty {
            do { try await reenqueuePendingWork(into: syncEngine, only: acknowledged) } catch {
                failOutbound(.pending)
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
        switch CloudKitSyncPolicy.failedSaveRecovery(for: failure.error.code) {
        case .resolveConflict:
            let operation = OutboundOperation.conflict(recordID)
            do {
                guard let record = failure.error.serverRecord else {
                    throw SyncOutboundFailure.invalidRecord
                }
                let localWon = try await outbound.resolveConflict(record)
                outboundFailures.remove(operation)
                outboundFailures.remove(.acknowledgement(recordID))
                if localWon {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                }
            } catch {
                failOutbound(operation)
                // The durable row retries on the next explicit start, not an
                // unbounded cloud-write loop or a fabricated local-wins result.
            }
        case .recreateZone:
            // Recreate the failed record's own zone, then retry it.
            diagnostics?.record(
                "Sync",
                "Sync zone was missing (CKError \(failure.error.code.rawValue)); recreating and retrying."
            )
            syncEngine.state.add(
                pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .pauseForQuota:
            diagnostics?.record("Sync", "iCloud storage is full — uploads paused.")
            isPaused = true
            emit(.paused(.iCloudFull))
        case .deferToEngine:
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
