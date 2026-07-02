# Gancho — Audit 10: Hot-Query Indexes + Thumbnail Cache Caps (implementation)

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Implements:** A3-1.1, A3-1.2 (partially A3-1.3/A3-1.4 where the same indexes apply), A3-1.15
from `.audit/03-architecture-performance-refactor.md` — Phase 0 items 1 and 3.
**Environment:** Linux container, no Swift toolchain. The migration SQL and every query plan
below were verified against SQLite 3.45 with a replicated v1–v15 schema; the Swift edits are
mechanical and mirror existing in-repo patterns line for line.

---

## 1. Migration `v16-hot-query-indexes`

Appended after `v15-reupload-board-members` in the `migrator` property
(`Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift:377-418`). Append-only — no
registered migration was edited. All four statements are `CREATE INDEX IF NOT EXISTS` via
`try db.execute(sql:)`; no query code was touched.

| Index | Definition | Serves |
| --- | --- | --- |
| `idx_clip_recent_activity` | `ON clip (isPinned DESC, IFNULL(lastUsedAt, createdAt) DESC) WHERE isArchived = 0` | `items(offset:limit:)` (`GRDBClipboardStore.swift:540-557`) — the list `AppModel.refreshRecents()` re-runs after every capture, paste, pin, board change, undo, and sync settle (A3-1.1). |
| `idx_clip_browse` | `ON clip (isPinned DESC, createdAt DESC) WHERE isArchived = 0` | `recentForBrowse(offset:limit:)` (`GRDBClipboardStore.swift:564-573`) — panel grouped history (`Apps/GanchoMac/PanelView.swift:1218`), iOS recent list (`Apps/GanchoiOS/GanchoiOSApp.swift:608`), keyboard extension (`Apps/GanchoKeyboard/KeyboardModel.swift:84`) (A3-1.2). |
| `idx_clip_board_board` | `ON clip_board (boardID, clipID)` | Board-filter subquery `SELECT clipID FROM clip_board WHERE boardID = ?` in `appendFilters` (`GRDBClipboardStore.swift:495-497`) and boards queries (`Pinboards.swift:167, 178, 235`); the retention engine's `id NOT IN (SELECT clipID FROM clip_board)` membership materialization (`RetentionEngine.swift:30, 37, 46, 55`). |
| `idx_clip_sensitive` | `ON clip (isSensitive) WHERE isSensitive = 1` | `sensitiveCount()` (`GRDBClipboardStore.swift:606-613`, Privacy Center), `deleteAllSensitive()` (`:618-625`, panic actions/intent), retention clause 2 (`RetentionEngine.swift:37`) (part of A3-1.3). |

### Why `(boardID, clipID)` when v10 already indexes `boardID`

The v10 junction has PK `(clipID, boardID)` plus single-column indexes on each column
(`GRDBClipboardStore.swift:312-317`). The single-column `boardID` index locates rows but is not
covering — every hit pays a table hop to fetch `clipID`, which is the only column the
subqueries select. The composite makes the board-filter lookup a **covering** index seek
(verified plan: `SEARCH clip_board USING COVERING INDEX idx_clip_board_board (boardID=?)`).

### The planner-mismatch caveat (expression index)

`idx_clip_recent_activity` is an expression index: SQLite only uses it when the query's
`ORDER BY` expression is **structurally identical** to the indexed expression after parsing.
GRDB renders `(Column("lastUsedAt") ?? Column("createdAt")).desc` as
`IFNULL("lastUsedAt", "createdAt") DESC` — confirmed by reading the query builder at
`GRDBClipboardStore.swift:540-557` (GRDB's `??` on SQL expressions emits `IFNULL`). Matching is
on the parse tree, not bytes, so GRDB's identifier quoting is irrelevant (verified: the quoted
form still plans `SCAN clip USING INDEX idx_clip_recent_activity`). The failure mode is benign
and one-sided: if a future GRDB version rendered a different function (e.g. `COALESCE`), the
planner would simply decline the index and fall back to the old full-scan-and-sort — **degraded
performance, never wrong results**. `IFNULL` is deterministic, as expression indexes require.
This caveat is written into the migration comment.

### How to verify on a Mac

```sh
sqlite3 path/to/gancho.sqlite   # or an unencrypted test copy; add PRAGMA key for SQLCipher
EXPLAIN QUERY PLAN SELECT * FROM clip WHERE isArchived = 0
  ORDER BY isPinned DESC, IFNULL(lastUsedAt, createdAt) DESC LIMIT 50;
-- expect: SCAN clip USING INDEX idx_clip_recent_activity   (and NO "USE TEMP B-TREE FOR ORDER BY")
EXPLAIN QUERY PLAN SELECT * FROM clip WHERE isArchived = 0
  ORDER BY isPinned DESC, createdAt DESC LIMIT 50;
-- expect: SCAN clip USING INDEX idx_clip_browse
EXPLAIN QUERY PLAN SELECT clipID FROM clip_board WHERE boardID = 'x';
-- expect: SEARCH clip_board USING COVERING INDEX idx_clip_board_board (boardID=?)
EXPLAIN QUERY PLAN SELECT COUNT(*) FROM clip WHERE isSensitive = 1 AND isArchived = 0;
-- expect: SEARCH clip USING INDEX idx_clip_sensitive (isSensitive=?)
```

All four expected plans were reproduced against SQLite 3.45 with the v1–v15 schema replicated
(including v10's pre-existing junction indexes, so the new index wins on merit, not absence).
A3-3.3's suggestion — `EXPLAIN QUERY PLAN` assertions in `PerformanceHarnessTests` — remains
open; it needs a Mac to validate against GRDB's exact rendered SQL.

### Correctness

Indexes are additive: they change no query text and no results. Worst case an index is unused
(dead weight on writes — four small partial/junction indexes, negligible against the existing
FTS5 triggers). `IF NOT EXISTS` keeps the migration idempotent even against a database that
somehow already carries the names.

### Test added

`hotQueryIndexes` in `Packages/GanchoKit/Tests/GanchoKitTests/GRDBClipboardStoreTests.swift`
(before `migrationIdempotent`): opens the standard in-memory store, migrates, and asserts
`pragma_index_list('clip')` / `pragma_index_list('clip_board')` contain the four names. Uses
the same `makeStore()` helper and the `store.writer.read` raw-SQL pattern already used by
`PerformanceHarnessTests.purgeForTest` under `@testable import`.

---

## 2. Thumbnail cache caps (A3-1.15)

Both app-side thumbnail caches were unbounded `[UUID: Image]` dictionaries with no eviction —
a monotonic leak in a weeks-long menu-bar agent session (each entry a decoded 480 px bitmap,
~0.9 MB). The keyboard extension already had the right pattern: FIFO order array + cap
(`Apps/GanchoKeyboard/KeyboardModel.swift:34-37, 162-167`). The same pattern is now applied to
both app stores with cap **64** (vs the keyboard's 24 — apps have more headroom, and 64 covers
a visible list plus scroll-back):

- `Apps/GanchoMac/ClipThumbnailStore.swift` — added `cacheOrder: [UUID]` + `maxCached = 64`
  (`:17-18`, both `@ObservationIgnored`, matching the file's existing pattern for non-rendered
  state) and FIFO eviction after insert in `ensureLoaded` (`:49-56`).
- `Apps/GanchoiOS/ClipThumbnailStore.swift` — same: `cacheOrder`/`maxCached` (`:18, 23`) and
  eviction in `ensureLoaded` (`:48-56`). (This file's `inFlight` is not `@ObservationIgnored`,
  so the new fields follow suit — each file's style mirrored exactly.)

Public surface unchanged (`cached(for:)` / `ensureLoaded(_:)`). Behavior on eviction is safe by
construction: an evicted id simply reloads through `ensureLoaded` next time its row appears —
the same lifecycle as a never-loaded row. The `evicted != item.id` guard (copied from
`KeyboardModel.swift:166`) protects the pathological cap ≤ 0 case; with 64 it never fires but
keeps the three implementations textually parallel. Rationale for FIFO over `NSCache`: matches
the in-repo precedent, keeps SwiftUI `@Observable` invalidation working on the plain dictionary,
and A3-2.7 already plans the unification into one shared capped cache later.

Memory bound: 64 × ~0.9 MB ≈ 58 MB worst case on macOS (full-blob decode at 480 px, see
A3-2.7's note that macOS should later switch to `thumbnailData(for:)`); iOS identical cap.

---

## 3. Skipped / out of scope

- **EXPLAIN QUERY PLAN test assertions** (A3-1.1's suggestion): needs a Mac to capture GRDB's
  exact SQL; the schema-level index-existence test stands in for now.
- **A3-1.3's other counter indexes** (`isPinned = 1`, `isSnippet = 1`, `isArchived = 1`) and
  **A3-1.4a/A3-1.8 retention/sync indexes** (`expiresAt`, `needsUpload`): not in this change's
  mandate; `idx_clip_sensitive` and `idx_clip_board_board` already cover the sensitive counter
  and the junction membership checks.
- **No query code touched** in `GRDBClipboardStore.swift` — migration section only, per scope.
- **Files edited:** `Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift`,
  `Apps/GanchoMac/ClipThumbnailStore.swift`, `Apps/GanchoiOS/ClipThumbnailStore.swift`,
  `Packages/GanchoKit/Tests/GanchoKitTests/GRDBClipboardStoreTests.swift`. Nothing else.
