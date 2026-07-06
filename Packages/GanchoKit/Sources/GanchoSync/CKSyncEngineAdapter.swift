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
        isPaused = false
        // Staged CKAsset files are plaintext clip content; each is deleted the
        // moment its record is reported sent. Sweep the stragglers a crash or
        // a failed send left behind — age-gated, so files a not-yet-sent batch
        // still needs are untouched.
        ClipRecordMapper.sweepStagedAssets()
        let engine = ensureEngine()
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID)),
            .saveZone(CKRecordZone(zoneID: boardZoneID)),
        ])
        await reenqueuePendingWork(into: engine)
        await reconcilePendingChanges(in: engine)
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
            try await pollRemoteChanges()
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            emit(.failed(Self.interruption(error)))
            throw error
        }
        await emitCurrentStatus()
    }

    /// True when a change fetch failed only because the zone doesn't exist yet
    /// (fresh account / first launch) — including inside a partial failure.
    /// Internal (not private) so the unit tests can pin the classification.
    static func isMissingZone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .zoneNotFound, .userDeletedZone:
            return true
        case .partialFailure:
            let partial = ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError }
            return partial?.allSatisfy {
                $0.code == .zoneNotFound || $0.code == .userDeletedZone
            } ?? false
        default:
            return false
        }
    }

    // MARK: - Explicit pull (hosts that receive no push)

    /// Change tokens for the explicit pull, persisted SEPARATELY from the
    /// engine's opaque state blob (piggybacking on it would corrupt the
    /// engine's serialization). Losing this file is harmless — the next poll
    /// re-scans the zones and the upserts are idempotent (last-writer-wins).
    private struct PollTokens: Codable {
        var database: Data?
        var zones: [String: Data] = [:]
    }

    private var pollTokens: PollTokens?

    private func loadPollTokens() -> PollTokens {
        if let pollTokens { return pollTokens }
        let loaded =
            pollStateStore?.load().flatMap {
                try? PropertyListDecoder().decode(PollTokens.self, from: $0)
            }
            ?? PollTokens()
        pollTokens = loaded
        return loaded
    }

    private func savePollTokens(_ tokens: PollTokens) {
        pollTokens = tokens
        if let data = try? PropertyListEncoder().encode(tokens) {
            pollStateStore?.save(data)
        }
    }

    private static func archive(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func unarchive(_ data: Data?) -> CKServerChangeToken? {
        data.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
    }

    /// Asks the SERVER whether our zones changed, and pulls + applies what did.
    /// One `databaseChanges` round-trip when idle; zone pulls only when the
    /// server reports news. Fetched batches flow through `applyFetched` — the
    /// exact code path the engine's own push-fed fetches use — so the two
    /// delivery mechanisms can never disagree on semantics. Zone-not-found is
    /// first-run (sendChanges creates the zones) and skips silently; an expired
    /// token drops to a full re-scan, which the LWW upserts make idempotent.
    private func pollRemoteChanges() async throws {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        var tokens = loadPollTokens()
        var changedZones: Set<CKRecordZone.ID> = []
        do {
            var token = Self.unarchive(tokens.database)
            var moreComing = true
            while moreComing {
                let page = try await database.databaseChanges(since: token)
                for modification in page.modifications {
                    changedZones.insert(modification.zoneID)
                }
                for deletion in page.deletions {
                    // Zone gone server-side: our per-zone token is meaningless.
                    // The engine's own machinery recreates the zone on demand.
                    tokens.zones[deletion.zoneID.zoneName] = nil
                }
                token = page.changeToken
                moreComing = page.moreComing
            }
            // The loop always runs at least once and every page carries a
            // token, so `token` is non-nil here.
            if let token { tokens.database = Self.archive(token) }
        } catch let error as CKError where error.code == .changeTokenExpired {
            // Stale database token: forget everything and re-scan next cycle.
            savePollTokens(PollTokens())
            return
        }
        for zone in [zoneID, boardZoneID] where changedZones.contains(zone) {
            do {
                let token = try await fetchZoneChanges(
                    from: database, in: zone,
                    since: Self.unarchive(tokens.zones[zone.zoneName]))
                tokens.zones[zone.zoneName] = token.flatMap(Self.archive)
            } catch let error as CKError where error.code == .changeTokenExpired {
                // The database token was already advanced by the time the
                // per-zone token proved stale, so "try again next cycle" would
                // NOT see this zone as changed again. Re-scan the zone now
                // from nil and persist the fresh zone token from that pass.
                do {
                    let token = try await fetchZoneChanges(from: database, in: zone, since: nil)
                    tokens.zones[zone.zoneName] = token.flatMap(Self.archive)
                } catch {
                    guard Self.isMissingZone(error) else { throw error }
                }
            } catch {
                guard Self.isMissingZone(error) else { throw error }
            }
        }
        savePollTokens(tokens)
    }

    private func fetchZoneChanges(
        from database: CKDatabase,
        in zone: CKRecordZone.ID,
        since startingToken: CKServerChangeToken?
    ) async throws -> CKServerChangeToken? {
        var token = startingToken
        var moreComing = true
        while moreComing {
            let page = try await database.recordZoneChanges(inZoneWith: zone, since: token)
            let records = page.modificationResultsByID.values.compactMap {
                try? $0.get().record
            }
            await applyFetched(records: records, deletions: page.deletions.map(\.recordID))
            token = page.changeToken
            moreComing = page.moreComing
        }
        return token
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
        let uploads = (try? await store.pendingUploadCount()) ?? 0
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
        if let pending = try? await store.pendingUploadIDs() {
            engine.state.add(
                pendingRecordZoneChanges: pending.map { .saveRecord(recordID(for: $0)) })
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
            ((try? await store.pendingUploadIDs()) ?? []).map { recordID(for: $0) })
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
        var boardsByID: [UUID: Pinboard] = [:]
        if saveIDs.contains(where: { $0.zoneID.zoneName == boardZoneID.zoneName }),
            let pendingBoards = try? await store.pendingBoardUploads()
        {
            for board in pendingBoards { boardsByID[board.id] = board }
        }
        var built: [CKRecord.ID: CKRecord] = [:]
        for changeID in saveIDs {
            guard let id = UUID(uuidString: changeID.recordName) else { continue }
            if changeID.zoneID.zoneName == boardZoneID.zoneName {
                guard let board = boardsByID[id] else { continue }
                let systemFields = (try? await store.boardSystemFields(for: id)) ?? nil
                if let record = BoardRecordMapper.record(
                    for: board, systemFields: systemFields, zoneID: boardZoneID)
                {
                    built[changeID] = record
                }
            } else if changeID.zoneID.zoneName == zoneID.zoneName {
                guard let entry = (try? await store.pendingUpload(id: id)) ?? nil else {
                    continue
                }
                let systemFields = (try? await store.systemFields(for: id)) ?? nil
                let boardIDs = (try? await store.boardIDs(forClip: id)) ?? []
                if let record = ClipRecordMapper.record(
                    for: entry.item, content: entry.content, systemFields: systemFields,
                    zoneID: zoneID, maxAssetBytes: maxAssetBytes, boardIDs: Array(boardIDs))
                {
                    built[changeID] = record
                }
            }
        }
        // A pending save with no buildable record is DROPPED by CKSyncEngine
        // when the provider returns nil — count it so the loss is visible
        // ("Recent issues"), not silent. `reenqueuePendingWork` re-adds any row
        // the store still flags on the next cycle.
        let missing = saveIDs.count(where: { built[$0] == nil })
        if missing > 0 {
            diagnostics?.record(
                "Sync",
                "\(missing) pending upload(s) had no sendable local row; retrying next cycle.")
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
        await applyFetched(
            records: event.modifications.map(\.record),
            deletions: event.deletions.map(\.recordID))
    }

    /// Applies a batch of fetched changes to the local store — shared by the
    /// engine's event handler (push-fed fetches) and `pollRemoteChanges()` (the
    /// explicit pull for hosts that receive no push). Counts the records the
    /// batch LOSES: a fetched change that fails to decode or apply used to
    /// vanish without a trace, which is exactly what makes "device A never sees
    /// device B's clips" undiagnosable. Counts only, never content.
    func applyFetched(records: [CKRecord], deletions: [CKRecord.ID]) async {
        var decodeFailures = 0
        var applyFailures = 0
        for record in records {
            if record.recordType == BoardRecordMapper.recordType {
                if let board = BoardRecordMapper.decode(record) {
                    do {
                        try await store.applyRemoteBoardUpsert(
                            board, systemFields: BoardRecordMapper.encodeSystemFields(record))
                    } catch { applyFailures += 1 }
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
            // newer local board set. `applied == false` is the NORMAL stale-remote
            // skip; only a thrown store error counts as a failure.
            do {
                let applied = try await store.applyRemoteUpsert(
                    decoded.item, content: decoded.content,
                    systemFields: ClipRecordMapper.encodeSystemFields(record))
                if applied {
                    try? await store.setBoardMembership(
                        clipID: decoded.item.id,
                        boardIDs: Set(ClipRecordMapper.boardIDs(from: record)))
                }
            } catch { applyFailures += 1 }
        }
        for recordID in deletions {
            do {
                if recordID.zoneID.zoneName == boardZoneID.zoneName {
                    try await store.applyRemoteBoardDeletion(recordID: recordID.recordName)
                } else {
                    try await store.applyRemoteDeletion(recordID: recordID.recordName)
                }
            } catch { applyFailures += 1 }
        }
        if decodeFailures + applyFailures > 0 {
            diagnostics?.record(
                "Sync",
                "Fetched \(records.count + deletions.count) changes; "
                    + "\(decodeFailures) failed to decode, \(applyFailures) failed to apply.")
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
                // The upload is done — CloudKit no longer reads the staged
                // asset file, so its plaintext copy must go now. Failed saves
                // are NOT cleaned here: a retry rebuilds the batch (and stages
                // a fresh file), and the start() sweep reaps the leftovers.
                ClipRecordMapper.removeStagedAsset(for: record)
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
                } else {
                    // The LOCAL copy won the conflict (e.g. an enrichment title
                    // written moments after the first upload, racing that
                    // upload's system-fields save). CKSyncEngine drops a failed
                    // pending change — the delegate must RE-QUEUE it after
                    // resolving, or the local edit only retries at the next
                    // start()'s reenqueue (a silent, laggy hole for the second
                    // save of a fresh record). The apply above stored the
                    // server's system fields, so the retry builds a record with
                    // a current change tag and succeeds.
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                }
            }
        case .zoneNotFound, .userDeletedZone:
            // Recreate the failed record's own zone, then retry it.
            diagnostics?.record(
                "Sync",
                "Sync zone was missing (CKError \(failure.error.code.rawValue)); recreating and retrying."
            )
            syncEngine.state.add(
                pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .quotaExceeded:
            diagnostics?.record("Sync", "iCloud storage is full — uploads paused.")
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
