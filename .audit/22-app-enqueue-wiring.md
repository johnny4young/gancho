# Gancho — Fix Report 22: App-side immediate sync enqueue (pin toggles + purge tombstones)

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Scope:** the app-layer half deferred by `.audit/12-sync-correctness-fixes.md` (B-4/B-5
"remaining halves"). Engine/store behavior is untouched; no package files were modified and no
new package API was added. Written on Linux without a Swift toolchain — every edit mirrors an
in-file pattern; CI is the compile gate.

**Files changed:** `Apps/GanchoMac/AppModel.swift`, `Apps/GanchoiOS/GanchoiOSApp.swift`.

---

## What now enqueues immediately

### 1. Pin toggles (B-4, app half)

Fix 12 made `GRDBClipboardStore.setPinned` set `needsUpload = 1` and bump `updatedAt`, but
nothing app-side enqueued the clip, so the toggle only uploaded at the next `start()`.

- **macOS** — `AppModel.togglePin` (`Apps/GanchoMac/AppModel.swift`): after the successful
  `grdbStore.setPinned(...)`, the task now calls `await sync.enqueue([item])`, exactly the
  capture path's call (`ingest`, same file). No `syncEnabled` guard, matching capture: `sync`
  is a `NoopSyncEngine` whenever sync is disabled, so the call is a no-op there. The early
  paywall `return` (free-tier pin ceiling) is before the enqueue, so a blocked pin enqueues
  nothing.
- **iOS** — `IOSAppModel.togglePin` (`Apps/GanchoiOS/GanchoiOSApp.swift`): same addition,
  `await syncEngine.enqueue([item])` after `grdb.setPinned(...)`, mirroring the capture path
  (`ingest`: `if let stored { await syncEngine.enqueue([stored]) }`).

Correctness notes:

- The `item` passed is the pre-toggle snapshot, which is fine: `CKSyncEngineAdapter.enqueue`
  uses only `item.id` (it calls `markNeedsUpload(id:)` and adds a `.saveRecord` pending
  change); the CKRecord is built from the stored row at send time, which already carries the
  new pin state.
- No double-enqueue: `setPinned` only flags the row; nothing else enqueues on this path.
  `markNeedsUpload` on an already-flagged row is an idempotent `UPDATE`.

### 2. Retention purge tombstones (B-5, app half)

Fix 12 made `RetentionEngine.runPurge` write `sync_tombstone` rows for synced victims, but
nothing app-side enqueued the deletions, so they propagated only at the next `start()` (via
`reenqueuePendingWork`). `runPurge` returns a `PurgeSummary` (counts, not ids), so the purged
ids are not directly available — instead the apps sweep the tombstone table, which the store
already exposes publicly as `pendingDeletionRecordIDs()` (protocol method on `SyncLocalStore`,
`public func` on `GRDBClipboardStore` — app-reachable, no new API needed).

- **macOS** — `AppModel.runRetention`: after `runPurge`, guarded by `if syncEnabled`, reads
  `grdbStore.pendingDeletionRecordIDs()`, maps to `UUID` via
  `compactMap { UUID(uuidString: $0) }` (same mapping `CKSyncEngineAdapter` uses for these
  record names), and calls `await sync.enqueueDeletion(ids: ids)` when non-empty.
- **iOS** — `IOSAppModel.runMaintenance`: identical block after `runPurge`, using `grdb` /
  `syncEngine`.

The `syncEnabled` guard matches the existing deletion-enqueue sites (mac `commitDeletion`, iOS
`delete(_:)`). Placement is after `runPurge` and before `TierEnforcement.enforce` —
enforcement only archives/releases (`isArchived`, a local-only column), never deletes, so it
produces no tombstones and needs no enqueue.

Double-enqueue safety: the sweep can include tombstones already enqueued (e.g. a user delete
in flight, or one awaiting its ack). That is safe by construction — `enqueueDeletion` only
does `engine.state.add(pendingRecordZoneChanges: [.deleteRecord(...)])`, and re-adding a
pending change for the same record id is idempotent in `CKSyncEngine.State`; even a
delete-after-delete race resolves server-side as an unknown-item delete, which the adapter's
existing failure handling already tolerates. `pendingDeletionRecordIDs()` is clip-zone only
(boards have their own `pendingBoardDeletionRecordIDs()`), so no cross-zone id confusion.

Bonus effect: because the sweep drains *all* pending clip tombstones, any tombstone written by
`deleteAllSensitive` (or an earlier failed enqueue) also propagates at the next retention pass
(mac: 300 s timer; iOS: foreground maintenance, ≥10 min throttle) — sooner than "next app
launch", though still not immediate (see below).

## What stays deferred, and exactly why

| Site | File | Why not wired |
| --- | --- | --- |
| `ClearSensitiveIntent` (panic delete) | `Apps/GanchoiOS/CaptureIntents.swift` | Outside this task's editable file set (other work streams own it). Structurally it also opens its own `IntentStore` and has no sync engine in scope — an immediate enqueue there needs either an in-app model hookup or a flush-on-start contract. Tombstones (written by `deleteAllSensitive` since fix 12) upload at the next `start()` or the next retention sweep (above). |
| `PinClipIntent` | `Apps/GanchoiOS/PinClipIntent.swift` | Same two reasons: file not editable in this task, and no engine in scope (standalone `IntentStore`). `setPinned`'s `needsUpload = 1` guarantees upload at the next `start()`. |
| macOS "clear sensitive" | — | No macOS app surface calls `deleteAllSensitive` today (verified by grep across `Apps/`); nothing to wire. |
| Board assign/unassign/removeFromAllBoards | `Apps/GanchoMac/AppModel.swift` (`assign`, `assignWithUndo`, `unassign`, `removeFromAllBoards`, `createBoard`, `setBoardMembership`-style toggles) and iOS equivalents | Observed adjacent gap of the same shape (B-3 made these set `needsUpload` + bump `updatedAt`, but the call sites don't `enqueue` the clip). Deliberately not touched here — outside this task's stated scope (pins + purges + clear-sensitive); flagging for a follow-up of the identical one-line pattern. |

## Package-side follow-up (if immediacy is wanted for the deferred sites)

No new package API was required for what landed — `pendingDeletionRecordIDs()` was already
public. If the intents' pins/deletes should propagate immediately (not merely on next
`start()`/retention pass), the cleanest engine-level addition would be
`SyncEngine.flushPendingDeletions()` (drain `pendingDeletionRecordIDs()` +
`pendingBoardDeletionRecordIDs()` into pending record-zone changes — i.e. expose the deletion
half of `reenqueuePendingWork`), invoked by the app on foreground/after intents run. A
lighter alternative: have the app call `syncNow()` when it foregrounds after an intent ran,
which `start()` already covers.

## Compile-confidence notes (no toolchain on this machine)

Every added line reuses constructs already present in the same file: `await sync.enqueue([item])`
/ `await syncEngine.enqueue([stored])` (capture paths), `await …enqueueDeletion(ids:)` +
`if syncEnabled` (delete paths), `(try? await …) ?? []`, and closure-style
`compactMap { UUID(uuidString: $0) }` (adapter precedent; avoided the point-free
`UUID.init(uuidString:)` form). Both models are `@MainActor`, so reading `syncEnabled` /
`sync` / `syncEngine` inside their unstructured `Task { }` blocks stays actor-isolated, same
as the surrounding code. All lines ≤ 100 columns. No new user-facing strings, no `print()`.
