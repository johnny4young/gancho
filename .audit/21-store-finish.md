# 21 — Store-layer finish (B-10, B-8, B-13, rekey flip flag)

Closes the four remaining store-layer items from `.audit/14` (B-8, B-10),
`.audit/13` (B-13), and `.audit/06` §5 (rekey rollout gate). Blind edits on
Linux (no toolchain): every change mirrors an in-file pattern exactly.

## B-10 — explicit reader-pool bound (perf, blind-safe)

`GRDBClipboardStore.init(directory:passphrase:)` now sets
`configuration.maximumReaderCount = 8` before the `DatabasePool` opens
(GRDBClipboardStore.swift, the configuration block). GRDB's default cap is 5;
8 matches the interactive read fan-out (list page + thumbnail decrypts +
search + sync feed) without over-provisioning — each reader is a connection +
page cache. Heavy scans are separately bounded and stay off this budget:
regex sweeps run under the A-2 ceiling, exports run through a single
read/cursor. Property name verified against GRDB's `Configuration`
(`public var maximumReaderCount: Int`, pool-only, default 5).

Not applied to `encryptedRawKeyAdopting` (RawKeyAdoption.swift) — that file
is owned by the raw-key path; fold the same line in there when that path is
next touched (tracked here so it isn't lost).

## B-8 — exportJSON peak-memory reduction (streamed-array, NOT streamed-encoder)

Outcome: **streamed-array**. `exportJSON(excludeSensitive:)` now gathers rows
through `fetchCursor` into ONE exactly-sized array (`reserveCapacity` from a
`fetchCount` in the same read transaction), skipping sensitive rows during
the walk when excluded. This removes `fetchAll`'s geometric-growth
over-allocation and the second `removeAll(where:)` pass — excluded rows never
materialize at all. The `ExportDocument` (version, exportedAt, clips[]) is
still encoded in ONE `JSONEncoder` shot with `.iso8601` +
`[.prettyPrinted, .sortedKeys]`, so output bytes are unchanged: same rows,
same `createdAt ASC` order, same encoder, same options.

Full encoder streaming remains **deliberately blocked**: hand-assembling the
`.prettyPrinted`/`.sortedKeys` layout byte-for-byte is implementation-defined
Foundation behavior, and `jsonExport`/round-trip tests (and users' existing
exports) depend on the exact bytes. `exportCSV(excludeSensitive:)` is the
fully streamed export format and covers the constant-memory need.

## B-13 — sensitive lifetime now overrides pins and boards (deliberate behavior change)

Decision per `.audit/13`: **sensitive items expire on the sensitive schedule
even when pinned or boarded** — a detected secret must not be preserved by
filing or favoriting it (the CHANGELOG promise: detected secrets always
follow the shorter Sensitive items limit). Snippets remain exempt: promotion
is an explicit, deliberate act of permanent curation.

`RetentionEngine.runPurge` clause 2 changed from

    isPinned = 0 AND isSnippet = 0 AND id NOT IN (SELECT clipID FROM clip_board)
        AND isSensitive = 1 AND createdAt <= ?

to

    isSnippet = 0 AND isSensitive = 1 AND createdAt <= ?

Clauses 1 (per-item `expiresAt`), 3 (per-kind), and 4 (global) are
byte-identical to before — pins, snippets, and board members stay exempt from
those. The tombstone/delete pairing inside `purge(where:arguments:)` is
untouched, so purged secrets still propagate deletion to iCloud.

Tests (RetentionEngineTests.swift):
- `pinsAreExempt` updated: drops the "pinned secret" seed (it now purges by
  design); pinned-old and pinned-timed still survive window + own-date.
- NEW `sensitiveExpiryOverridesPinsAndBoards`: a stale secret that is pinned
  AND on Favorites is purged (`sensitiveExpired == 1`); an identically
  curated non-sensitive clip survives; a stale sensitive SNIPPET survives.

Known stale docs (files outside this task's editable set — follow-up):
- `RetentionPolicy.swift:5` still says "Pins are exempt from ALL of them".
- CHANGELOG can now truthfully claim the sensitive-limit promise.

## Rekey flip flag — raw-key adoption env-gated, OFF by default (`.audit/06` §5)

`GRDBClipboardStore.encrypted(directory:keychainAccessGroup:)` now branches
after loading the Keychain key: when
`ProcessInfo.processInfo.environment["GANCHO_RAWKEY_ADOPT"] == "1"` (and the
build links SQLCipher), it opens via
`encryptedRawKeyAdopting(directory:passphrase:)`; otherwise the unchanged
derived-key `init(directory:passphrase:)`. The gate is the tiny testable
helper `rawKeyAdoptionEnabled(environment:)` (defaults to the process
environment), so tests pin both sides without mutating the process. No
build-system change, fully reversible, off by default; only the literal "1"
opts in. RawKeyAdoption.swift itself is untouched.

Flip it ONLY per the on-device rollout checklist in `.audit/06` §5 (raw-first
open one release, rekey the next, extension choreography verified on
hardware). Test: `GRDBClipboardStoreTests.rawKeyAdoptionFlag` asserts
absent/"0"/"true" stay off and "1" opts in. The full adoption/rekey behavior
itself is covered by the §6 raw-key test file when it lands (device-gated).

## Files touched

| File | Items |
|---|---|
| `Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift` | B-10, B-8, rekey flag |
| `Packages/GanchoKit/Sources/GanchoKit/RetentionEngine.swift` | B-13 |
| `Packages/GanchoKit/Tests/GanchoKitTests/RetentionEngineTests.swift` | B-13 tests |
| `Packages/GanchoKit/Tests/GanchoKitTests/GRDBClipboardStoreTests.swift` | flag test |

`GRDBEncryptionTests.swift` needed no change: encryption expectations
(needle scans, key gating, plaintext migration) are unaffected by all four
items, and the flag test lives with the store tests so it also runs on
non-SQLCipher builds.
