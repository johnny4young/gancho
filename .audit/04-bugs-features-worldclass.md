# Gancho — Deep Audit 04: Bugs, New Functionality, World-Class Roadmap

**Date:** 2026-07-01 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Scope:** goes *deeper* than `.audit/gancho-audit-report.md` (read first; its findings F-1.x…F-7.x are
not repeated here except where new evidence changes their severity). This pass hunted correctness
edge cases in the retention/tier/sync triangle, the mappers, dedupe, the classifier/detector, the
MCP/CLI surface, and export/import round-trips — then builds the feature and roadmap story on top.

> **Environment caveat:** Linux container, no Swift toolchain — every finding is from reading the
> source (file:line cited, with a concrete failing input/state), not from a run. Nothing here was
> compiled or executed; the handful of findings that depend on GRDB/CKSyncEngine runtime behavior
> say so explicitly. Documentation only; no code was changed.

Severity: **P0** data-loss / broken stated guarantee · **P1** fix before public release ·
**P2** should-fix · **P3** nice-to-have. Effort: **S** ≤½ day · **M** 1–3 days · **L** >3 days.

---

## PART A — Bugs & correctness edge cases (ranked)

### A.1 The sync-clobber cluster (the most important finding of this audit)

The root defect is one line — `SyncLocalStore.applyRemoteUpsert` writes the **whole `ClipRow`**
(`finalRow.upsert(db)`, `Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift:145`) built from a
`ClipItem` that **cannot carry the local-only columns**, because `ClipRecordMapper` never encodes
them (`Packages/GanchoKit/Sources/GanchoSync/ClipRecordMapper.swift:41-77` sets neither `keyword`,
`uses`, nor anything for `isSnippet`/`isArchived`, and `ClipRow(item:)` defaults `isSnippet=false`,
`isArchived=false` — `GRDBClipboardStore.swift:691-694, 696-717`). Everything below falls out of it.

| ID | Sev | Eff | Finding |
| --- | --- | --- | --- |
| **B-1** | **P0** | M | **A remote update silently demotes a snippet — and retention then deletes it.** Failing state: promote a clip to a snippet on the Mac (`SnippetLibrary.swift:18-30`, sets `isSnippet=1`); later pin/board/edit the *same synced clip* on the iPhone (any edit bumps `updatedAt` and re-uploads); the Mac fetches the record → `applyRemoteUpsert` LWW check passes (remote newer) → `upsert` writes `isSnippet=0, keyword=NULL, uses=0`. The "permanent, retention-exempt" snippet is now an ordinary clip; the next `RetentionEngine.runPurge` (Mac, every 300 s — `AppModel.swift:1229`) **deletes it** once past its window. Same mechanism wipes a snippet's `keyword` and `uses` even when it survives. **Fix:** make `applyRemoteUpsert` an explicit column-list UPDATE/INSERT that never touches `isSnippet`, `isArchived`, `keyword`, `uses` (or merge them from the existing row before upserting). Add a round-trip test: promote → remote edit → assert still a snippet. |
| **B-2** | **P0/P1** | M | **A remote update wipes locally attached OCR text.** `attachExtractedText` stores extracted words in `contentText` for image clips (`SnippetLibrary.swift:67-73`); a remote record for a binary clip decodes with `content == nil` (asset path) or over-limit assets decode with no content at all (`ClipRecordMapper.swift:70-77, 102-117`), so the upsert writes `contentText=NULL` — screenshots silently stop being searchable after any cross-device edit. Same fix as B-1 (content columns only when the remote actually carries content). |
| **B-3** | **P1** | S/M | **Stale remote board membership overwrites newer local membership — unconditionally.** `handleFetchedRecordZoneChanges` calls `store.setBoardMembership(...)` on **every** modification, *outside* the LWW check (`CKSyncEngineAdapter.swift:345-349`; same in the `serverRecordChanged` path `:400-407`). `applyRemoteUpsert` correctly skips a remote older than the local row — but the membership replace still runs and `DELETE FROM clip_board WHERE clipID = ?` wipes the local set (`Pinboards.swift:188-207`). Failing sequence: device A adds clip→board (`assign`, which sets `needsUpload=1` but **does not bump `updatedAt`** — `Pinboards.swift:124-132`); before A uploads, a fetch delivers the pre-add record (equal `updatedAt` → remote wins ties) → upsert runs, **resets `needsUpload=0`** (`SyncLocalStore.swift:147-148`), and `setBoardMembership` deletes the junction row. The add is gone locally *and* will never upload. **Fix:** (a) gate `setBoardMembership` behind the same LWW decision (have `applyRemoteUpsert` return applied/skipped); (b) `assign`/`unassign` should bump `updatedAt`; (c) treat membership as a set-merge for concurrent add/remove (the first audit's F-4.4 — this pass shows it is worse than "last writer wins": the loser is silently reverted *and* de-queued). |
| **B-4** | **P1** | S | **Pin/unpin never syncs at all.** `setPinned` bumps `updatedAt` but not `needsUpload` (`Pinboards.swift:57-63`), and *no call site enqueues*: Mac `togglePin` → `AppModel.swift:982`, iOS `togglePin` → `GanchoiOSApp.swift:717-721`, Shortcuts `PinClipIntent.swift:18`. `pendingUploads()` selects `syncSystemFields IS NULL OR needsUpload = 1` (`SyncLocalStore.swift:68-77`) — an already-synced clip with a flipped pin matches neither. The record still carries `isPinned` (`ClipRecordMapper.swift:50`) so the docs' "only `isPinned` syncs (boards are device-local)" promise is exactly the part that doesn't work. **Fix:** `setPinned` sets `needsUpload=1`; call sites call `syncEngine.enqueue([item])` (as capture does). Add an adapter test: pin → `pendingUploads` contains the clip. |
| **B-5** | **P1** | M | **Retention purges, `deleteAllSensitive`, and non-sync `delete(id:)` never write tombstones — purged secrets live on in iCloud and resurrect.** `RetentionEngine.runPurge` issues raw `DELETE`s (`RetentionEngine.swift:27-67`); `deleteAllSensitive` too (`GRDBClipboardStore.swift:574-581`, called by the iOS "Clear Sensitive" panic intent `CaptureIntents.swift:90`); `delete(id:)` (`GRDBClipboardStore.swift:538-556`) is used whenever `syncEnabled` is false (`AppModel.swift:749-750`, `GanchoiOSApp.swift:728`). None insert into `sync_tombstone`, and sensitive clips **do** sync (`ClipRecordMapper.swift:51` + full `contentText` in `encryptedValues`). Failing state: a detector-flagged secret syncs up, expires, the purge deletes it locally on every device — the CKRecord (with the secret, E2E-encrypted but present) stays in the private DB **forever**, and a new device / reinstall / zone re-fetch resurrects it into local history. This inverts the product's central promise ("auto-expires after 10 minutes"). **Fix:** purge/panic paths must collect the affected IDs first (SELECT before DELETE), insert tombstones when the row has `syncSystemFields`, and the app should `enqueueDeletion` after a purge; alternatively (stronger): **never upload sensitive clips at all** — one `WHERE isSensitive = 0` in `pendingUploads()` removes the whole class. Also add a tombstone check inside `applyRemoteUpsert` so a pending local deletion can't be resurrected by a concurrent remote edit (`SyncLocalStore.swift:115-150` never consults `sync_tombstone`). |
| **B-6** | **P2** | S | **Board renames can permanently diverge between devices.** `Pinboard` has no `updatedAt` and `applyRemoteBoardUpsert` applies unconditionally (`SyncLocalStore.swift:202-222`). Failing sequence: A renames board→"Work-A", B (offline) renames→"Work-B"; both upload, both fetch the other's record and apply it → **A shows "Work-B", B shows "Work-A"**, both `needsUpload=0`, no further convergence. **Fix:** add `modifiedAt` to the board record + LWW, or resolve conflicts through `handleFailedSave` only. |
| **B-7** | **P2** | S | **Conflict-losing local edits stall until next launch.** In `handleFailedSave(.serverRecordChanged)` where the *local* row is newer, `applyRemoteUpsert` correctly keeps the local row (`needsUpload` stays 1) — but nothing re-adds a `.saveRecord` pending change; the failed change was consumed. The re-upload only happens at the next `start()` via `reenqueuePendingWork` (`CKSyncEngineAdapter.swift:182-205`). Until an app restart the UI shows `pending(N)` forever. **Fix:** in the local-wins branch, `syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])` (mirroring the zone-not-found branch `:408-412`). *(Runtime-behavior caveat: verify CKSyncEngine doesn't auto-retry these.)* |
| **B-8** | **P2** | S | **Corrupt archived system fields brick a record's sync permanently.** `ClipRecordMapper.record` returns nil when `decodeSystemFields` fails (`ClipRecordMapper.swift:33-35`); the batch provider then has no record for the pending save, the row keeps `needsUpload=1`, and `reconcilePendingChanges`… keeps it valid (it *is* in `pendingUploads`) → the send queue re-attempts a save it can never build. **Fix:** on unarchive failure, mint a fresh `CKRecord` (server will answer `serverRecordChanged`, which the conflict path already handles) instead of returning nil. |
| **B-9** | **P2** | M | **First-sync memory/IO blowup: `pendingUploads()` loads full content (including blobs up to 50 MB each) for every pending clip — and is called four times per `start()`.** `pendingUploads` does an N+1 `content(for:)` (`SyncLocalStore.swift:68-83`); `start()` calls it via `reenqueuePendingWork`, `reconcilePendingChanges`, `nextRecordZoneChangeBatch`, and `emitCurrentStatus` — the last one just to `.count` it (`CKSyncEngineAdapter.swift:161`). A 10k-clip first sync with images decodes every blob repeatedly. Also `makeAsset` writes a temp file per binary clip per batch-provider call and never deletes them (`ClipRecordMapper.swift:151-156`). **Fix:** add `pendingUploadIDs()`/`pendingUploadCount()` (IDs only) for the three non-batch callers; load content lazily per record inside the batch provider; delete asset temp files in `handleSentRecordZoneChanges`. |

### A.2 Retention / tier / archive correctness

| ID | Sev | Eff | Finding |
| --- | --- | --- | --- |
| **B-10** | **P0** | M | **iOS never runs the retention engine or tier enforcement — the "10-minute secret expiry" is false on iPhone/iPad.** The only `runPurge`/`enforce` call sites in any app are Mac (`AppModel.swift:1240-1241`, plus tier-change `:794`). Nothing in `Apps/GanchoiOS`, the keyboard, widgets, or share extension purges, and **no read path filters `expiresAt`** (grep: `expiresAt` appears only in schema/mapper/engine). Failing state: iPhone-only user copies an AWS key → masked, "auto-expires it after 10 minutes" says the iOS UI verbatim (`Apps/GanchoiOS/IntelligenceView.swift:92`, `Localizable.xcstrings:1364`) → the row (and revealable full secret) persists indefinitely. Free-tier ceilings (30-day/2,000) are likewise never enforced on iOS. **Fix:** run `RetentionEngine` + `TierEnforcement` on iOS at foreground activation and via `BGAppRefreshTask`; and add a defense-in-depth read-time filter (`expiresAt IS NULL OR expiresAt > now`) to `items`, `recentForBrowse`, `search`, keyboard/widget feeds so an expired secret is invisible even before the purge lands. |
| **B-11** | **P1** | S | **`TierEnforcement` still gates on the legacy `pinboardID` column — dead since the v10 junction migration.** Both free-tier UPDATEs use `pinboardID IS NULL` (`TierEnforcement.swift:40, 51`), but membership has lived in `clip_board` since v10 (`GRDBClipboardStore.swift:300-319`); `pinboardID` is only ever *read* by the one-time v10 backfill — nothing writes it anymore. Failing state: free user files a clip on a board today → 30 days later `enforce(tier:.free)` archives it, contradicting the type's own doc ("board members are never archived", `TierEnforcement.swift:6-7`). Bonus inconsistency: `items(inBoard:)` does **not** filter `isArchived` (`Pinboards.swift:163-173`), so the archived member still shows in the board view but vanishes from history/search/counts. **Fix:** replace with `id NOT IN (SELECT clipID FROM clip_board)`; decide whether board views show archived members and make all surfaces agree. |
| **B-12** | **P1** | S | **`TierEnforcement` archives sensitive clips despite claiming it never does.** The doc comment says "Pins, board members, and sensitive items are never archived" (`TierEnforcement.swift:6-7`) but neither UPDATE has an `isSensitive = 0` clause (`:38-56`). Failing state (Mac, free tier, >2,000 items): a not-yet-expired secret lands beyond the item ceiling → archived → disappears from `sensitiveCount()` (which excludes archived, `GRDBClipboardStore.swift:562-569`) so the Privacy Center's "Secrets masked" under-counts, while the secret still sits on disk and in exports. **Fix:** add `AND isSensitive = 0` (retention owns their lifecycle), plus a test. |
| **B-13** | **P2** | S | **Boarding (including Favorites) or per-item-pinning a secret cancels its expiry — silently.** Extends F-4.2 with two sharper edges this pass verified: (1) *all four* purge clauses exclude board members (`RetentionEngine.swift:30, 37, 46, 55`), including the **per-item `expiresAt`** clause — so a detector-stamped 10-minute secret dropped on the built-in Favorites board (`Pinboard.favoritesID`, one tap in every UI) never expires; (2) the exemption interacts with B-5: the un-expiring secret keeps syncing. **Fix:** sensitive expiry (clauses 1–2) should apply regardless of pin/board/snippet status, or the UI must warn when favoriting a sensitive clip ("this keeps the secret forever"). Pin down in a test either way; today the CHANGELOG's "detected secrets always follow the shorter Sensitive items limit" is false three different ways. |
| **B-14** | **P1/P2** | S | **Re-copying archived content makes the copy invisible.** `insert` dedupe matches on `contentHash + sourceDeviceName` with no `isArchived` check (`GRDBClipboardStore.swift:475-492`); the dupe path updates timestamps and returns the **archived** row. Failing state: free-tier user re-copies text that tier enforcement archived last month → nothing appears in history (lists filter `isArchived = 0`), capture looks broken. **Fix:** in the dedupe branch, also set `isArchived = 0` (a fresh copy is fresh activity — it should re-enter the newest-N window). |
| **B-15** | **P2** | S | **Re-copying a secret near its expiry deletes it moments later.** Dedupe keeps the existing row's `expiresAt` (`GRDBClipboardStore.swift:484-489` updates only `lastUsedAt`/`updatedAt`), so copying the same API key at minute 9 of 10 leaves the stale expiry — purged at minute 10 despite being just copied. **Fix:** dedupe branch should refresh `expiresAt` (and `isSensitive` decoration) from the incoming item when the incoming item is sensitive. |
| **B-16** | **P3** | S | **Orphaned embeddings accumulate forever.** `clip_embedding` (v7, `GRDBClipboardStore.swift:262-270`) has no FK cascade and no sweep — `delete`, purges, and remote deletions leave vectors behind; `removeOrphanedBlobs` covers blobs only. Cosmetically filtered by the JOIN, but the table grows unboundedly and each semantic query decodes every orphan. **Fix:** `DELETE FROM clip_embedding WHERE clipID NOT IN (SELECT id FROM clip)` in the purge pass (and a cascade in a v16 migration). |

### A.3 Classifier / detector false results

| ID | Sev | Eff | Finding |
| --- | --- | --- | --- |
| **B-17** | **P2** | S | **Luhn-valid phone numbers are masked and auto-deleted in 10 minutes.** `RuleClassifier.isCreditCard` accepts any 13–19 digit run passing Luhn (`RuleClassifier.swift:96-103`) and runs **before** the phone data-detector (`:23-25`); `SensitiveDataDetector.containedCardCandidate` has the same shape (`SensitiveDataDetector.swift:54-61`), so `SensitiveIngestionPolicy` stamps a 10-minute expiry. ~1 in 10 random digit runs passes Luhn. Failing input: a 13-digit international number without `+` (e.g. an Indonesian mobile `6281234567890` when it Luhn-validates) → classified `creditCard`, preview masked, deleted 10 minutes later — the user loses a phone number they copied on purpose. **Fix:** require card-plausibility beyond Luhn (IIN prefix table: 3x/4x/5x/6x, and grouping shape `4-4-4-4`/`4-6-5`), or run the phone detector first for `+`-prefixed/spaced shapes. Add regression inputs to the 28-case suite. |
| **B-18** | **P3** | S | **Detector order lets a JWT-looking Stripe/GitHub string be missed, and `alg:none` JWTs are never JWTs.** `isJWT` requires 3 non-empty base64url segments (`RuleClassifier.swift:34-42`); unsecured JWTs (`header.payload.` — empty signature) fail `isBase64URL(_:)`'s non-empty rule and fall through to text. Pedantic but these appear in security testing workflows. Also `DevActions.decodeJWT` uses `split(separator: ".")` *with* empty-drop (`DevActions.swift:81-83`) so it can't decode them either — the two disagree with each other's parsing. **Fix:** accept an empty third segment in both, flag "UNSIGNED" in the decode output. |
| **B-19** | **P3** | S | **`maskedPreview` leaks the last 4 characters of every secret, not just cards.** `SensitiveMasking.maskedPreview` (`SensitiveDataDetector.swift:142-147`) shows the final 4 non-whitespace chars of AWS secrets, Stripe keys, and context-detected passwords in every list, widget-adjacent surface, and export of previews. Last-4 is a *card* convention; for a 12-char password it's a third of the alphabet-space gone. **Fix:** last-4 only for `creditCard`; full mask (`●●●●`) otherwise. |
| **B-20** | **P3** | S | **`convertColor` mis-parses CSS 8-digit hex.** `parseColor` drops the **first** two hex digits of an 8-digit color (`DevActions.swift:199-204`) — i.e. assumes `#AARRGGBB` — while CSS (and the design tools users copy from) writes `#RRGGBBAA`. Failing input: `#FF000080` (red @ 50%) → output claims `hex: #000080` (navy). **Fix:** treat 8-digit as `#RRGGBBAA`, keep alpha in the output. |

### A.4 CLI / MCP / import-export edges

| ID | Sev | Eff | Finding |
| --- | --- | --- | --- |
| **B-21** | **P2** | S | **`PinClipIntent` hardcodes `isPro: false`** (`Apps/GanchoiOS/PinClipIntent.swift:15`) — a paying Pro user with ≥15 pins gets "Free plan pin limit reached." from Siri/Shortcuts. **Fix:** read the entitlement like the in-app paths do. |
| **B-22** | **P2** | S | **Mac capture enqueues the pre-dedupe item, not the stored one.** `AppModel.swift:329-330` inserts then `sync.enqueue([item])` with the *original* item; on a dedupe hit the stored row has a different UUID, so the adapter flags a nonexistent id (`UPDATE … WHERE id = ?` no-op) and registers a `.saveRecord` no provider can ever build — a phantom pending change until the next `reconcilePendingChanges`. iOS gets this right (`GanchoiOSApp.swift:881-882` enqueues `stored`). **Fix:** enqueue the returned `stored` item. |
| **B-23** | **P2** | M | **`.ganchoarchive` round-trip silently loses boards, board membership, and pins-per-board structure — and skips missing blobs without reporting.** Export writes only `ClipRow`s (`GanchoArchive.swift:51-68`; `ClipRow` has no board columns) — `pinboard` and `clip_board` never travel, so the 0.3.0 "back up and restore your history" flow restores clips with all boards gone (Favorites membership included). Export also `continue`s over a missing blob (`:76-77`) and still counts the row in `clipCount`, so a restore yields image rows whose `contentBlobHash` dangles → `content(for:)` returns nil, thumbnail blank, no error anywhere. **Fix:** bump archive to v2 adding `boards.json` + `memberships.json` (restore keeps v1 compatibility); on export, either fail or record `missingBlobs` in the manifest and surface it; on restore, validate every referenced hash exists. This is the "no data hostage" claim — it should be *complete*. |
| **B-24** | **P2** | S | **MCP `boards` scope actually means "pinned", post-v10.** The runner filters `!$0.isPinned` in all three read tools (`MCPToolRunner.swift:67, 91-93, 141`), while the scope is documented as "clips you marked (pinned / on a board)" (`MCPAccess.swift:9-10`, `docs/INTEGRATIONS.md`). Since v10 made boards orthogonal to pins, a clip deliberately filed on a board (arguably the *stronger* curation signal) is invisible to agents in `boards` scope, and `create_pin --board` itself force-pins as a workaround (`MCPToolRunner.swift:116-119`). **Fix:** scope test = `isPinned OR clip_board membership` (add `boardIDs(forClip:)` to `MCPClipStore`), and update the docs. |
| **B-25** | **P3** | S | **MCP `get_clip` serves full content of tier-archived clips.** `item(id:)` doesn't filter `isArchived` (`MCPAccessStore.swift:10-14`), so an agent holding an old id reads content the free tier has hidden from every human surface. Not a privacy hole (user's own data) but an inconsistency with "archived = invisible until Pro". **Fix:** treat archived like not-found in MCP reads. |
| **B-26** | **P3** | S | **CLI flag parser can't take values that start with `--`.** `Options` (`GanchoCLI.swift:303-321`): `gancho save --title "--draft"` consumes `--title` as a bare flag and `--draft` as another flag — the snippet gets an auto title with no error. Also `--limit abc` silently becomes the default. **Fix:** `--key=value` support or a `--` terminator; warn on unparseable ints. |
| **B-27** | **P3** | S | **`importCSV` recognizes only lowercase `"true"` for pins** (`ClipImporter.swift:46-47`) — `TRUE`/`1`/`yes` (Excel's defaults) silently import unpinned. Its RFC-4180 parser also strips bare `\r` mid-field outside quotes (`:142`). **Fix:** case-insensitive boolean set; treat `\r` as row-end only when followed by `\n`. |
| **B-28** | **P3** | S | **Docs vs. code: "Sensitive clips are never exposed through any integration"** (`docs/INTEGRATIONS.md:10-12`) — but `gancho export` (JSON/CSV) dumps full sensitive `contentText` (F-3.2) and `gancho copy <id>` pastes it; both are integrations by the doc's own definition. The sentence should say "through the MCP server"; better, fix the export default (F-3.2) so the sentence becomes true. |
| **B-29** | **P3** | S | **Silent `try?` inventory that hides user-visible failures.** The worst offenders found: every store call in `handleFetchedRecordZoneChanges`/`handleSentRecordZoneChanges` (`CKSyncEngineAdapter.swift:339-379` — a failed `applyRemoteUpsert` is indistinguishable from success; the record's change is acknowledged and never re-fetched → permanent divergence); `enqueue`'s `try? markNeedsUpload` (`:89`) which can silently produce the exact stale-save state `reconcilePendingChanges` then *drops*; and both apps' `try? await grdb.deleteForSync` (`AppModel.swift:747`, `GanchoiOSApp.swift:725`) — a failed delete still enqueues the CK deletion → the clip disappears from other devices but survives locally. **Fix:** route these through `DiagnosticLog` (the content-free error log added in 0.3.0 exists for exactly this) and, for `applyRemoteUpsert` failures, do not persist the record's system fields so it re-syncs. |
| **B-30** | **P3** | S | **`ClipRow.item` masks identity corruption with `UUID() ?? `.** A row whose `id` fails to parse gets a *fresh random UUID on every fetch* (`GRDBClipboardStore.swift:721`), so delete/pin/board actions target a UUID that doesn't exist in the DB — actions on that row silently do nothing, forever. Same pattern in `PinboardRow.board` (`Pinboards.swift:300`). **Fix:** skip (and diagnostically count) undecodable rows instead of laundering them. |

**Not re-listed** (already in the first audit, confirmed still present): export includes sensitive by
default + CSV formula injection (F-3.2/F-3.3), MCP config file authn (F-3.4), GRDB fork pinned to a
branch (F-3.1), detector pattern gaps (F-3.5), localization sweep gaps (F-6.1).

---

## PART B — New functionality (spec-level, wedge-deepening)

Everything below respects the invariants: veto-before-read, no content in logs/telemetry, AI stays
on-device, CloudKit only behind `SyncEngine`, sensitive clips excluded from every automated surface.
The theme: **features that require holding the user's clipboard *privately* are features Paste
(cloud infra), Raycast (account-centric, macOS-only), Maccy (no AI), CleanShot (not a clipboard),
and Alfred (no sync, no AI) structurally cannot copy.**

### B-F1. "Ask your clipboard" 2.0 — from Q&A to recall engine (Effort: M)
- **User problem:** "I copied a confirmation number / address / snippet sometime this week and I
  can't formulate a keyword search for it."
- **Design:** `ClipboardQA` already grounds answers in history with sensitive filtering. Extend:
  (1) **time/kind/source-scoped retrieval** ("the URL I copied from Slack yesterday") — parse the
  constraint on-device (FoundationModels structured output) into the existing `ClipSearchQuery`
  filters; (2) **cited answers** — every answer chip deep-links `gancho://clip/<id>` to its source
  clips (the wire already exists in `WidgetClips.deepLinkURL`); (3) **answer→action** — "copy it",
  "make it a snippet", "run Pretty-print" as follow-ups on the cited clip; (4) QA over OCR'd
  screenshot text (already in `contentText` — B-2 must be fixed first or sync erases the corpus).
- **Data/API impact:** none new on disk; `ClipboardQA.answer(question:store:filters:)` gains a
  filter parameter; one new App Intent parameter.
- **Privacy:** all retrieval local; keep the existing sensitive veto; answers never logged. This is
  the headline demo: *no competitor can answer questions about your clipboard without uploading it.*

### B-F2. Dev Actions: breadth + composable pipelines (Effort: M–L)
- **User problem:** developers chain transforms (decode → extract field → re-encode) through
  scratch files and `jq`.
- **Design:** add actions: hash (SHA-256/MD5), epoch↔ISO date, JSON↔YAML, JSON→CSV, URL
  encode/decode, case conversion (camel/snake/kebab), regex extract, diff-two-clips, cURL→fetch/
  URLSession, JWT *verify* (paste a public key — pure CryptoKit, offline), UUID v4/v7 generate.
  Then **Pipelines**: a user-named sequence of actions saved as a value (`[ActionID]` +
  per-step params), invoked from the panel, a snippet-style keyword, an App Intent, or MCP.
  `DevActions.run` is already the single pure entry point — a pipeline is `reduce`.
- **Data/API impact:** one small `pipeline` table (or UserDefaults JSON like `SmartCollectionRule`);
  new MCP tool `run_dev_action` (below); each action = one pure function + tests.
- **Privacy:** transforms are pure and offline by construction; nothing to do. Free tier on purpose
  (the word-of-mouth spear, per the existing comment).

### B-F3. Snippet/board sharing that cannot leak (Effort: M)
- **User problem:** teams re-create the same snippet libraries by hand; every competitor's answer
  is "make an account".
- **Design:** "Share board…" exports a **`.ganchoboard`** file: the board's clips with
  `excludeSensitive` **hard-wired true**, a *second* detector re-scan at export time (belt and
  suspenders — catches pre-detector legacy rows), provenance manifest (board name, count, date), and
  an Ed25519 signature using the existing license-key signing infra so recipients can verify origin.
  Import merges as a new board via the existing archive dedupe. Share over AirDrop/Files/anything.
- **Data/API impact:** thin layer over `GanchoArchive` (fix B-23 first so boards travel);
  `GanchoArchive.Options` gains `boardID:` scoping.
- **Privacy:** no server, no link infra, sensitive excluded twice, share is a deliberate user
  export. This is the growth loop that is *on-brand*: content the user curated, never history.

### B-F4. Team boards via CKShare (Effort: L — next-quarter+)
- **User problem:** small teams want a live shared snippet library (API keys excluded!) without an
  enterprise tool.
- **Design:** the board zone was isolated for exactly this (`BoardRecordMapper.zoneName`,
  adapter comment `CKSyncEngineAdapter.swift:21-24`). A shared board = its own custom zone with a
  `CKShare`; clips join it only via an explicit "Add to team board" gesture that *copies* the clip
  record into the shared zone (never a pointer into private history). Hard rules: sensitive clips
  are refused; the share UI shows exactly what fields travel. Participants get read or read/write.
- **Data/API impact:** per-shared-board zone; `SyncEngine` boundary grows
  `share(board:)`/`acceptShare(metadata:)`; membership for shared boards rides a junction record in
  the shared zone (fixes B-3's set-merge need in the process — per-membership records merge trivially).
- **Privacy:** CloudKit sharing is Apple-account E2E infrastructure — Gancho still runs no server.
  **Monetization:** this is the Team tier (see Part C).

### B-F5. Public GanchoMCP extension surface (Effort: M)
- **User problem:** agents are becoming the power-user shell; today's MCP surface is 4 read/pin
  tools with a file-flip authorization (F-3.4).
- **Design:** (1) **capability tokens**: the app mints per-client, scope-bound, revocable tokens
  (listed + revocable in the Privacy Center); `gancho mcp --token` presents one; the bare config
  file can no longer raise scope. (2) New tools: `save_snippet` (agent → Library, mirrors
  `gancho save`), `run_dev_action` / `run_pipeline` (transform without exposing history),
  `ask_clipboard` (**answer-only scope**: the agent gets a grounded *answer* + clip ids, never raw
  bodies — a genuinely novel privacy level for agent integration), `list_boards`. (3) Publish the
  tool JSON schema + a conformance doc so Raycast/VS Code/Claude-Desktop configs are copy-paste.
- **Data/API impact:** token store (Keychain, app-written); `mcp_access_log` gains a `client` column
  (v16 migration); schema doc in `docs/`.
- **Privacy:** every call already logged content-free; tokens make the log attributable. The pitch
  writes itself: *"give your AI agent a clipboard — with a scope dial and an audit log."*

### B-F6. Spotlight + App Intents depth (Effort: M)
- **Design:** donate non-sensitive, non-secret-kind clips/snippets to Core Spotlight
  (`CSSearchableItem`, title+preview only) so ⌘Space finds clips; **opt-in**, because donation
  copies previews into the OS index (that's a privacy disclosure, and deletion must call
  `deleteSearchableItems` — wire it into `delete`/purge, which B-5's ID-collection refactor
  enables). Add intents: Run Dev Action (parameterized), Paste Nth Clip, Add to Board, Export Board;
  Focus filters (work Focus → only work boards visible); interactive widget for the paste stack;
  keyword snippet expansion via the iOS keyboard already exists — surface it in onboarding.
- **Impact:** app-layer only; no schema change beyond the deletion hook.

### B-F7. Transparency & trust as product surface (Effort: S–M each)
- **Privacy Report** (weekly, local): captures vetoed, secrets masked, items purged, MCP calls/
  denials — every number already exists (`purge_log`, `mcp_access_log`, `PrivacyEvents`); this is a
  screen, not an engine. End with "Content uploaded to Gancho servers: **0** (we don't have any)."
- **Data-flow inspector:** per-clip provenance sheet — where captured, what enrichments ran, whether
  it synced (`syncSystemFields != nil` is already the flag `syncedCount` uses), which fields ride
  encrypted vs. plain (from `ClipRecordMapper`'s table). Turns the SECURITY-MODEL doc into UI.
- **Verifiable claims page:** publish `docs/SECURITY-MODEL.md` on gancho.app with a "check it
  yourself" section (`strings` the binary for URLs; the direct build's lack of network entitlement;
  the no-content-logging test suite). Commission the third-party audit the first report suggested —
  after Part A's P0/P1s land, not before.

### B-F8. Session timeline / "clipboard time machine" (Effort: M, differentiating)
- **User problem:** "everything I copied while debugging yesterday" is a *session*, not a query.
- **Design:** on-device time-clustering of capture bursts (gap > 20 min = new session), labeled by
  dominant source app + an on-device one-line summary (FoundationModels, Pro). A session view
  supports copy-all-as-stack and promote-selection-to-board. No new capture data needed —
  `createdAt` + `sourceAppBundleID` suffice; optional window-title capture stays **off** by default
  (content-adjacent; if ever added: encrypted column, never synced, never in exports).
- **Why competitors can't:** requires history + on-device summarization + privacy trust — the wedge.

---

## PART C — World-class roadmap

### Phase 0 — 0.4.0, "the correctness release" (next release, ~3–4 weeks)
Sync is the one bet you cannot fake before charging for it, and Part A shows it currently *loses
user data in normal use*. Ship, in order:
1. **Field-preserving remote upsert** (B-1/B-2) + LWW-gated membership (B-3) + pin sync (B-4).
2. **Tombstones for purge/panic/plain delete + no-sensitive-upload switch** (B-5) — decide the
   simple, marketable rule: *"secrets never leave the device"* (one WHERE clause) and say it loudly.
3. **iOS retention/tier parity + read-time expiry filter** (B-10) — the 10-minute promise must be
   true on every platform that states it.
4. **Tier junction fix + sensitive-archive exclusion + archived-dedupe revival** (B-11/B-12/B-14).
5. **Sensitive-expiry-vs-boards decision** (B-13) + phone/Luhn false positive (B-17).
6. Carry over the first report's shortlist: export-sensitive default + CSV injection guard, MCP
   config hardening (interim: log+notify on scope raise), GRDB revision pin.
7. On-hardware sync verification matrix (the README's own gate) now has a concrete test plan:
   every Part A sync scenario above is a named case.

### Phase 1 — 0.5/0.6, "sharpen the wedge" (next quarter)
- **Ask 2.0** (B-F1) as the headline; **Dev Action breadth + pipelines** (B-F2); **Spotlight/App
  Intents depth** (B-F6). These three make the daily-use loop unmatchable.
- **Archive v2** (B-23) → then **`.ganchoboard` sharing** (B-F3): the privacy-safe growth loop.
- **MCP tokens + published schema + `ask_clipboard` answer-only tool** (B-F5): own the
  "agent-safe clipboard" category before Raycast does.
- **Privacy Report + data-flow inspector** (B-F7); commission the external audit; publish it.
- Launch to developers first (Homebrew CLI + VS Code integration already exist as hooks), Product
  Hunt/HN with the transparency page as the story.

### Phase 2 — post-launch (2–3 quarters)
- **Team boards on CKShare** (B-F4) and the **Team tier** — serverless team infra is the moat Paste
  cannot cross without rebuilding their backend, and Maccy/Alfred will never build.
- **Session timeline** (B-F8) — the retention-and-recall story matures into "memory layer".
- Portable envelope v2 → the documented client contract (first report's F-1.5 sequencing) → a
  public `GanchoKit` for non-Apple clients only when the capability matrix says the demand is real.
- watchOS pins viewer; visionOS only if usage justifies (unchanged from plan).

### Monetization notes
- Keep: generous free tier as the distribution engine; Pro = sync + AI depth (semantic, Ask, OCR,
  unlimited history). Price against Paste (~$30/yr) and CleanShot (~$29 one-time): **one-time direct
  license (~$29) including local Pro features + optional $15–19/yr "Sync & AI" add-on** matches the
  local-first architecture and undercuts subscription fatigue; App Store keeps the pure subscription.
- **Team tier** ($5–8/seat/mo, direct only) once CKShare boards land — priced on collaboration, not
  hostage data (export stays free forever; that asymmetry *is* the brand).
- Fix B-21 (Pro pin limit in Shortcuts) before anyone pays — a paying user hitting a free-tier wall
  in Siri is a refund generator.

### Trust & distribution notes
- Every trust artifact is cheap because the invariants already hold in code: publish the security
  model, the privacy report, the audit, and the "what syncs / what never leaves" table straight from
  `ClipRecordMapper`. Notarized direct download + Homebrew cask + Sparkle (already wired) for the
  developer channel; App Store for reach.
- The one message to repeat until it's boring: **"We can prove what we don't know about you."**

### Top 10 moves to category leadership
1. **Fix the sync-clobber cluster (B-1…B-5) and verify on hardware** — correctness before growth;
   a clipboard manager that loses snippets is dead on arrival.
2. **Make "secrets never leave the device" literally true** (no-sensitive-upload + tombstoned
   purges + iOS expiry parity) and turn it into the marquee marketing line.
3. **Ship Ask-your-clipboard 2.0 with cited, actionable answers** — the demo nobody else can run
   without a cloud round-trip.
4. **Own the agent era: tokenized MCP + published schema + answer-only scope** — become the default
   "clipboard for AI agents" while competitors are still shipping menubar features.
5. **Dev Action pipelines exposed everywhere** (panel, keyword, Shortcuts, MCP, CLI) — the
   developer wedge that compounds daily.
6. **`.ganchoboard` signed sharing** — viral growth with zero servers and zero privacy compromise.
7. **Privacy Report + data-flow inspector + third-party audit, published** — convert invariants
   into visible, screenshot-able trust.
8. **Archive v2 completeness (boards travel; nothing silently dropped)** — make "no data hostage"
   audit-proof; it's also the foundation for sharing and future clients.
9. **CKShare team boards + Team tier** — serverless collaboration as the structural moat and the
   revenue expansion.
10. **One-time license + sync add-on pricing against Paste's subscription** — position as the
    fair-deal, private alternative in every comparison table.
