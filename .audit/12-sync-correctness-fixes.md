# Gancho — Fix Report 12: The sync-clobber cluster (B-1 … B-5)

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Scope:** implements the PART A / A.1 fixes from `.audit/04-bugs-features-worldclass.md`
(B-1, B-2, B-3, B-4, B-5) inside the engine modules, plus the test suites that pin the new
semantics down. Written on Linux without a Swift toolchain: every edit was pattern-matched
against the surrounding file; CI (macos-26, full Swift Testing suite) is the compile/run gate.

---

## B-1 (P0) — Remote upsert clobbered local-only columns

**File:** `Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift`
(`GRDBClipboardStore.applyRemoteUpsert`)

**Before:** the method built a full `ClipRow(item:)` and ran `finalRow.upsert(db)`. `ClipItem`
cannot carry `isSnippet`/`isArchived`, and `ClipRecordMapper` never syncs `keyword`/`uses`, so a
remote edit reset all four (plus `sortIndex` via the row's absent column default on conflict
replace). A demoted snippet was then eligible for the next retention purge — silent data loss.

**After:** the whole-row upsert is gone. The method now has three explicit branches inside one
write transaction:

1. **LWW skip** (local strictly newer): unchanged behavior — store the remote's system fields
   only, and now `return false`.
2. **Existing row, remote wins** (remote `updatedAt` ≥ local — remote still wins ties, exactly
   as before): an explicit column-list `UPDATE` of only the synced columns — `createdAt`,
   `updatedAt`, `lastUsedAt`, `kind`, `title`, `preview`, `contentHash`, `sourceAppBundleID`,
   `sourceDeviceName`, `isPinned`, `isSensitive`, `expiresAt`, `tags` — plus
   `syncSystemFields`/`needsUpload = 0` bookkeeping. `isSnippet`, `isArchived`, `keyword`,
   `uses`, `sortIndex` (and the legacy `pinboardID`) are never mentioned, so they survive.
   Content columns are handled separately (see B-2). `return true`.
3. **New row:** the original `ClipRow` insert, unchanged — except for the tombstone guard
   (see B-5). `return true` (or `false` when tombstoned).

Blob handling is untouched: a remote `.binary` payload is written through
`blobsForMaintenance.write(data)` *before* the transaction, exactly as before.

## B-2 (rides B-1) — Content-column semantics (OCR text, nil content)

`attachExtractedText` (`SnippetLibrary.swift:67-73`) stores OCR words for image clips in
`contentText` — a local enrichment the CKRecord never carries. The exact semantics chosen for
the existing-row branch, per remote content case:

| Remote content | contentText | contentBlobHash | contentTypeIdentifier |
| --- | --- | --- | --- |
| `.text(t)` | ← `t` | ← `NULL` | ← `NULL` |
| `.fileReferences(p)` | ← joined paths | ← `NULL` | ← `"public.file-url"` |
| `.binary(d, t)` | **untouched** (OCR preserved) | ← new blob hash | ← `t` |
| `nil` | **untouched** | **untouched** | **untouched** |

Rationale:

- **`nil` means "the record carries no content"** (asset over the 50 MB cap, or an asset that
  failed to download/decode — `ClipRecordMapper.decode` collapses both to `content == nil`).
  Blanking local content on that signal is exactly the B-2 data loss; leaving all three columns
  alone keeps the local blob *and* any OCR text. The synced metadata (title, preview,
  timestamps, flags) still updates, so the row is not stale.
- **`.binary` preserves `contentText`** because for image clips that column is pure local
  enrichment (OCR). The blob and its type identifier still follow the remote, so a genuinely
  edited image replaces bytes correctly. (A binary row's `content(for:)` reads the blob first,
  so a leftover `contentText` never changes what paste produces — it only keeps search working.)
- **`.text` / `.fileReferences` fully replace content** including clearing a stale blob
  reference — a remote text edit must win completely, and a dangling `contentBlobHash` would
  otherwise shadow the new text in `content(for:)` (which prefers the blob). This means a
  remote *text* edit of a clip that also had OCR text overwrites it — correct, because for a
  text clip `contentText` IS the synced content, not an enrichment.

The new-row branch uses the mapped content directly (a brand-new row has no local enrichment to
protect).

## B-3 (P1) — Stale remote board membership applied unconditionally

**Files:** `Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift` (protocol + GRDB impl),
`Packages/GanchoKit/Sources/GanchoSync/CKSyncEngineAdapter.swift` (both call sites),
`Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift` (`assign`/`unassign`/
`removeFromAllBoards`), `Packages/GanchoKit/Tests/GanchoSyncTests/SyncEnablementTests.swift`
(stub conformer).

Per the dossier's prescription (a) + (b); (c) is deferred (below).

- **(a) Protocol change:** `applyRemoteUpsert` is now
  `@discardableResult func applyRemoteUpsert(_:content:systemFields:) async throws -> Bool` —
  `true` iff the remote was applied (row updated or inserted); `false` on LWW skip or tombstone
  block. Conformers updated: `GRDBClipboardStore` (SyncLocalStore.swift) and the private
  `StubSyncLocalStore` in `SyncEnablementTests.swift` (returns `true`). Those are the only two
  conformers in the repo (verified by grep; `ClientContract.swift` only *mentions* the protocol
  in a comment and does not re-declare this method).
- **Both adapter call sites** (`handleFetchedRecordZoneChanges` and the `serverRecordChanged`
  conflict path in `handleFailedSave`) now call `setBoardMembership` **only when the upsert
  returned true**. A `try?` failure counts as not-applied (`?? false`) — membership is never
  rebuilt from a record whose row-apply did not land (also the safe half of B-29's concern).
- **(b) `assign`/`unassign`/`removeFromAllBoards` now bump `updatedAt`** (alongside the
  existing `needsUpload = 1`). Without this, the dossier's exact failing sequence still lost:
  the fetched pre-add record ties on `updatedAt`, remote wins ties, `applyRemoteUpsert` returns
  *true*, and the stale board set would be applied anyway (and `needsUpload` reset). With the
  bump, the local not-yet-uploaded membership change strictly outranks the pre-change server
  copy, the upsert returns `false`, membership survives, and the pending upload survives.

## B-4 (P1) — Pin toggles never reached the cloud

**File:** `Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift` (`setPinned`).

`setPinned` now executes
`UPDATE clip SET isPinned = ?, updatedAt = ?, needsUpload = 1 WHERE id = ?` — the `needsUpload`
flag puts the clip into `pendingUploads()` (whose predicate is
`syncSystemFields IS NULL OR needsUpload = 1`), and the `updatedAt` bump (which the method
already did) makes the toggle win LWW on the other devices.

**Remaining half (out of my file scope, documented as follow-up):** the dossier also prescribes
that the call sites enqueue immediately — Mac `togglePin` (`AppModel.swift:982`), iOS
`togglePin` (`GanchoiOSApp.swift:717-721`), and `PinClipIntent.swift:18` should call
`syncEngine.enqueue([item])` the way capture does. Until that lands, the `needsUpload = 1` flag
guarantees the pin uploads at the next `start()` (app launch / sign-in / zone reset) via
`reenqueuePendingWork`/`reconcilePendingChanges` — eventual, not immediate.

## B-5 (P1) — Purges and panic delete wrote no tombstones; upserts could resurrect deletions

**Files:** `Packages/GanchoKit/Sources/GanchoKit/RetentionEngine.swift` (`runPurge`),
`Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift` (`deleteAllSensitive`),
`Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift` (tombstone guard in
`applyRemoteUpsert`).

- **`runPurge`:** the four DELETE clauses now go through one local
  `purge(where:arguments:)` helper inside the same write transaction:
  `INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) SELECT id, <now> FROM clip WHERE
  syncSystemFields IS NOT NULL AND <predicate>` followed by
  `DELETE FROM clip WHERE <predicate>` (identical predicate string for both statements, so they
  cover exactly the same rows; `db.changesCount` is read after the DELETE, so the summary
  counters are unchanged). `INSERT OR REPLACE` matches `deleteForSync`'s style. Only rows with
  `syncSystemFields` get tombstones — an unsynced row has no cloud record to delete.
- **`deleteAllSensitive`:** same pattern — tombstone `isSensitive = 1 AND syncSystemFields IS
  NOT NULL` rows, then the original `DELETE FROM clip WHERE isSensitive = 1`, inside the one
  existing write transaction. Counting semantics unchanged (`changesCount` after the DELETE).
- **Resurrection guard:** `applyRemoteUpsert`'s new-row branch first checks
  `sync_tombstone` for the record id; when a tombstone exists the insert is skipped and the
  method returns `false` (no system fields are stored — there is no row to store them on). The
  pending CK deletion wins the race: it propagates, deletes the server record, and
  `clearTombstone` runs on ack. Edge case accepted: if the user *edits* the clip on device B in
  the window between A's delete and its propagation, that edit is lost — deletion-wins is the
  chosen (and simplest correct) policy for a tombstoned id; the alternative (resurrect and
  cancel the tombstone) would re-inflate every purged secret that got touched remotely.

**Remaining halves (documented, deliberately not changed here):**
- The apps do not call `enqueueDeletion` after a purge/panic, so purge tombstones upload at the
  next `start()` (via `reenqueuePendingWork`) rather than immediately. Wiring the apps to read
  `pendingDeletionRecordIDs()` post-purge and enqueue is app-layer work (out of my file scope).
- `delete(id:)` (the non-sync delete used when `syncEnabled` is false) still writes no
  tombstone — correct while sync is off, but the dossier's account-transition edge (delete
  while signed out, then enable sync) remains open.
- The dossier's stronger alternative — never uploading sensitive clips at all
  (`WHERE isSensitive = 0` in `pendingUploads()`) — is a product decision ("secrets never leave
  the device") left to Phase-0 planning; this fix makes the current behavior correct rather
  than changing the policy.

---

## Protocol change summary

`SyncLocalStore.applyRemoteUpsert` (SyncLocalStore.swift:29):
`async throws` → `@discardableResult … async throws -> Bool`, with the doc comment extended to
state the contract ("false ⇒ the caller must not apply any follow-up state from the record").
Conformers updated:

| Conformer | File | Change |
| --- | --- | --- |
| `GRDBClipboardStore` | `Sources/GanchoKit/SyncLocalStore.swift` | full reimplementation (B-1/B-2/B-5), `@discardableResult`, returns `Bool` |
| `StubSyncLocalStore` (test-private) | `Tests/GanchoSyncTests/SyncEnablementTests.swift` | returns `true` |

Callers updated: both sites in `CKSyncEngineAdapter` (fetch path + conflict path) now gate
`setBoardMembership` on the returned Bool. The three pre-existing test call sites compile
unchanged thanks to `@discardableResult`.

## Test inventory

`Packages/GanchoKit/Tests/GanchoKitTests/SyncLocalStoreTests.swift`
- *(extended)* "Remote upsert applies a newer remote, ignores an older one" — now also asserts
  the returned Bool both ways and that a losing remote leaves content untouched.
- **"A remote-winning upsert never touches local-only curation columns"** (B-1) — promote to
  snippet + keyword + uses + archived, then a newer remote edit: curation survives; title,
  preview, isPinned, contentText take the remote's values. Asserted at the `ClipRow` level.
- **"Remote content: nil leaves local content untouched; binary keeps OCR text"** (B-2) —
  (1) newer remote with `content: nil` updates metadata but keeps the local text;
  (2) image clip with attached OCR text + newer remote binary: OCR text survives, blob replaced.
- **"A pre-change remote copy cannot revert a fresh local board assignment"** (B-3) — the
  dossier's exact failing sequence at the store level: assign (bumps updatedAt) → stale fetch
  (old updatedAt) → upsert returns false, `boardIDs(forClip:)` intact, still in
  `pendingUploads()`.
- **"Pin toggles re-flag a synced clip for upload and bump updatedAt"** (B-4) — synced clip,
  `setPinned` → appears in `pendingUploads()` with `isPinned` and a strictly newer `updatedAt`.
- **"A locally tombstoned record is not resurrected by a remote upsert"** (B-5) —
  `deleteForSync` then a newer remote edit: returns false, row count stays 0, tombstone still
  pending.
- **"Panic delete tombstones synced secrets only"** (B-5) — synced + unsynced secrets +
  plain clip: `deleteAllSensitive` removes 2, tombstones exactly the synced one.

`Packages/GanchoKit/Tests/GanchoKitTests/RetentionEngineTests.swift`
- **"Purges tombstone synced rows so deletions propagate; unsynced rows leave none"** (B-5) —
  sensitive-lifetime clause with one synced and one unsynced victim.
- **"Every purge clause tombstones its synced victims"** (B-5) — one synced victim per clause
  (own `expiresAt`, sensitive lifetime, per-kind window, global window); all four purged and
  all four tombstoned.

Adapter-level note (B-3): `handleFetchedRecordZoneChanges`/`handleFailedSave` are private and
take live `CKSyncEngine.Event` values that cannot be constructed in tests, and the repo has no
adapter test seam today — the LWW-gating contract is therefore pinned at the store boundary
(the returned Bool), which is the exact value the adapter branches on. Building an event seam
(or extracting the modification-apply loop into a testable function) is a worthwhile follow-up.

## Interactions with concurrent audit work

`GRDBClipboardStore.insert`'s dedupe branch gained `existing.isArchived = false` (B-14, another
work stream) while this fix was in flight — no overlap with these changes; both coexist in the
working tree. `TierEnforcement*` was not touched by this work.

## Compile-confidence notes (no toolchain on this machine)

Everything matches in-file precedent (multi-line SQL literals, `StatementArguments`, literal
argument arrays with optionals, `Bool.fetchOne`, captured `let` rows in `writer.write`
closures). The three constructs worth a reviewer's glance:

1. `RetentionEngine.runPurge` — the local `func purge(where:arguments:)` declared inside the
   `writer.write` closure (captures `db` and `now`; non-escaping, so strict concurrency is
   satisfied), and `StatementArguments([now]) + arguments` (GRDB's documented `+` concatenation;
   the explicit `StatementArguments([now])` avoids relying on array-literal inference).
2. `@discardableResult` on the protocol *requirement* (SyncLocalStore.swift) as well as on the
   GRDB implementation — both placements are needed for warning-free callers through either
   the protocol or the concrete type.
3. The `SELECT EXISTS (…)` fetched via `Bool.fetchOne` in the tombstone guard (SQLite returns
   0/1, which GRDB decodes as Bool; same decode path as `Bool.fetchOne` on `isSystem`).
