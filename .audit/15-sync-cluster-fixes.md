# Gancho — Fix Report 15: The sync cluster (A-1, B-1, B-2)

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Scope:** implements findings A-1, B-1, B-2 from `.audit/14-security-performance-deep-dive.md`
inside the sync boundary (`SyncLocalStore` + `GanchoSync`), plus the test suites that pin the
new semantics down. Written on Linux without a Swift toolchain: every edit was pattern-matched
against the surrounding file; CI (macos, full Swift Testing suite) is the compile/run gate.

Files touched:

| File | Findings |
| --- | --- |
| `Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift` | B-1, B-2 (protocol + GRDB impl) |
| `Packages/GanchoKit/Sources/GanchoSync/CKSyncEngineAdapter.swift` | A-1, B-1, B-2 (call sites) |
| `Packages/GanchoKit/Sources/GanchoSync/ClipRecordMapper.swift` | A-1 (staging lifecycle) |
| `Packages/GanchoKit/Tests/GanchoKitTests/SyncLocalStoreTests.swift` | B-1/B-2 tests |
| `Packages/GanchoKit/Tests/GanchoSyncTests/ClipRecordMapperTests.swift` | A-1 tests |
| `Packages/GanchoKit/Tests/GanchoSyncTests/SyncEnablementTests.swift` | stub conformer update |

---

## B-1 (P1) — `pendingUploads()` decrypted every pending blob to feed count/id callers

**Before:** `CKSyncEngineAdapter.emitCurrentStatus` (wants a count), `reenqueuePendingWork`
(wants ids), and `reconcilePendingChanges` (wants ids) all called
`store.pendingUploads()`, which fetches every dirty row **and** hydrates its content — a blob
read + AES-GCM decrypt per binary clip — on every sync cycle and every status refresh.

**After — three additive protocol requirements on `SyncLocalStore`, all content-free except
the last (which is single-row):**

| New requirement | GRDB implementation | Used by |
| --- | --- | --- |
| `pendingUploadCount() -> Int` | `SELECT COUNT(*) FROM clip WHERE syncSystemFields IS NULL OR needsUpload = 1` | `emitCurrentStatus` |
| `pendingUploadIDs() -> [UUID]` | `SELECT id … ORDER BY createdAt ASC`, `compactMap { UUID(uuidString:) }` | `reenqueuePendingWork`, `reconcilePendingChanges` |
| `pendingUpload(id:) -> (item, content)?` | `SELECT * … WHERE id = ? AND (syncSystemFields IS NULL OR needsUpload = 1)` + `content(for:)` for that one row | `nextRecordZoneChangeBatch` (B-2) |

The `WHERE` clause and `ORDER BY createdAt ASC` are copied verbatim from `pendingUploads()`,
so the projections are exact — the test suite asserts count/ids/order equality against the
full fetch on a seeded store (synced + re-dirtied + never-synced rows).

**Conformers updated (both of the only two in the tree, verified by grep):**

| Conformer | File |
| --- | --- |
| `GRDBClipboardStore` | `Sources/GanchoKit/SyncLocalStore.swift` (real SQL) |
| `StubSyncLocalStore` (test-private) | `Tests/GanchoSyncTests/SyncEnablementTests.swift` (`0` / `[]` / `nil`) |

`pendingUploads()` (the hydrating full fetch) is deliberately **kept** on the protocol: it is
the ground-truth API the store tests (`SyncLocalStoreTests`, `PinboardTests`) assert against,
and the semantic anchor the projections are tested to agree with. After B-2 it has no
production caller — a future pass may fold it into the tests, but removing a protocol
requirement is not the smallest correct diff here.

## B-2 (P1) — `nextRecordZoneChangeBatch` built a CKRecord for every pending upload

**Before:** the batch provider prefetched `store.pendingUploads()` (full backlog hydrate +
decrypt) **and** `store.pendingBoardUploads()`, built a CKRecord for every entry, and handed
`RecordZoneChangeBatch(pendingChanges:)` a dictionary — on a big first sync, O(backlog) record
builds per batch callback when CloudKit only reads the ones referenced by this send's pending
changes.

**After:** the build is scoped to `syncEngine.state.pendingRecordZoneChanges`:

1. Collect the `.saveRecord` ids from `pendingChanges` (deletes need no record).
2. Boards (cheap, metadata-only, no decrypt): `pendingBoardUploads()` is fetched **once, and
   only if** a board-zone save is present, then indexed by id.
3. Clips: each save id in the clip zone is hydrated individually via the new
   `store.pendingUpload(id:)` — one row fetch + one content decrypt per record the batch
   actually references.
4. Records are keyed by the change's own `CKRecord.ID` (identical construction to the old
   `recordID(for:)`/`boardRecordID(for:)` keys — every pending change was added through those
   same helpers), and the `UncheckedSendableBox` + synchronous-closure handoff is preserved
   byte-for-byte.

**Behavior equivalence argument:** for any requested `recordID`, the old code returned a
record iff the row was in `pendingUploads()`/`pendingBoardUploads()` (and the mapper returned
non-nil); the new code returns a record iff the same predicate
(`syncSystemFields IS NULL OR needsUpload = 1`, resp. `needsUpload = 1`) holds for that id —
same predicate, same mapper call, same arguments. Ids in `pendingChanges` but no longer
pending (row deleted, stale resumed state) resolve to `nil` in both versions, which is exactly
what `reconcilePendingChanges` exists to mop up. Zone names that match neither zone resolve to
`nil` in both versions.

**Test seam note:** the delegate method itself takes a live `CKSyncEngine` and cannot be
constructed on CI (no iCloud container), matching the pre-existing zero direct coverage of
this method. The new behavior is pinned where the seam exists: `pendingUpload(id:)` is tested
to return content-hydrated entries for dirty rows only (nil for unknown / already-synced ids,
pending again after `markNeedsUpload`) in `SyncLocalStoreTests`.

## A-1 (P1, security) — CKAsset temp files leaked plaintext clip bytes forever

**Before:** `ClipRecordMapper.makeAsset` wrote clip binary payloads **unencrypted** to
`temporaryDirectory/gancho-asset-<uuid>` and nothing ever deleted them — a fifth, unencrypted
resting place for content outside the SQLCipher/AES-GCM boundary, growing without bound.

**After — a three-part staging lifecycle** (`ClipRecordMapper` "CKAsset staging" section +
two adapter hooks):

1. **Dedicated directory.** `makeAsset` stages into
   `temporaryDirectory/gancho-ck-assets/gancho-asset-<uuid>` (`assetStagingDirectory`,
   created on demand). Every build writes a **fresh random-named file** — two builds of the
   same clip (e.g. a retry, or an edit racing a send) can never collide on one path, so no
   deletion of one can strand the other.
2. **Targeted delete on sent.** `handleSentRecordZoneChanges` calls
   `ClipRecordMapper.removeStagedAsset(for: record)` for each saved clip record before
   `markUploaded`. It deletes the file behind **that record's own** `contentAsset.fileURL` —
   and only if the file (symlink-resolved, `/var` vs `/private/var`) lives directly inside the
   staging directory, so a *fetched* record's CloudKit-managed asset can never be touched.
3. **Age-gated sweep at `start()`.** `sweepStagedAssets(olderThan: 3600)` reaps files older
   than 1 h — the crash-between-stage-and-send leftovers, and files whose save failed (failed
   saves are deliberately not cleaned inline: CKSyncEngine's retry rebuilds the batch and
   stages a fresh file anyway).

**Why this cannot delete a file CloudKit still needs:**

- The per-record delete fires only *after* CloudKit reports the record saved — the upload is
  complete, the asset was already copied server-side. The URL deleted is the one carried by
  that exact record instance, which no other in-flight batch references (fresh file per
  build). If the returned record's asset URL was rewritten server-side or points outside the
  staging dir, the guard makes it a no-op and the sweep covers the leftover later.
- The start-time sweep only removes files ≥ 1 h old. A staged file is read exactly once, by
  the send of the batch whose build wrote it, shortly after `nextRecordZoneChangeBatch`
  returns; any file that old belongs to a send that finished, failed (retry = fresh file), or
  died with its process. No sweep runs on a timer mid-send.

**Residual window (documented, accepted):** a file whose save *fails* persists until the next
`start()` (app relaunch or sync re-enable) ages it out — bounded, plaintext-in-tmp for the
retry window only, versus forever before. `.audit/14`'s alternative (staging inside the
encrypted blob tree) remains open if even that window is unacceptable.

---

## Tests added

`Packages/GanchoKit/Tests/GanchoKitTests/SyncLocalStoreTests.swift`

- **"Count and id projections agree with the full pending-upload fetch"** — seeds synced,
  re-dirtied and never-synced rows with explicit `createdAt` spacing; asserts
  `pendingUploadCount`/`pendingUploadIDs` match `pendingUploads()` in count, membership and
  order.
- **"Per-id pending fetch hydrates content for dirty rows only"** — `pendingUpload(id:)`
  returns item + decrypted content for a dirty row; nil for an unknown id; nil once
  `markUploaded`; non-nil again after `markNeedsUpload`.

`Packages/GanchoKit/Tests/GanchoSyncTests/ClipRecordMapperTests.swift`

- **"Binary assets stage in the dedicated subdir and are removed on sent"** — a binary
  record's `CKAsset` file lands inside `assetStagingDirectory` (symlink-resolved compare);
  `removeStagedAsset(for:)` then deletes exactly that file.
- **"The staging sweep reaps stale files and spares fresh ones"** — plants a backdated
  (−2 h `modificationDate`) file plus a fresh one; `sweepStagedAssets(olderThan: 3600)`
  removes only the stale file. Parallel-suite safe: only genuinely old files are reaped, so a
  concurrently-running mapper test's fresh asset is never at risk.
- **"removeStagedAsset never touches a file outside the staging directory"** — a record whose
  asset points at a foreign tmp file (the fetched-record shape) is left alone.

`Packages/GanchoKit/Tests/GanchoSyncTests/SyncEnablementTests.swift` — `StubSyncLocalStore`
grew the three new requirements (`0` / `[]` / `nil`), keeping the factory tests compiling.

## Follow-ups (not in scope)

- `.audit/03` A3-1.8: a partial index on the pending-upload predicate would speed all four
  pending queries (`COUNT`, ids, per-id, full) — schema change, separate migration PR.
- Consider demoting `pendingUploads()` from the protocol to a test-only extension once the
  store tests migrate to the projections.
