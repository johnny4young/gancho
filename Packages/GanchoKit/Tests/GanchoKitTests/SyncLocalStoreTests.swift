import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("SyncLocalStore bridge — uploads, remote apply, tombstones")
struct SyncLocalStoreTests {
    private func makeStore(
        blobDir: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-\(UUID().uuidString)")
    ) throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: blobDir))
        try store.migrate()
        return store
    }

    @Test("New clips are pending upload until marked, then drop out")
    func pendingThenUploaded() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hi", contentHash: "h")
        try await store.insert(item, content: .text("hi"))

        var pending = try await store.pendingUploads()
        #expect(pending.map(\.item.id) == [item.id])
        #expect(pending.first?.content == .text("hi"))

        try await store.markUploaded(id: item.id, systemFields: Data([1, 2, 3]))
        pending = try await store.pendingUploads()
        #expect(pending.isEmpty)
        #expect(try await store.systemFields(for: item.id) == Data([1, 2, 3]))
    }

    @Test("A local edit re-flags the clip for upload")
    func editReflags() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "v1", contentHash: "h")
        try await store.insert(item, content: .text("v1"))
        try await store.markUploaded(id: item.id, systemFields: Data([9]))
        #expect(try await store.pendingUploads().isEmpty)

        try await store.markNeedsUpload(id: item.id)
        #expect(try await store.pendingUploads().map(\.item.id) == [item.id])
    }

    @Test("Remote upsert applies a newer remote, ignores an older one")
    func remoteUpsertLastWriterWins() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let local = ClipItem(
            updatedAt: base, preview: "local", contentHash: "h", isPinned: false)
        try await store.insert(local, content: .text("local"))

        // Older remote → ignored, but its system fields are recorded. The
        // returned Bool tells the sync adapter to skip follow-up state from
        // the record too (board membership).
        let older = ClipItem(
            id: local.id, updatedAt: base.addingTimeInterval(-60), preview: "older remote",
            contentHash: "h")
        let olderApplied = try await store.applyRemoteUpsert(
            older, content: .text("older"), systemFields: Data([7]))
        #expect(!olderApplied, "a stale remote must report it was skipped")
        #expect(try await store.items().first?.preview == "local")
        #expect(try await store.content(for: local.id) == .text("local"))
        #expect(try await store.systemFields(for: local.id) == Data([7]))

        // Newer remote → wins.
        let newer = ClipItem(
            id: local.id, updatedAt: base.addingTimeInterval(60), preview: "newer remote",
            contentHash: "h")
        let newerApplied = try await store.applyRemoteUpsert(
            newer, content: .text("newer"), systemFields: Data([8]))
        #expect(newerApplied)
        #expect(try await store.items().first?.preview == "newer remote")
        #expect(try await store.content(for: local.id) == .text("newer"))
    }

    @Test("An enrichment-title update (v2) applies over the untitled first sync (v1)")
    func enrichmentFruitSecondSaveApplies() async throws {
        // The receiving side of the fruit pipeline: a clip arrives untitled
        // (the capture's first save), then the SAME record arrives again with
        // the AI title the origin device wrote moments later. The second apply
        // must land — this is the macOS→iOS smart-title path.
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        let v1 = ClipItem(id: id, updatedAt: base, title: "", preview: "body", contentHash: "h")
        #expect(
            try await store.applyRemoteUpsert(v1, content: .text("body"), systemFields: Data([1])))
        #expect(try await store.item(id: id)?.title.isEmpty == true)

        // `updateTitle` on the origin bumps updatedAt, so v2 is strictly newer.
        let v2 = ClipItem(
            id: id, updatedAt: base.addingTimeInterval(2), title: "Rotate the credentials",
            preview: "body", contentHash: "h")
        #expect(
            try await store.applyRemoteUpsert(v2, content: .text("body"), systemFields: Data([2])))
        #expect(try await store.item(id: id)?.title == "Rotate the credentials")
    }

    @Test("A newer local title survives a stale remote and stays flagged for upload")
    func localFruitSurvivesConflictAndStaysPending() async throws {
        // The conflict-resolution invariant the adapter's serverRecordChanged
        // re-queue depends on: when the LOCAL copy (fresh title) beats a stale
        // server record, the title stays, the server's system fields are
        // recorded (so the retry builds with a current change tag), and the row
        // REMAINS pending upload — the fruit must still reach the other devices.
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let item = ClipItem(id: UUID(), updatedAt: base, preview: "body", contentHash: "h")
        try await store.insert(item, content: .text("body"))
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        try await store.updateTitle(id: item.id, title: "Fresh local title")
        #expect(try await store.pendingUploads().map(\.item.id) == [item.id])

        // The stale server copy (the untitled v1) loses last-writer-wins.
        let stale = ClipItem(
            id: item.id, updatedAt: base, title: "", preview: "body", contentHash: "h")
        let applied = try await store.applyRemoteUpsert(
            stale, content: .text("body"), systemFields: Data([9]))
        #expect(!applied, "the stale remote must lose to the newer local title")
        #expect(try await store.item(id: item.id)?.title == "Fresh local title")
        #expect(
            try await store.systemFields(for: item.id) == Data([9]),
            "the server tag must be recorded so the retry builds a current record")
        #expect(
            try await store.pendingUploads().map(\.item.id) == [item.id],
            "the local fruit must STAY pending — it still has to reach the other devices")
    }

    @Test("Remote upsert of an unseen clip inserts it, not pending re-upload")
    func remoteUpsertInserts() async throws {
        let store = try makeStore()
        let remote = ClipItem(preview: "from other device", contentHash: "hr")
        try await store.applyRemoteUpsert(
            remote, content: .text("from other device"), systemFields: Data([1]))
        #expect(try await store.count() == 1)
        #expect(try await store.pendingUploads().isEmpty, "remote-applied rows are not dirty")
    }

    @Test("Deletes become tombstones, propagate, then clear")
    func deletionTombstones() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "doomed", contentHash: "h")
        try await store.insert(item, content: .text("doomed"))

        try await store.deleteForSync(id: item.id)
        #expect(try await store.count() == 0)
        #expect(try await store.pendingDeletionRecordIDs() == [item.id.uuidString])

        try await store.clearTombstone(recordID: item.id.uuidString)
        #expect(try await store.pendingDeletionRecordIDs().isEmpty)
    }

    @Test("Sync deletes remove now-orphaned binary blobs")
    func deletionTombstonesCleanOrphanedBlobs() async throws {
        let blobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-delete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore(blobDir: blobDir)
        let payload = Data("sync-delete-binary-payload".utf8)
        let item = ClipItem(
            kind: .image, preview: "Image",
            contentHash: ClipItem.hash(of: payload, kind: .image))
        try await store.insert(item, content: .binary(data: payload, typeIdentifier: "public.data"))

        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: blobDir.path)
        #expect(blobFiles.filter { $0 != "thumbnails" }.count == 1)

        try await store.deleteForSync(id: item.id)

        #expect(try await store.count() == 0)
        #expect(try await store.pendingDeletionRecordIDs() == [item.id.uuidString])
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: blobDir.path)) ?? []
        #expect(
            !remaining.contains { $0 != "thumbnails" },
            "sync delete should mirror direct delete's orphan blob cleanup")
    }

    @Test("Remote deletion removes the local row")
    func remoteDeletion() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.applyRemoteDeletion(recordID: item.id.uuidString)
        #expect(try await store.count() == 0)
    }

    @Test("Forgetting sync fields re-flags every clip for upload, keeps the data")
    func forgetAllSyncFields() async throws {
        let store = try makeStore()
        let a = ClipItem(preview: "a", contentHash: "ha")
        let b = ClipItem(preview: "b", contentHash: "hb")
        try await store.insert(a, content: .text("a"))
        try await store.insert(b, content: .text("b"))
        try await store.markUploaded(id: a.id, systemFields: Data([1]))
        try await store.markUploaded(id: b.id, systemFields: Data([2]))
        #expect(try await store.pendingUploads().isEmpty)

        try await store.forgetAllSyncFields()

        // Data survives; both rows are pending again with their tags dropped.
        #expect(try await store.count() == 2)
        #expect(try await store.pendingUploads().count == 2)
        #expect(try await store.systemFields(for: a.id) == nil)
        #expect(try await store.systemFields(for: b.id) == nil)
    }

    @Test("Remote board identity survives insert, update, and database reopen")
    func remoteBoardIdentitySurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-board-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: directory)
        let boardID = UUID()
        let first = Pinboard(
            id: boardID, name: "Work", sfSymbol: "briefcase", colorHex: "#34C759",
            emoji: "💼")
        try await store?.applyRemoteBoardUpsert(first, systemFields: Data([1]))

        let changed = Pinboard(
            id: boardID, name: "Work", sfSymbol: "briefcase", colorHex: "#0A84FF",
            emoji: "🧰")
        try await store?.applyRemoteBoardUpsert(changed, systemFields: Data([2]))
        store = nil

        let reopened = try GRDBClipboardStore(directory: directory)
        let persisted = try await reopened.pinboards().first { $0.id == boardID }
        #expect(persisted?.colorHex == "#0A84FF")
        #expect(persisted?.emoji == "🧰")
        #expect(try await reopened.boardSystemFields(for: boardID) == Data([2]))
        #expect(!(try await reopened.pendingBoardUploads().contains { $0.id == boardID }))

        let legacy = Pinboard(id: UUID(), name: "Legacy", sfSymbol: "square.stack")
        try await reopened.applyRemoteBoardUpsert(legacy, systemFields: Data([3]))
        let legacyPersisted = try await reopened.pinboards().first { $0.id == legacy.id }
        #expect(legacyPersisted?.colorHex == nil)
        #expect(legacyPersisted?.emoji == nil)
    }

    @Test("A remote-winning upsert never touches local-only curation columns")
    func remoteUpsertPreservesLocalOnlyColumns() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let local = ClipItem(updatedAt: base, preview: "local", contentHash: "h")
        try await store.insert(local, content: .text("local"))

        // Curate locally: snippet + keyword + uses + archived — none of which
        // the sync record can carry, so a remote edit must leave them alone.
        try await store.promoteToSnippet(id: local.id, title: "My snippet")
        try await store.setKeyword(id: local.id, keyword: "sig")
        try await store.incrementUses(id: local.id)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [local.id.uuidString])
        }

        // A newer remote edit of the same clip (e.g. it was pinned on the phone).
        let remote = ClipItem(
            id: local.id, updatedAt: Date().addingTimeInterval(600), title: "Remote title",
            preview: "remote", contentHash: "h", isPinned: true)
        let applied = try await store.applyRemoteUpsert(
            remote, content: .text("remote"), systemFields: Data([1]))
        #expect(applied)

        let row = try await store.writer.read { db in
            try ClipRow.filter(key: local.id.uuidString).fetchOne(db)
        }
        let merged = try #require(row)
        // Local-only curation survives …
        #expect(merged.isSnippet, "a remote edit must never demote a snippet")
        #expect(merged.isArchived)
        #expect(merged.keyword == "sig")
        #expect(merged.uses == 1)
        // … while the synced fields took the remote's values.
        #expect(merged.title == "Remote title")
        #expect(merged.preview == "remote")
        #expect(merged.isPinned)
        #expect(merged.contentText == "remote")
    }

    @Test("Remote content: nil leaves local content untouched; binary keeps OCR text")
    func remoteUpsertContentSemantics() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)

        // nil content (e.g. an asset over the size cap) never blanks content.
        let textClip = ClipItem(updatedAt: base, preview: "text", contentHash: "ht")
        try await store.insert(textClip, content: .text("the body"))
        let metadataOnly = ClipItem(
            id: textClip.id, updatedAt: base.addingTimeInterval(60), preview: "edited",
            contentHash: "ht")
        let applied = try await store.applyRemoteUpsert(
            metadataOnly, content: nil, systemFields: Data([1]))
        #expect(applied)
        #expect(try await store.content(for: textClip.id) == .text("the body"))
        #expect(try await store.items().first?.preview == "edited")

        // A binary payload replaces the blob but keeps contentText — for image
        // clips that column holds locally attached OCR text, which never syncs.
        let imageClip = ClipItem(
            updatedAt: base, kind: .image, preview: "Image", contentHash: "hi")
        try await store.insert(
            imageClip, content: .binary(data: Data([1, 2]), typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: imageClip.id, text: "receipt total 42")
        let remoteImage = ClipItem(
            id: imageClip.id, updatedAt: Date().addingTimeInterval(600), kind: .image,
            preview: "Image", contentHash: "hi")
        #expect(
            try await store.applyRemoteUpsert(
                remoteImage, content: .binary(data: Data([3, 4]), typeIdentifier: "public.png"),
                systemFields: Data([2])))
        let row = try await store.writer.read { db in
            try ClipRow.filter(key: imageClip.id.uuidString).fetchOne(db)
        }
        let imageRow = try #require(row)
        #expect(imageRow.contentText == "receipt total 42")
        #expect(
            try await store.content(for: imageClip.id)
                == .binary(data: Data([3, 4]), typeIdentifier: "public.png"))
    }

    @Test("Pin toggles re-flag a synced clip for upload and bump updatedAt")
    func pinToggleReflagsForUpload() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let item = ClipItem(updatedAt: base, preview: "pin me", contentHash: "h")
        try await store.insert(item, content: .text("pin me"))
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        #expect(try await store.pendingUploads().isEmpty)

        try await store.setPinned(id: item.id, true)

        let pending = try await store.pendingUploads()
        #expect(pending.map(\.item.id) == [item.id])
        let updated = try #require(pending.first?.item)
        #expect(updated.isPinned)
        #expect(updated.updatedAt > base, "LWW needs the pin toggle to look newer")
    }

    @Test("A pre-change remote copy cannot revert a fresh local board assignment")
    func staleRemoteLosesToFreshBoardAssignment() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let item = ClipItem(updatedAt: base, preview: "boarded", contentHash: "h")
        try await store.insert(item, content: .text("boarded"))
        try await store.markUploaded(id: item.id, systemFields: Data([1]))

        // Local: add the clip to a board. The assignment bumps updatedAt, so
        // the not-yet-uploaded change outranks the server's pre-add copy.
        let board = try await store.createPinboard(name: "Work")
        try await store.assign(clipID: item.id, toBoard: board.id)

        // A fetch delivers the record as the server last saw it (updatedAt =
        // base, no boards). It must lose LWW: the adapter then skips
        // setBoardMembership, and the pending upload must survive.
        let stale = ClipItem(
            id: item.id, updatedAt: base, preview: "boarded", contentHash: "h")
        let applied = try await store.applyRemoteUpsert(
            stale, content: .text("boarded"), systemFields: Data([2]))
        #expect(!applied, "the stale remote must lose so membership is not reverted")
        #expect(try await store.boardIDs(forClip: item.id) == [board.id])
        #expect(
            try await store.pendingUploads().map(\.item.id) == [item.id],
            "the assignment still uploads — the stale fetch must not de-queue it")
    }

    @Test("A locally tombstoned record is not resurrected by a remote upsert")
    func tombstoneBlocksResurrection() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "deleted here", contentHash: "h")
        try await store.insert(item, content: .text("deleted here"))
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        try await store.deleteForSync(id: item.id)
        #expect(try await store.pendingDeletionRecordIDs() == [item.id.uuidString])

        // A concurrent remote edit arrives after the local delete.
        let remote = ClipItem(
            id: item.id, updatedAt: Date().addingTimeInterval(600), preview: "remote edit",
            contentHash: "h")
        let applied = try await store.applyRemoteUpsert(
            remote, content: .text("remote edit"), systemFields: Data([2]))
        #expect(!applied)
        #expect(try await store.count() == 0, "the local deletion wins")
        #expect(
            try await store.pendingDeletionRecordIDs() == [item.id.uuidString],
            "the pending deletion still propagates")
    }

    @Test("Panic delete tombstones synced secrets only")
    func deleteAllSensitiveTombstonesSyncedRows() async throws {
        let store = try makeStore()
        let synced = ClipItem(preview: "synced secret", contentHash: "hs", isSensitive: true)
        let unsynced = ClipItem(preview: "local secret", contentHash: "hu", isSensitive: true)
        let plain = ClipItem(preview: "plain", contentHash: "hp")
        try await store.insert(synced, content: .text("synced secret"))
        try await store.insert(unsynced, content: .text("local secret"))
        try await store.insert(plain, content: .text("plain"))
        try await store.markUploaded(id: synced.id, systemFields: Data([1]))

        let removed = try await store.deleteAllSensitive()

        #expect(removed == 2)
        #expect(try await store.count() == 1)
        #expect(
            try await store.pendingDeletionRecordIDs() == [synced.id.uuidString],
            "only the synced secret has a cloud record to delete")
    }

    @Test("Count and id projections agree with the full pending-upload fetch")
    func pendingUploadProjections() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let synced = ClipItem(createdAt: base, preview: "synced", contentHash: "hs")
        let redirtied = ClipItem(
            createdAt: base.addingTimeInterval(1), preview: "edited", contentHash: "he")
        let fresh = ClipItem(
            createdAt: base.addingTimeInterval(2), preview: "fresh", contentHash: "hf")
        try await store.insert(synced, content: .text("synced"))
        try await store.insert(redirtied, content: .text("edited"))
        try await store.insert(fresh, content: .text("fresh"))
        try await store.markUploaded(id: synced.id, systemFields: Data([1]))
        try await store.markUploaded(id: redirtied.id, systemFields: Data([2]))
        try await store.markNeedsUpload(id: redirtied.id)

        // The content-free projections must see exactly what the hydrating
        // fetch sees, in the same createdAt order.
        let full = try await store.pendingUploads()
        #expect(full.map(\.item.id) == [redirtied.id, fresh.id])
        #expect(try await store.pendingUploadCount() == full.count)
        #expect(try await store.pendingUploadIDs() == full.map(\.item.id))
    }

    @Test("Per-id pending fetch hydrates content for dirty rows only")
    func pendingUploadByID() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hi", contentHash: "h")
        try await store.insert(item, content: .text("hi"))

        let pending = try await store.pendingUpload(id: item.id)
        let entry = try #require(pending)
        #expect(entry.item.id == item.id)
        #expect(entry.content == .text("hi"))
        let unknown = try await store.pendingUpload(id: UUID())
        #expect(unknown == nil, "unknown id is nil")

        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        let clean = try await store.pendingUpload(id: item.id)
        #expect(clean == nil, "clean rows are not pending")

        try await store.markNeedsUpload(id: item.id)
        let redirtied = try await store.pendingUpload(id: item.id)
        #expect(redirtied?.item.id == item.id, "an edit makes the row pending again")
    }
}
