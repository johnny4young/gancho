# 16 — Store-cluster fixes (A-2, B-5, B-6, B-8 from `.audit/14`)

**Date:** 2026-07-02 · **Scope:** the four store-layer findings from
`.audit/14-security-performance-deep-dive.md`, implemented in
`GRDBClipboardStore.swift` and `RetentionEngine.swift` (plus their test suites).
No migration was touched; no engine logging added; all changes are blind-safe
and CI-verifiable.

---

## A-2 — Regex search DoS ceiling (P2, security) — DONE

`GRDBClipboardStore.regexSearch` now bounds both axes of the ReDoS surface:

- **Row ceiling:** the SQL gains `LIMIT ?` bound to a new internal constant
  `GRDBClipboardStore.regexScanCeiling = 5000`. A pattern that matches nothing
  examines at most 5 000 (newest-first, post-filter) rows instead of walking
  the whole table on the reader queue. The bound is applied in SQL, so the
  cursor itself stops — not just the Swift loop.
- **Haystack cap:** `regexHaystackLimit = 100_000` — each row's `contentText`
  is matched only on its first 100k characters (`title`/`preview` always match
  in full), so catastrophic backtracking on one giant clip is bounded.
- **Semantics documented** on the method: regex is best-effort over recent
  items; kind/app/date/board filters extend its reach.

Results still return up to `limit`, ordered newest-first as before.

**Tests (`ClipSearchTests`):**
- `regexScanCeiling` — seeds `ceiling + 2` rows via `importBatch`; a pattern
  matching only the newest row still returns it, and a pattern matching only
  the row *past* the ceiling returns empty (ceiling honored).
- `regexOversizedHaystack` — a 150k-char clip matches on markers inside the
  100k prefix and not on markers past it; no blow-up.

## B-5 — Targeted orphan-blob cleanup (P2, perf) — DONE (both mass paths)

Steady-state purge cost drops from O(table + files) to O(deleted):

- New internal helper `GRDBClipboardStore.removeBlobsIfOrphaned(_:)`
  (`RetentionEngine.swift`): takes the candidate hashes of just-deleted rows,
  ref-checks each (`contentBlobHash == hash → fetchCount == 0`) and deletes
  only true orphans — the mass-path counterpart of the per-row `delete(id:)`
  reference check. Never deletes a blob a surviving row still shares.
- `RetentionEngine.runPurge`: the in-transaction `purge(where:)` helper now
  runs `SELECT DISTINCT contentBlobHash … WHERE contentBlobHash IS NOT NULL
  AND <same predicate>` BEFORE each tombstone+DELETE pair, unioning candidates.
  The write transaction returns `(PurgeSummary, Set<String>)`; blob files are
  removed AFTER the transaction (blobs are files, not rows), then `logPurge`
  runs — ordering/semantics otherwise preserved, and
  `summary.orphanedBlobsRemoved` keeps its meaning.
- `GRDBClipboardStore.deleteAllSensitive`: same pattern — hashes captured
  inside the write before the tombstone insert + `DELETE`, precise cleanup
  after.
- The full-sweep `removeOrphanedBlobs()` is KEPT (doc updated) as the explicit
  garbage-collection / repair entry point; it is no longer on any steady-state
  path. (Same benign TOCTOU window between the ref-check read and the file
  delete as the pre-existing `delete(id:)` path — unchanged risk posture.)

**Tests:**
- `RetentionEngineTests.purgeKeepsSharedBlobs` — two clips share one
  content-addressed blob; purging one keeps the file (and
  `orphanedBlobsRemoved == 0`), purging the last removes it.
- `GRDBClipboardStoreTests.deleteAllSensitiveKeepsSharedBlobs` — a sensitive
  and a plain clip share a blob; the panic delete keeps the file and the plain
  clip's content stays readable; deleting the last reference removes it.
- Existing `orphanSweepAndCounters` still passes: the purged image's blob is a
  candidate with zero survivors → counted and removed as before.

## B-6 — Shared tags JSON coders (P3, perf) — DONE

`ClipRow` gains `static let tagsEncoder = JSONEncoder()` /
`static let tagsDecoder = JSONDecoder()` (default options — stored bytes
unchanged; encode/decode calls are safe to share across threads).
`ClipRow.init(item:)` and `var item` use them, removing the per-row allocation
on the bulk import/read paths. There was no pre-existing shared coder for this
column. Round-trip coverage: the existing
`GRDBClipboardStoreTests.textRoundTrip` asserts `fetched.tags == item.tags`.

## B-8 — Streaming export — CSV DONE, JSON deliberately deferred

- `exportCSV(excludeSensitive:)` now iterates a `fetchCursor` inside one
  `writer.read`, appending each row's escaped line (sensitive rows skipped
  in place when excluded) — no full `[ClipRow]` materialization; only the
  output text accumulates. Output is byte-identical: same `createdAt ASC`
  order, same header, same `csvEscape`, same exclude semantics.
- `exportJSON(excludeSensitive:)` is **unchanged** (reduced scope, per the
  `.audit/14` prescription's fallback): hand-assembling the `clips` array
  would have to reproduce `JSONEncoder`'s `.prettyPrinted` + `.sortedKeys`
  layout byte-for-byte, which is encoder-implementation-defined and cannot be
  verified without a toolchain. Noted in the method doc. **Follow-up:** stream
  JSON by encoding each row compactly and re-indenting deterministically, or
  relax the byte-compat requirement once the importer tolerates compact
  output.

**Tests:** existing `jsonExport`, `csvExport`, `csvFormulaInjectionGuard`,
`exportExcludesSensitive` all still apply; new
`GRDBClipboardStoreTests.csvStreamedOrder` pins the streamed CSV's ordering
and in-place sensitive skipping.

---

## Files touched

| File | Findings |
|---|---|
| `Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift` | A-2, B-5 (`deleteAllSensitive`), B-6, B-8 |
| `Packages/GanchoKit/Sources/GanchoKit/RetentionEngine.swift` | B-5 (`runPurge`, `removeBlobsIfOrphaned`, full-sweep doc) |
| `Packages/GanchoKit/Tests/GanchoKitTests/ClipSearchTests.swift` | A-2 tests |
| `Packages/GanchoKit/Tests/GanchoKitTests/RetentionEngineTests.swift` | B-5 test |
| `Packages/GanchoKit/Tests/GanchoKitTests/GRDBClipboardStoreTests.swift` | B-5 + B-8 tests |
