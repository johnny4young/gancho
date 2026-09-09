import Foundation
import GRDB

/// What the CloudKit adapter needs from the local store, expressed WITHOUT
/// importing CloudKit — so the boundary holds and the engine room stays
/// network-free. The adapter (in `GanchoSync`) is the only thing that turns
/// these into CKRecords.
///
/// Record identity = the clip's UUID string (one CKRecord per clip), so
/// remote upserts/deletions address rows by id, never by content hash.
/// One decoded remote clip change, ready to apply.
public struct RemoteClipChange: Sendable {
    public let item: ClipItem
    public let content: ClipContent?
    public let systemFields: Data
    public let boardIDs: Set<UUID>

    public init(item: ClipItem, content: ClipContent?, systemFields: Data, boardIDs: Set<UUID>) {
        self.item = item
        self.content = content
        self.systemFields = systemFields
        self.boardIDs = boardIDs
    }
}

/// One decoded remote board change.
public struct RemoteBoardChange: Sendable {
    public let board: Pinboard
    public let systemFields: Data

    public init(board: Pinboard, systemFields: Data) {
        self.board = board
        self.systemFields = systemFields
    }
}

/// What one page of remote changes did. Counts only — never content.
public struct RemoteApplySummary: Sendable, Equatable {
    /// Remote changes that won and were written.
    public var applied = 0
    /// Remote changes a newer local row beat. Normal, not a failure.
    public var skippedAsStale = 0
    /// Changes whose write threw and was rolled back on its own.
    public var failed = 0

    public init(applied: Int = 0, skippedAsStale: Int = 0, failed: Int = 0) {
        self.applied = applied
        self.skippedAsStale = skippedAsStale
        self.failed = failed
    }
}

public protocol SyncLocalStore: Sendable {
    /// Clips that still need uploading: never synced (no system fields) or
    /// edited since last upload.
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)]
    /// How many clips still need uploading — a bare COUNT, so status
    /// refreshes never hydrate (and decrypt) content just to show a number.
    func pendingUploadCount() async throws -> Int
    /// The ids of clips still needing upload, oldest first — content-free,
    /// for callers that only register record ids with the engine.
    func pendingUploadIDs() async throws -> [UUID]
    /// One clip still needing upload, with its content — nil when the clip
    /// is gone or already synced. Lets the batch provider hydrate exactly
    /// the records a send batch references instead of the whole backlog.
    func pendingUpload(id: UUID) async throws -> (item: ClipItem, content: ClipContent?)?
    /// Record IDs of deletions waiting to propagate (tombstones).
    func pendingDeletionRecordIDs() async throws -> [String]

    /// After a successful upload: store the CKRecord system fields and clear
    /// the dirty flag.
    func markUploaded(id: UUID, systemFields: Data) async throws
    /// Archived CKRecord system fields for a clip (nil = never synced).
    func systemFields(for id: UUID) async throws -> Data?
    /// Flags a locally-edited clip for re-upload.
    func markNeedsUpload(id: UUID) async throws

    /// Applies a remote change, last-writer-wins by `updatedAt`: a remote
    /// older than the local row is ignored (but its system fields are still
    /// stored so we don't fight it). Never flips `needsUpload`. Returns
    /// whether the remote won — when it did not, the caller must not apply
    /// any follow-up state from the record (e.g. board membership) either.
    @discardableResult
    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    ) async throws -> Bool
    /// Applies a whole fetched page in ONE transaction.
    ///
    /// The apply path used to open two transactions per record — the upsert,
    /// then the board membership that rides it — so a page of several hundred
    /// records paid several hundred WAL commits for one page of changes.
    ///
    /// Each change still gets its own savepoint inside that transaction, so a
    /// record that throws rolls back alone and the rest of the page still
    /// commits. That is deliberate rather than incidental: `applyFetched` does
    /// not throw and the change token advances regardless, so a page that
    /// failed as a unit would lose every change in it with no retry. One bad
    /// record must not take the page down with it.
    func applyRemoteChanges(
        clips: [RemoteClipChange], boards: [RemoteBoardChange],
        clipDeletions: [String], boardDeletions: [String]
    ) async throws -> RemoteApplySummary

    /// Applies a remote deletion by record id.
    func applyRemoteDeletion(recordID: String) async throws
    /// Forgets a tombstone once its deletion has propagated.
    func clearTombstone(recordID: String) async throws

    /// Drops every clip's saved CloudKit identity and re-flags all rows for
    /// upload. Called when the server zone is reset/deleted or the iCloud
    /// account changes: the old record identities are gone, so the next sync
    /// must re-upload from scratch. Local clips are kept — only the sync
    /// linkage is forgotten.
    func forgetAllSyncFields() async throws

    /// The board ids a clip belongs to — read when building the clip's sync
    /// record so membership rides the clip (the boards extension implements it).
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID>
    /// Rebuilds a clip's board membership from a synced record, seeding a
    /// placeholder board for any id whose metadata hasn't synced yet.
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws

    // Board metadata sync — the board table's mirror of the clip methods above,
    // so a board's name/glyph propagate. Membership rides the clip record.
    func pendingBoardUploads() async throws -> [Pinboard]
    func markBoardNeedsUpload(id: UUID) async throws
    func markBoardUploaded(id: UUID, systemFields: Data) async throws
    func boardSystemFields(for id: UUID) async throws -> Data?
    func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws
    func forgetAllBoardSyncFields() async throws

    // Board deletion sync — the board zone's tombstones, mirroring the clip
    // deletion methods so a deleted board disappears on the user's other devices.
    func pendingBoardDeletionRecordIDs() async throws -> [String]
    func applyRemoteBoardDeletion(recordID: String) async throws
    func clearBoardTombstone(recordID: String) async throws
}

extension SyncLocalStore {
    /// Falls back to the per-record path.
    ///
    /// The batching is an optimization of HOW a page is written, not of what it
    /// means, so a conformer that has no transaction to share — every test
    /// double, and any future non-GRDB store — gets the same result by
    /// composing the single-record requirements. `GRDBClipboardStore` overrides
    /// it with the one-transaction version.
    public func applyRemoteChanges(
        clips: [RemoteClipChange], boards: [RemoteBoardChange],
        clipDeletions: [String], boardDeletions: [String]
    ) async throws -> RemoteApplySummary {
        var summary = RemoteApplySummary()
        // Boards BEFORE clips — see `applyRemoteChanges` on the GRDB store for
        // why the order is load-bearing rather than cosmetic.
        for board in boards {
            do {
                try await applyRemoteBoardUpsert(board.board, systemFields: board.systemFields)
                summary.applied += 1
            } catch {
                summary.failed += 1
            }
        }
        for change in clips {
            do {
                let applied = try await applyRemoteUpsert(
                    change.item, content: change.content, systemFields: change.systemFields)
                if applied {
                    try await setBoardMembership(
                        clipID: change.item.id, boardIDs: change.boardIDs)
                }
                summary.applied += applied ? 1 : 0
                summary.skippedAsStale += applied ? 0 : 1
            } catch {
                summary.failed += 1
            }
        }
        for recordID in clipDeletions {
            do {
                try await applyRemoteDeletion(recordID: recordID)
                summary.applied += 1
            } catch {
                summary.failed += 1
            }
        }
        for recordID in boardDeletions {
            do {
                try await applyRemoteBoardDeletion(recordID: recordID)
                summary.applied += 1
            } catch {
                summary.failed += 1
            }
        }
        return summary
    }
}

extension GRDBClipboardStore: SyncLocalStore {
    public func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] {
        let rows = try await writer.read { db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT * FROM clip
                    WHERE syncSystemFields IS NULL OR needsUpload = 1
                    ORDER BY createdAt ASC
                    """)
        }
        var result: [(ClipItem, ClipContent?)] = []
        for row in rows {
            result.append((row.item, try await content(for: row.item.id)))
        }
        return result
    }

    public func pendingUploadCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM clip
                    WHERE syncSystemFields IS NULL OR needsUpload = 1
                    """) ?? 0
        }
    }

    public func pendingUploadIDs() async throws -> [UUID] {
        let names = try await writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM clip
                    WHERE syncSystemFields IS NULL OR needsUpload = 1
                    ORDER BY createdAt ASC
                    """)
        }
        return names.compactMap { UUID(uuidString: $0) }
    }

    public func pendingUpload(id: UUID) async throws -> (item: ClipItem, content: ClipContent?)? {
        let row = try await writer.read { db in
            try ClipRow.fetchOne(
                db,
                sql: """
                    SELECT * FROM clip
                    WHERE id = ? AND (syncSystemFields IS NULL OR needsUpload = 1)
                    """,
                arguments: [id.uuidString])
        }
        guard let row else { return nil }
        return (row.item, try await content(for: row.item.id))
    }

    public func pendingDeletionRecordIDs() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT recordID FROM sync_tombstone")
        }
    }

    public func markUploaded(id: UUID, systemFields: Data) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
                arguments: [systemFields, id.uuidString])
        }
    }

    public func systemFields(for id: UUID) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT syncSystemFields FROM clip WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    public func markNeedsUpload(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET needsUpload = 1 WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    /// Applies one remote change in its own transaction.
    ///
    /// The single-record entry point; `applyRemoteChanges` is the one the sync
    /// adapter uses for a whole page.
    @discardableResult
    public func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    ) async throws -> Bool {
        let finalRow = try preparedRow(for: item, content: content)
        return try await writer.write { db in
            try applyPreparedUpsert(
                finalRow, item: item, content: content, systemFields: systemFields, in: db)
        }
    }

    /// Builds the row a remote change will write, doing its blob I/O here so
    /// the transaction that follows holds no file handles.
    func preparedRow(for item: ClipItem, content: ClipContent?) throws -> ClipRow {
        var row = ClipRow(item: item)
        switch content {
        case .text(let text):
            row.contentText = text
        case .binary(let data, let typeIdentifier):
            row.contentBlobHash = try blobsForMaintenance.write(data)
            row.contentTypeIdentifier = typeIdentifier
        case .fileReferences(let paths):
            row.contentText = paths.joined(separator: "\n")
            row.contentTypeIdentifier = "public.file-url"
        case nil:
            break
        }
        return row
    }

    // swiftlint:disable function_body_length
    /// The upsert itself, against an open transaction.
    ///
    /// Split from the async entry point so a page of remote changes can run
    /// through one transaction instead of one per record, without the two
    /// paths drifting apart on last-writer-wins or on which columns travel.
    /// Blob writes stay OUTSIDE, in the caller: file I/O has no business
    /// inside a write transaction, and a blob written for a change that then
    /// rolls back is inert content-addressed bytes the orphan sweep reclaims.
    func applyPreparedUpsert(
        _ finalRow: ClipRow, item: ClipItem, content: ClipContent?, systemFields: Data,
        in db: Database
    ) throws -> Bool {
        // swiftlint:enable function_body_length
        if let localUpdatedAt = try Date.fetchOne(
            db, sql: "SELECT updatedAt FROM clip WHERE id = ?",
            arguments: [item.id.uuidString])
        {
            let localContentText = try String.fetchOne(
                db, sql: "SELECT contentText FROM clip WHERE id = ?",
                arguments: [item.id.uuidString])
            // Last-writer-wins: skip if the local copy is newer, but still
            // record the remote's system fields so we stop re-sending ours.
            if localUpdatedAt > item.updatedAt {
                try db.execute(
                    sql: "UPDATE clip SET syncSystemFields = ? WHERE id = ?",
                    arguments: [systemFields, item.id.uuidString])
                return false
            }
            // The remote won over an existing row: update ONLY the columns
            // the record actually syncs. Local-only curation — isSnippet,
            // isArchived, keyword, uses, sortIndex — never travels, so a
            // whole-row upsert would silently reset it (demoting a
            // snippet, which retention would then purge).
            try db.execute(
                sql: """
                    UPDATE clip SET
                        createdAt = ?, updatedAt = ?, lastUsedAt = ?, kind = ?,
                        title = ?, preview = ?, contentHash = ?,
                        sourceAppBundleID = ?, sourceDeviceName = ?,
                        isPinned = ?, isSensitive = ?, expiresAt = ?, tags = ?,
                        syncSystemFields = ?, needsUpload = 0
                    WHERE id = ?
                    """,
                arguments: [
                    finalRow.createdAt, finalRow.updatedAt, finalRow.lastUsedAt,
                    finalRow.kind, finalRow.title, finalRow.preview,
                    finalRow.contentHash, finalRow.sourceAppBundleID,
                    finalRow.sourceDeviceName, finalRow.isPinned,
                    finalRow.isSensitive, finalRow.expiresAt, finalRow.tags,
                    systemFields, item.id.uuidString
                ])
            // Content columns move only when the remote carries content —
            // nil (an asset over the size cap, or an undecodable payload)
            // must not blank local content. A binary payload keeps
            // contentText: for image clips it holds locally attached OCR
            // text, which the record never syncs.
            switch content {
            case .text, .fileReferences:
                try db.execute(
                    sql: """
                        UPDATE clip SET contentText = ?, contentBlobHash = NULL,
                            contentTypeIdentifier = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        finalRow.contentText, finalRow.contentTypeIdentifier,
                        item.id.uuidString
                    ])
                if case .text = content, localContentText != finalRow.contentText {
                    try db.execute(
                        sql: "DELETE FROM clip_embedding WHERE clipID = ?",
                        arguments: [item.id.uuidString])
                }
            case .binary:
                try db.execute(
                    sql: """
                        UPDATE clip SET contentBlobHash = ?, contentTypeIdentifier = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        finalRow.contentBlobHash, finalRow.contentTypeIdentifier,
                        item.id.uuidString
                    ])
            case nil:
                break
            }
            return true
        }
        // A new row — unless we deleted this record locally and its
        // tombstone is still waiting to propagate: inserting would
        // resurrect the deletion (the pending CK delete wins instead).
        let tombstoned =
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS (SELECT 1 FROM sync_tombstone WHERE recordID = ?)",
                arguments: [item.id.uuidString]) ?? false
        if tombstoned { return false }
        try finalRow.insert(db)
        try db.execute(
            sql: "UPDATE clip SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
            arguments: [systemFields, item.id.uuidString])
        return true
    }

    public func applyRemoteChanges(
        clips: [RemoteClipChange], boards: [RemoteBoardChange],
        clipDeletions: [String], boardDeletions: [String]
    ) async throws -> RemoteApplySummary {
        // Blobs first, outside the transaction: file I/O has no business
        // holding a write lock, and a blob written for a change that then rolls
        // back is inert content-addressed bytes the orphan sweep reclaims.
        var prepared: [(change: RemoteClipChange, row: ClipRow)] = []
        prepared.reserveCapacity(clips.count)
        var summary = RemoteApplySummary()
        for change in clips {
            do {
                prepared.append(
                    (change, try preparedRow(for: change.item, content: change.content)))
            } catch {
                summary.failed += 1
            }
        }

        let staged = prepared
        let counted = summary
        return try await writer.write { db in
            var summary = counted
            // Boards FIRST. A clip's membership creates a placeholder board for
            // any id it does not find locally, stamped `createdAt = now` and
            // `isSystem = 0`. The board upsert that follows deliberately leaves
            // both columns alone — `isSystem` so a device's own Favorites stays
            // a system board — so a board arriving in the SAME page as a clip
            // that references it would keep the placeholder's values forever.
            // Both are load-bearing: `pinboards()` orders by
            // `isSystem DESC, sortIndex ASC, createdAt ASC`, and
            // `applyRemoteBoardDeletion` refuses to delete a system board, so a
            // system board demoted to a placeholder also loses that protection.
            // Applying boards first makes the membership INSERT OR IGNORE a
            // no-op for them, and placeholders stay what they are for: boards
            // this page genuinely does not carry.
            applyRemoteBoards(boards, into: &summary, in: db)
            applyStagedClips(staged, into: &summary, in: db)
            applyRemoteDeletions(
                clips: clipDeletions, boards: boardDeletions, into: &summary, in: db)
            return summary
        }
    }

    /// The clip half of a page. Each change gets its own savepoint.
    private func applyStagedClips(
        _ staged: [(change: RemoteClipChange, row: ClipRow)],
        into summary: inout RemoteApplySummary, in db: Database
    ) {
        for (change, row) in staged {
            // A savepoint per change: one that throws rolls back alone and the
            // page still commits around it.
            var applied = false
            do {
                try db.inSavepoint {
                    applied = try applyPreparedUpsert(
                        row, item: change.item, content: change.content,
                        systemFields: change.systemFields, in: db)
                    return .commit
                }
                summary.applied += applied ? 1 : 0
                summary.skippedAsStale += applied ? 0 : 1
            } catch {
                summary.failed += 1
                continue
            }
            // Membership rides the clip record, so it follows the same
            // last-writer-wins verdict — but in its OWN savepoint. Rolling the
            // clip back because its membership failed would lose a clip that
            // applied cleanly, where the previous per-record code kept it and
            // only lost the membership. This keeps that outcome and stops it
            // being silent: the old `try?` swallowed it whole.
            guard applied else { continue }
            do {
                try db.inSavepoint {
                    try setBoardMembership(
                        clipID: change.item.id, boardIDs: change.boardIDs, in: db)
                    return .commit
                }
            } catch {
                summary.failed += 1
            }
        }
    }

    private func applyRemoteBoards(
        _ boards: [RemoteBoardChange], into summary: inout RemoteApplySummary, in db: Database
    ) {
        for board in boards {
            do {
                try db.inSavepoint {
                    try applyRemoteBoardUpsert(
                        board.board, systemFields: board.systemFields, in: db)
                    summary.applied += 1
                    return .commit
                }
            } catch {
                summary.failed += 1
            }
        }
    }

    private func applyRemoteDeletions(
        clips: [String], boards: [String], into summary: inout RemoteApplySummary, in db: Database
    ) {
        for recordID in clips {
            do {
                try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [recordID])
                summary.applied += 1
            } catch {
                summary.failed += 1
            }
        }
        for recordID in boards {
            // A savepoint because this one is TWO statements: memberships, then
            // the board. Without it a throw on the second commits the first,
            // leaving the board present with its memberships already gone —
            // a partial change, which is exactly what the per-change savepoint
            // contract in this function exists to prevent.
            do {
                try db.inSavepoint {
                    try applyRemoteBoardDeletion(recordID: recordID, in: db)
                    return .commit
                }
                summary.applied += 1
            } catch {
                summary.failed += 1
            }
        }
    }

    public func applyRemoteDeletion(recordID: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [recordID])
        }
    }

    public func clearTombstone(recordID: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM sync_tombstone WHERE recordID = ?", arguments: [recordID])
        }
    }

    public func forgetAllSyncFields() async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE clip SET syncSystemFields = NULL, needsUpload = 1")
        }
    }

    // MARK: Board metadata sync

    public func pendingBoardUploads() async throws -> [Pinboard] {
        try await writer.read { db in
            try PinboardRow.filter(sql: "needsUpload = 1").fetchAll(db).map(\.board)
        }
    }

    public func markBoardNeedsUpload(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET needsUpload = 1 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func markBoardUploaded(id: UUID, systemFields: Data) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
                arguments: [systemFields, id.uuidString])
        }
    }

    public func boardSystemFields(for id: UUID) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT syncSystemFields FROM pinboard WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    public func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws {
        try await writer.write { db in
            try applyRemoteBoardUpsert(board, systemFields: systemFields, in: db)
        }
    }

    /// Board upsert against an open transaction, so a page shares one.
    func applyRemoteBoardUpsert(
        _ board: Pinboard, systemFields: Data, in db: Database
    ) throws {
        // Upsert metadata WITHOUT flipping needsUpload (remote-driven). isSystem
        // is left untouched so a device's local Favorites stays a system board.
        try db.execute(
            sql: """
                INSERT INTO pinboard
                    (id, name, sfSymbol, sortIndex, createdAt, isSystem, colorHex, emoji,
                     syncSystemFields, needsUpload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, sfSymbol = excluded.sfSymbol,
                    sortIndex = excluded.sortIndex,
                    colorHex = excluded.colorHex, emoji = excluded.emoji,
                    syncSystemFields = excluded.syncSystemFields, needsUpload = 0
                """,
            arguments: [
                board.id.uuidString, board.name, board.sfSymbol, board.sortIndex,
                board.createdAt, board.isSystem, board.colorHex, board.emoji, systemFields
            ])
    }

    public func forgetAllBoardSyncFields() async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE pinboard SET syncSystemFields = NULL, needsUpload = 1")
        }
    }

    /// Records a deletion as a tombstone AND removes the row — call this
    /// instead of `delete(id:)` when sync is active so the deletion can
    /// propagate before the row is forgotten.
    public func deleteForSync(id: UUID, now: Date = .now) async throws {
        let blobHash = try await writer.write { db -> String? in
            let hash = try ClipRow
                .filter(key: id.uuidString)
                .fetchOne(db)?.contentBlobHash
            try db.execute(
                sql:
                    "INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) VALUES (?, ?)",
                arguments: [id.uuidString, now])
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [id.uuidString])
            return hash
        }
        // Post-commit maintenance, and non-throwing on purpose: see
        // `removeBlobIfOrphaned`. The tombstone and the row removal are already
        // durable by this point, so a failure here must not be reported as a
        // failed deletion — the caller would then skip propagating a removal
        // that already happened locally.
        await removeBlobIfOrphaned(blobHash)
    }

    /// How many clips have been uploaded to iCloud (carry stored system
    /// fields). Drives the Privacy Center "Items synchronized" count.
    public func syncedCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM clip WHERE syncSystemFields IS NOT NULL") ?? 0
        }
    }
}
