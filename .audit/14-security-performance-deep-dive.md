# 14 — Deep-dive: Security & Performance (exhaustive)

**Date:** 2026-07-02 · **Scope:** a second, deeper pass focused only on security and
performance, hunting findings the earlier dossiers (`.audit/02`, `.audit/03`, `.audit/05`,
`.audit/10`, `.audit/12`) did NOT cover. Every item is grounded in current source with
`file:line`; each is tagged **[NEW]** (not previously reported) or **[DEEPENED]** (adds
mechanism/impact to a prior finding). Severity P0–P3, effort S/M/L, and a "safe to apply
without a device" flag (this environment has no Swift toolchain; sync/crypto changes are
gated on CI + on-device verification by policy).

Legend for the last column: **✅ blind-safe** (self-contained, CI-verifiable) ·
**⚠️ CI-gated** (compiles-check only; behavior needs judgement) · **🔒 device-gated**
(touch only with hardware verification).

---

## Part A — Security

### A-1 [NEW] CKAsset temp files leak plaintext clipboard content and never get deleted — P1 / S / ⚠️

`ClipRecordMapper.makeAsset` (`Packages/GanchoKit/Sources/GanchoSync/ClipRecordMapper.swift:151-156`)
writes a synced clip's binary payload (image / file bytes) **unencrypted** to
`FileManager.default.temporaryDirectory/gancho-asset-<uuid>` and hands the URL to `CKAsset`.
A repo-wide grep shows **nothing ever deletes these files** (only reference is the write
itself).

- **Mechanism:** CloudKit copies the asset into its own managed store at upload time, but
  it does **not** remove the caller's source file. So every synced image/file clip leaves a
  plaintext copy in `tmp/`. The whole storage design goes to lengths to keep content sealed
  (SQLCipher DB + AES-GCM blobs + sealed thumbnails, per `docs/ARCHITECTURE.md` "Encryption
  at rest"); this path silently drops **unencrypted** clip bytes outside that boundary.
- **Impact:** (1) Privacy — the threat model (`docs/SECURITY-MODEL.md`: "Content exists in
  exactly four places") is violated; a fifth place (`tmp`) accumulates plaintext content,
  reachable by other processes/backup/forensics until the OS reaps tmp (days on macOS, and
  not guaranteed). (2) Disk growth — unbounded accumulation across sync cycles.
- **Fix (do NOT delete in `makeAsset` — CKSyncEngine reads the file later during batch
  send, so early deletion breaks the upload):**
  1. Write assets into a dedicated subdir `temporaryDirectory/gancho-ck-assets/`.
  2. In `CKSyncEngineAdapter.handleSentRecordZoneChanges` (`CKSyncEngineAdapter.swift:360`),
     after a record's `savedRecords` entry lands, delete that record's asset file.
  3. Belt-and-suspenders: on `CKSyncEngineAdapter` `start()`, sweep the subdir of any file
     older than ~1 h (covers crashes between write and send). Mirror `BlobStore.removeAll`'s
     directory-scan style.
  - Alternative if per-record mapping is awkward: write the asset **inside the encrypted
    blob store's directory tree in a temp area you own**, still sweeping after send.
- **Why ⚠️ not blind-safe:** deletion timing is coupled to CKSyncEngine's asset lifecycle;
  deleting too early drops the upload. Needs the send-completion hook + a sweep, and a
  round-trip test. Prescription is exact; implementation should land with the sync test suite.

### A-2 [NEW] Regex search is a local Denial-of-Service (ReDoS) on the DB reader — P2 / S / ✅

`GRDBClipboardStore.regexSearch` (`GRDBClipboardStore.swift:403-430`) compiles a
**user-supplied** `NSRegularExpression` and runs `firstMatch` against `title`, `preview`,
and full `contentText` for **every non-archived row** inside a `writer.read { }` block.

- **Mechanism:** two compounding costs. (1) No SQL `LIMIT`: the cursor walks the whole table
  until `results.count` reaches `limit`; a query that matches nothing scans every row.
  (2) `NSRegularExpression` (ICU) is backtracking — a pathological pattern (`(a+)+$`,
  `(.*a){20}`) against a long `contentText` exhibits catastrophic backtracking and can hang
  for seconds-to-minutes **per row**. Because it runs on the GRDB reader queue, it also
  stalls concurrent reads (list refresh, thumbnails).
- **Impact:** a user (or an MCP agent via `search_clips` with `mode: regex` — verify the CLI/
  MCP even expose regex mode; the CLI `--mode regex` does) can wedge the store. Not a content
  leak, but a reliability/DoS hole, and on iOS a wedged reader under a memory-tight extension
  can OOM.
- **Fix (blind-safe):**
  - Cap the work: add `.useUnixLineSeparators`-free timeout via a matching budget — ICU has
    no timeout, so bound it structurally: run the regex match on a **detached task with a
    deadline** and cancel/return partial results, OR pre-filter candidate rows with the
    existing FTS/`LIKE` narrowing before the regex pass, OR cap the scanned-row count and
    surface "narrow your search" past the cap.
  - Cheapest correct first step: add an explicit scanned-row ceiling (e.g. 5–10k) and a
    `contentText` length guard (skip regex on payloads > N KB, or match only a prefix), and
    document regex as "best-effort over recent items". All are self-contained in `regexSearch`.
  - Encourage the pre-narrowed path: `appendFilters` already lets kind/date/source shrink the
    cursor — make the UI apply a default recency window for regex mode.

### A-3 [DEEPENED] Direct-download license token has no expiry, device binding, or nonce — P2 / M / ⚠️

`LicenseToken` (`Packages/GanchoKit/Sources/GanchoKit/License.swift:9-17`) carries only
`licenseID` + `issuedAt`; `LicenseVerifier.verify` (`:61-71`) checks the Ed25519 signature and
decodes. Signing prevents **forgery**, but nothing prevents **sharing**: one purchased,
signed token opens Pro on unlimited machines forever.

- **Impact:** monetization integrity for the direct-download channel (not a privacy issue).
  A single token posted publicly unlocks Pro for everyone; there is no revocation surface.
- **Fix (⚠️ — changes the license format, coordinate with `LemonSqueezyStore` issuance):**
  add optional `expiresAt` (already anticipated by the doc comment) and/or a device-bound
  `activationFingerprint` (hash of a stable machine id) to the token; keep old tokens valid
  by treating missing fields as "no constraint" (forward-compatible, as the comment says).
  Add a periodic (offline-tolerant) online re-validation against Lemon Squeezy for high-value
  tiers. Keep the "works offline" property by only *soft*-gating on online checks.
- **Note:** this is deliberately out of the privacy/perf critical path; listed for
  completeness since the deep-dive touched the crypto surface.

### A-4 [NEW] Pasteboard veto is TOCTOU-racy against a fast A→B swap — P3 / M / ⚠️

`MacPasteboardMonitor.pollOnce` (`ClipboardCore/MacPasteboardMonitor.swift:195-240`) reads
`reader.currentTypes()` and runs the sensitive-type veto, then `scheduleRead` performs the
**content** read on a detached task via `reader.readPayload()`, which re-reads the *current*
pasteboard.

- **Mechanism:** the veto is computed on the types observed at `changeCount = N`. The detached
  read reads whatever is on the pasteboard when it runs. If content is replaced between the
  metadata read and the payload read, the payload is of the newer content but was gated by the
  older types. In practice a new write bumps `changeCount`, so the next `pollOnce` cancels the
  in-flight read and re-vetoes — the window is small and self-correcting. But it is a real
  read-before-fully-vetoed window for the current change.
- **Impact:** low; a theoretical path to reading content whose *current* types include a
  concealed marker that wasn't present at metadata-read time. Defense-in-depth gap against the
  "veto before read" invariant #2.
- **Fix:** inside the detached read, re-check `currentTypes()` against `SensitivePasteboardTypes.captureVeto`
  immediately before `readPayload()` and drop if now vetoed. ~3 lines, but touches the capture
  path so it wants the `ProductionMonitorTests` suite.

### A-5 [DEEPENED] MCP enable-state is a plaintext file any local process can flip — P2 / M / ⚠️

`MCPServerConfig` (`GanchoKit/MCPAccess.swift:58-89`) persists `{isEnabled, scope}` as
plaintext JSON in the store dir; `gancho enable --scope all` (or any process writing the file)
raises exposure. Already noted in `.audit/02`; deepening the **exploit chain**: a local
process with FS access can (1) write `mcp-config.json` with `scope: all`, (2) spawn
`gancho mcp`, (3) read every non-sensitive clip — no user interaction, no app involvement.
The sensitive veto still holds, so secrets are safe, but *all history* is exposed.

- **Fix (⚠️):** require the **app** to mint a capability the CLI must present to raise scope
  above `metadata` (e.g. an app-written token in the file the server validates), or at minimum
  post a user-visible notification (the app is running the menu-bar agent) when scope becomes
  `all` or when a new client first connects. Surfacing beats silence.

### A-6 [NEW / verify] `deleteAllSensitive` DELETE and FTS/tombstone consistency — P2 / S / ✅ (test-only)

`deleteAllSensitive` (`GRDBClipboardStore.swift:574-581`) runs `DELETE FROM clip WHERE
isSensitive = 1` and sweeps orphan blobs. With the B-5 tombstone work landed it now also
tombstones synced rows. Two things to verify on a device/CI: (1) the external-content
`clip_fts` index is kept in sync by GRDB's `synchronize(withTable:)` triggers on a **raw SQL**
DELETE (it should — triggers are schema-level — but external-content FTS is exactly where a
raw bulk delete can desync if a trigger was ever dropped); add an explicit test asserting an
FTS `MATCH` no longer returns a purged sensitive clip. (2) Same for the four `RetentionEngine`
DELETE clauses. Low code risk; the value is a regression test around raw-SQL deletes vs FTS.

### A-7 [NEW] Sensitive detector: masked preview can still leak the tail; entropy gate bypass — P3 / S / ✅

`SensitiveMasking.maskedPreview` (`GanchoAI/SensitiveDataDetector.swift:142-147`) renders
`"●●●● " + last 4 non-whitespace chars`. For short/structured secrets (a 6-digit OTP, a short
PIN) the last 4 chars are a large fraction of the secret. And `isProbablePassword` requires all
four character classes + entropy > 3.0, so a long all-lowercase high-entropy secret
(e.g. a 32-char base32 TOTP seed) is **not** flagged unless it hits a structured pattern.

- **Fix (blind-safe):** for very short flagged values, mask entirely (`●●●●`) rather than
  revealing 4 of, say, 6 chars; and lower the class requirement for long tokens (≥24 chars with
  entropy > 3.5 and ≥3 classes) to catch base32/hex secrets. Extend the 28-pattern suite in
  lockstep. Defense-in-depth; the `org.nspasteboard` veto remains the primary line.

### Security posture confirmed correct (no action — audited, for the record)
- SQLCipher whole-DB encryption incl. FTS index; random 256-bit key, never user-derived;
  `kSecAttrAccessibleAfterFirstUnlock` is the most-protective level compatible with background
  capture; `Failure` carries only `OSStatus` (`KeychainPassphraseStore`). Honest "not
  zero-knowledge" claim.
- Blob/thumbnail AES-GCM sealing with random per-seal nonce (CryptoKit `combined`); header
  magic gating; encrypted stores never vend a plaintext thumbnail URL (`BlobStore`).
- CloudKit content rides `encryptedValues`/`CKAsset`; only structural metadata is plain
  (`ClipRecordMapper`) — with the A-1 asset-tmp caveat above.
- No logging in engine modules (enforced by `NoContentLoggingTests`); telemetry is bucket-only
  by type construction; CloudKit imported only in `GanchoSync`.

---

## Part B — Performance

Performance budgets from `docs/ARCHITECTURE.md`: idle capture <0.5% CPU; exact search <50 ms
@100k; semantic <100 ms @10k; capture rules <10 ms; no main-thread content decrypt for
off-screen rows. The findings below are ordered by leverage.

### B-1 [DEEPENED] `pendingUploads()` decrypts every pending blob just to feed callers that need a count — P1 / M / ✅

`SyncLocalStore.pendingUploads` (`SyncLocalStore.swift:68-83`) fetches all dirty rows **and**
calls `content(for:)` on each — a blob read + AES-GCM decrypt per binary clip. It is called
from `CKSyncEngineAdapter.emitCurrentStatus` (just wants `.count`),
`reenqueuePendingWork` (wants ids), and `reconcilePendingChanges` (wants ids) —
`CKSyncEngineAdapter.swift:161,184,214` — plus the batch builder that actually needs content.

- **Impact:** every sync cycle and every status refresh decrypts the entire pending-upload set
  even when only a number or a set of ids is needed. On a large first sync this is O(pending) ×
  (disk + AES) for nothing. Amplified now that the B-4 fix flags more rows `needsUpload`.
- **Fix (blind-safe, additive):** add `pendingUploadCount() -> Int` (a `SELECT COUNT(*)`) and
  `pendingUploadIDs() -> [UUID]` (ids only, no content), and route the three count/id callers to
  them; keep `pendingUploads()` (with content) only for `nextRecordZoneChangeBatch`. Pure
  additions to the protocol + GRDB impl + three call-site swaps.

### B-2 [DEEPENED] `nextRecordZoneChangeBatch` builds a CKRecord for *every* pending upload up front — P1 / M / ⚠️

`CKSyncEngineAdapter.nextRecordZoneChangeBatch` (`:231-268`) calls `store.pendingUploads()`
and builds records for the whole set, then hands CloudKit a dictionary — but CloudKit asks for
records **by the pending changes in this batch** only. On a big backlog this materializes (and
decrypts) far more than the batch needs.

- **Fix (⚠️ — touches the sync record provider):** build records lazily scoped to
  `context`/`pendingChanges` for the current batch (fetch content per requested id), not the
  full pending set. Needs care with the sync test seam; prescription in `.audit/03` A3-1.9.

### B-3 [DEEPENED] Semantic search decodes and scalar-loops every vector per query — P2 / S–M / ✅

`SemanticSearch.semanticSearch` (`GanchoKit/SemanticSearch.swift`) fetches all `clip_embedding`
rows, decodes each `Data` → `[Float]`, and computes cosine with a scalar `for` loop, allocating
per row — while the vectorized `EmbeddingIndex` (`GanchoAI/EmbeddingIndex.swift`, `vDSP_dotpr`)
already exists but the DB path doesn't use it. (The blocking-read half of this was fixed in the
first pass; the compute half remains.)

- **Fix (blind-safe):** normalize-on-write (store unit vectors), then score with `vDSP_dotpr`
  over a contiguous buffer, mirroring `EmbeddingIndex.search`. Keep the linear scan; just
  vectorize it. At 10k×512 this is the difference between comfortably-under and near the 100 ms
  budget.

### B-4 [NEW] Retention now runs on *every* iOS foreground — throttle it — P2 / S / ✅

The B-10 fix (correctly) wired `IOSAppModel.runMaintenance()` to run `RetentionEngine.runPurge`
+ `TierEnforcement.enforce` on every return to foreground. `runPurge` does four DELETE passes,
tombstone INSERTs, **and** an orphan-blob directory sweep (`removeOrphanedBlobs` scans the whole
blobs dir + reads every `contentBlobHash`), and `TierEnforcement` does two full-table UPDATEs.
Foregrounding is frequent; doing all of this every time is wasteful and adds launch-adjacent
latency.

- **Fix (blind-safe):** throttle maintenance to at most once per interval (e.g. 5–15 min) using
  a persisted `lastMaintenanceAt` (UserDefaults), and/or move it off the foreground-critical
  path onto a short delay after first paint. Purely additive guard around the existing call.
  (Honest self-correction: this cost was introduced by our own B-10 fix, so it belongs here.)

### B-5 [NEW] `removeOrphanedBlobs` is an O(rows + files) full sweep after every purge — P2 / M / ✅

`GRDBClipboardStore.removeOrphanedBlobs` (`RetentionEngine.swift:81-89`) reads **all**
`contentBlobHash` values into a Set, then `contentsOfDirectory` over the whole blobs dir and
deletes the complement. Called after every `runPurge` (now every iOS foreground per B-4) and
after `deleteAllSensitive`.

- **Fix (blind-safe-ish):** the per-row `delete(id:)` path already reference-counts and removes
  blobs precisely; make the mass paths do likewise — collect the `contentBlobHash` of just the
  rows being deleted (a `RETURNING` clause or a pre-DELETE `SELECT` of the affected hashes) and
  ref-count-check only those, instead of diffing the entire directory. Fall back to the full
  sweep only rarely (e.g. a periodic GC), not on every purge. Reduces steady-state purge cost
  from O(table) to O(deleted).

### B-6 [NEW] Per-row `JSONEncoder()` allocation in the hot insert path — P3 / S / ✅

`ClipRow.init(item:)` (`GRDBClipboardStore.swift:802`) allocates a fresh `JSONEncoder` to encode
`tags` **per row**. On `importBatch` (bulk import / restore of 100k rows) that is 100k encoder
allocations. Same pattern for decode in `var item`.

- **Fix (blind-safe):** hoist a `static let tagsEncoder`/`tagsDecoder` (JSONEncoder/Decoder are
  thread-safe for encode/decode) and reuse. Micro, but it's on the bulk path.

### B-7 [NEW] Thumbnail generation runs synchronously on the writer queue during capture — P3 / M / ⚠️

`BlobStore.write` (`BlobStore.swift:50-67`) calls `cacheThumbnail` (ImageIO downsample + encode
+ seal) **inside** the store write. For a burst of image captures this puts image decode/encode
on the capture write path.

- **Fix (⚠️):** generate the thumbnail lazily on first list request (the cold-cache path in
  `thumbnailData(for:)` already handles this) OR off-load warm generation to a utility task after
  the row is persisted, so capture latency isn't gated on ImageIO. Verify no reader assumes the
  thumbnail exists synchronously after insert (the keyboard warms from data, so check that path).

### B-8 [DEEPENED] Streaming export before the store can be "opened to clients" — P2 / M / ⚠️

`exportJSON`/`exportCSV` (`GRDBClipboardStore.swift:630-659`) `fetchAll` the entire table into
memory and encode in one shot. At 100k rows + text this is a large transient allocation (and on
iOS a possible memory spike). Fix: stream rows through the encoder (chunked `fetchCursor` +
incremental JSON array / CSV lines) — prescription in `.audit/03` A3-1.13. Matters more now that
export is a first-class, sensitive-aware, per-tier feature.

### Performance confirmed sound (no action)
- Capture poll loop (adaptive 250 ms / 1.5 s, pause on lock, off-main reads, in-flight
  coalescing) — meets the idle-CPU budget by construction.
- v16 hot-query indexes (this branch) — planner-verified for `items()`, `recentForBrowse`, board
  filter, sensitive count.
- Keyboard extension thumbnail discipline (FIFO cap, decode small cache only) and the new app-side
  FIFO caps (this branch).
- Content-addressed blobs (single-store dedup), lazy thumbnails, metadata-only pagination.

---

## Suggested sequencing

**Land next (blind-safe, CI-verifiable):** B-1 (pending upload count/ids), B-3 (vDSP semantic),
B-4 (throttle iOS maintenance), B-5 (targeted orphan cleanup), B-6 (encoder reuse), A-2 (regex
DoS ceiling), A-7 (masking hardening). These are additive or self-contained and gated only by CI.

**Land with the sync test cycle (⚠️):** A-1 (CKAsset tmp cleanup — highest-value security item
here), A-4 (veto re-check), A-5 (MCP capability), B-2 (scoped batch build), B-7 (async thumb),
B-8 (streaming export).

**Device-gated (🔒):** none new here beyond the already-documented raw-key rekey flip (`.audit/06`).

**Top 5 by leverage:** A-1 (plaintext content leak) · B-1 (decrypt-to-count on every sync) ·
A-2 (regex DoS) · B-4 (per-foreground purge storm) · B-3 (vectorize semantic scan).

---

## Addenda — second review (expanded findings)

### A-8 [NEW] SharedInbox stores plaintext clipboard content in the App Group container — P2 / M / ⚠️

`SharedInbox.deposit` (`ClipboardCore/SharedInbox.swift:53-57`) writes each captured
`PreparedCapture` — which embeds the full `PasteboardCapture` payload (text, RTF, **image
bytes**) — as **plaintext JSON** into `<AppGroup>/inbox/<uuid>.json`, and `drainPrepared`
(`:69-100`) reads+deletes them app-side. Between the extension's deposit and the app's next
activation, clipboard content sits **unencrypted on disk**, outside the SQLCipher/AES-GCM
boundary the rest of the store maintains.

- **Mechanism / exposure window:** iOS Data Protection encrypts the file at rest tied to the
  passcode (mitigation), but (1) it is plaintext relative to Gancho's own sealed layer; (2) if
  the app is never reopened after shares, files **accumulate indefinitely** in plaintext; (3) a
  user can share a secret via the share sheet — the on-device sensitive detector runs app-side
  on drain, so a sensitive capture lives plaintext in the inbox until then; (4) it is a fifth
  content location not listed in `docs/SECURITY-MODEL.md` ("Content exists in exactly four
  places").
- **Fix (⚠️):** seal the envelope with the same key the store uses. The extension already reads
  the shared-keychain SQLCipher key (it opens the encrypted DB path), so it can `AES.GCM.seal`
  the JSON before writing and the app unseals on drain — reuse `BlobStore`'s
  `encodeForDisk`/`decodeFromDisk` (extract them into a small shared `SealedEnvelope` helper).
  At minimum, set explicit `FileProtectionType.completeUntilFirstUserAuthentication` on the
  write and cap inbox age/size with an eager background drain. Add a test that a deposited file
  is not readable as plaintext once sealing lands.

### Cross-cutting theme: content escapes the sealed store through handoff/temp paths

A-1 (CKAsset tmp), A-8 (SharedInbox), and — verify — any Share/keyboard scratch files form a
pattern: **the encryption-at-rest guarantee is airtight for the DB and blobs but leaks at the
process-boundary handoffs.** Architectural recommendation: introduce ONE `SealedEnvelope`
primitive (seal/open with the store key, reusing `BlobStore`'s AES-GCM path) and route every
cross-process/temp write through it — CKAsset staging, the share inbox, any future desktop
extension inbox. Then the "content exists in exactly four places" claim becomes enforceable by
construction, and `docs/SECURITY-MODEL.md` can assert it truthfully. Single S–M primitive,
several call sites; sequence it right after A-1/A-8 land.

### B-9 [DEEPENED] FTS write-amplification grows with the sync-correctness fixes — P3 / S / observe

`clip_fts` is external-content FTS5 synchronized by triggers on `clip` (migration v2). The B-1..
B-5 sync fixes legitimately UPDATE `title`/`preview`/`contentText` more often (remote upserts,
membership churn bumping `updatedAt`), and every such write re-indexes the row in FTS. This is
correct behavior, not a bug, but at 100k rows under active sync it is measurable write cost.
- **Action:** none required now; just **measure** FTS write cost during the on-hardware sync
  verification (it shares the same test window as the raw-key rekey). If it dominates, batching
  remote upserts in fewer transactions is the lever.

### B-10 [NEW] Default-bounded reader pool can contend under concurrent load — P3 / S / ✅

`GRDBClipboardStore` opens a `DatabasePool` with default configuration
(`GRDBClipboardStore.swift:60`); GRDB pools bound concurrent readers (default `maximumReaderCount`).
Under a burst — list refresh + several thumbnail decrypts + a semantic scan + a sync fetch — read
tasks can queue behind the cap. Combined with the (now-fixed) blocking-read and the still-present
regex full-scan (A-2), a single slow reader (a big regex or semantic scan) can head-of-line-block
interactive reads.
- **Fix (blind-safe, tune-only):** set `configuration.maximumReaderCount` explicitly (e.g. 8–10)
  to match the interactive read fan-out, and keep heavy scans (regex, export) off the interactive
  pool by bounding them (A-2/B-8). Measure before/after; do not over-provision (each reader is a
  connection + cache).

**Revised top-5 (post-addenda):** A-1 + A-8 as a pair (plaintext-escape via a shared
`SealedEnvelope`) · B-1 (decrypt-to-count) · A-2 (regex DoS) · B-4 (per-foreground purge) ·
B-3 (vectorize semantic).
