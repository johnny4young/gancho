# Gancho — Audit 09: Executable Architecture Refactor Plan

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24`
**Converts:** `.audit/03-architecture-performance-refactor.md` (A3-x.y findings) into a
PR-by-PR sequence a macOS developer can execute. Each PR is independently shippable —
nothing here blocks a release, and every PR leaves `make lint && make test` green.
**Sizes:** S ≤½ day · M 1–3 days · L >3 days.
**Nature:** *mechanical* = behavior-preserving move/rename/retype, reviewable by diff
shape; *structural* = new seams, needs design review + new tests.

---

## 0. What already landed on this branch (PR-A)

`Packages/GanchoKit/Sources/GanchoKit/ClientContract.swift` adds nine protocol facets
plus two compositions, and retroactively conforms `GRDBClipboardStore` to all of them
(empty extensions — every requirement copies an existing method signature exactly, with
protocol-illegal default argument values dropped; the concrete methods keep their
defaults and still satisfy the requirements — the pattern `MCPClipStore` already proves
in-tree).

| Facet | Methods | Surface |
| --- | --- | --- |
| `ClipReading` | 6 | `items(offset:limit:)`, `recentForBrowse(offset:limit:)`, `item(id:)`, `content(for:)`, `count()`, `thumbnailData(for:)` |
| `ClipSearching` | 3 | `search(_:limit:)`, `semanticSearch(queryVector:topK:snippetsOnly:)`, `items(matching:limit:)` |
| `ClipMutating` | 5 | `insert(_:content:)`, `delete(id:)`, `deleteForSync(id:now:)`, `deleteAllSensitive()`, `setPinned(id:_:)` |
| `ClipEnriching` | 4 | `updateTitle`, `attachExtractedText`, `updateClipText`, `saveEmbedding` |
| `BoardStoring` | 12 | full board CRUD + membership + `deletePinboardForSync` + `setBoardMembership` |
| `SnippetStoring` | 9 | promote/demote, `snippets()`, `snippetCount()`, `saveSnippet`, `updateSnippet`, `setKeyword`, `incrementUses`, `snippet(matchingKeyword:)` |
| `StoreStatsProviding` | 5 | `pinnedCount`, `sensitiveCount`, `archivedCount`, `syncedCount`, `purgedItemCount(since:)` |
| `ExportProviding` | 4 | `exportJSON()` ×2, `exportCSV()` ×2 (explicitly documented as NOT frozen — see PR-K) |
| `StoreMaintaining` | 3 | `importBatch(_:)`, `backfillLegacyPreviews()`, `vacuum()` |

Compositions: `GanchoClientStore = ClipReading & ClipSearching & BoardStoring &
ExportProviding` (the third-party contract to freeze) and `FullClipStore` (everything
the first-party apps hold). Deliberate omissions, documented in the file header:
`thumbnailURL(for:)` (plaintext-only semantics — implementation detail),
`recordMCPAccess`/`recentMCPAccesses` (MCP surface is in flight),
`setSortIndex(clipID:_:)` (SDK-27 replacement pending), and all `writer`/blob internals.

`Tests/GanchoKitTests/ClientContractTests.swift` pins the conformances: existential
bindings for every facet (compile-time assertion) plus a dispatch round-trip
(insert via `ClipMutating`, observe via `ClipReading`/`StoreStatsProviding`).

Everything below builds on this.

---

## 1. PR sequence at a glance (dependency order)

```
Track P (perf, all independent, land anytime):
  PR-B  v16 indexes + EXPLAIN tests            S   mechanical
  PR-C  pendingUploadCount()/IDs()             S   mechanical
  PR-P3 thumbnail cache caps (interim)         S   mechanical
  PR-P4 vDSP semanticSearch                    S   mechanical
  PR-P5 retention pre-check + sweep skip       S   mechanical

Track R (sync reliability, independent):
  PR-R1 stop advancing state on failed applies M   structural
  PR-R2 batch-scoped record building           M   structural

Track A (architecture, the core of this plan):
  PR-A  facets + conformances (DONE, this branch)        S
  PR-D  migrate the concrete-store casts onto facets     M   mechanical   ← PR-A
  PR-E  GanchoAppCore target + controllers               M/L structural   ← PR-A (PR-D helps)
  PR-F  iOS god-file split (files only)                  M   mechanical   (coordinate: file in flight)
  PR-G  IOSAppModel → view models over GanchoAppCore     L   structural   ← PR-E, PR-F
  PR-H  Mac AppModel → coordinators over GanchoAppCore   L   structural   ← PR-E
  PR-I  PanelView split + PanelSearchModel               M/L structural   (independent)
  PR-J  ImageDownsampler + ThumbnailCache unification    M   mechanical   (independent; pairs with PR-P3)
  PR-K  streaming export (ClipExporter) + facet reshape  M   structural   ← PR-A (before PR-L)
  PR-L  contract freeze: @_spi/internal + doc gate       M   mechanical   ← PR-D, PR-K (last)
```

**Leverage ranking** (impact ÷ effort): PR-B > PR-E > PR-D > PR-C > PR-K > PR-J >
PR-G/PR-H > PR-I > PR-L. PR-B is the biggest perf win per line in the repo (audit
A3-1.1/1.2). PR-E is the highest-leverage *structural* change: it de-duplicates whole
subsystems that currently must be bug-fixed twice (A3-2.4) and makes them
`swift test`-able for the first time.

**In-flight coordination:** `MCPAccess.swift`, `GanchoMCP/*`, `gancho/GanchoCLI.swift`,
`GanchoAI/DevActions*`, `Apps/GanchoiOS/GanchoiOSApp.swift`, `Apps/GanchoMac/AppModel.swift`
are owned by other work streams as of this writing. PR-D/F/G/H touch some of them —
sequence those PRs after the in-flight branches merge, and treat the line numbers below
as anchors to re-verify, not gospel.

---

## 2. PR-D — Migrate every concrete-store dependency onto the facets (M, mechanical)

**Goal:** kill the `store as? GRDBClipboardStore` pattern (22 sites in
`GanchoiOSApp.swift`) and the concrete-typed handles (`AppModel.grdbStore`,
`KeyboardModel.store`, `ClipboardQA`'s parameters). Zero behavior change; the diff is
retypes plus making protocol-dropped default arguments explicit at ~6 call sites.

### 2.1 iOS: one typed handle instead of 22 casts

`IOSAppModel` keeps `store: any ClipboardStore` (the in-memory fallback still needs it)
and gains **one** stored capability handle, downcast once at init:

```swift
// Before (×22):
guard let grdb = store as? GRDBClipboardStore else { return }

// After (once, in init):
/// Full-featured store surface; nil when running on the in-memory fallback,
/// in which case boards/search/snippets degrade to no-ops VISIBLY (isDurable
/// already drives the warning banner).
private let full: (any FullClipStore)?
...
self.full = store as? any FullClipStore

// At each former cast site:
guard let full else { return }
```

Cast → facet map (line anchors from today's `GanchoiOSApp.swift`; every method used at
the site is already a requirement of the named facet):

| Site | Uses | Facet(s) exercised via `full` |
| --- | --- | --- |
| `:47` post-launch task | `backfillLegacyPreviews()` | `StoreMaintaining` |
| `:294` `configureSync` | passes store to `SyncEngineFactory.make(store:)` | **not a facet** — the factory already takes `any SyncLocalStore`; change the guard to `store as? any SyncLocalStore` |
| `:407` `handleDeepLink` | `item(id:)` | `ClipReading` |
| `:421` `refreshBoards` | `pinboards()` | `BoardStoring` |
| `:434`, `:440` `clipCount` | `count()`, `count(inBoard:)` | `ClipReading`, `BoardStoring` |
| `:447` `saveAsSnippet` | `snippetCount()`, `promoteToSnippet` | `SnippetStoring` |
| `:463`, `:485` `createBoard` | `pinboards()`, `createPinboard`, `assign` | `BoardStoring` |
| `:501` `boardMembership` | `boardIDs(forClip:)` | `BoardStoring` |
| `:511` `suggestedBoard` | `pinboards()`, `boardIDs`, `content(for:)`, `semanticSearch` | `BoardStoring`+`ClipReading`+`ClipSearching` (moves wholesale to `BoardSuggestionService` in PR-E) |
| `:541` `setBoardMembership` | `assign`/`unassign` | `BoardStoring` |
| `:554` `renameBoard` | `renameBoard` | `BoardStoring` |
| `:567` `deleteBoard` | `deletePinboardForSync`/`deletePinboard` | `BoardStoring` |
| `:592` `search` | `items(inBoard:)`, `search(_:limit:)` | `BoardStoring`+`ClipSearching` |
| `:614` `loadRecentPage` | `recentForBrowse(offset:limit:)` | `ClipReading` |
| `:707` `askClipboard` | `ClipboardQA().answer(store:)` | retyped in §2.3 |
| `:725` `togglePin` | `setPinned` | `ClipMutating` |
| `:731` `delete` | `deleteForSync(id:now:)` — now pass `now: .now` explicitly (default lost through existential) | `ClipMutating` |
| `:783`, `:801` backup/restore | `GanchoArchive.export/restore` | **stays concrete** — `GanchoArchive` is an in-module engine using `store.writer`/`blobsForMaintenance` (like `RetentionEngine`, `TierEnforcement`); the composition root may keep ONE concrete handle for constructing engines. Keep a `private let grdbForEngines: GRDBClipboardStore?` beside `full`, used ONLY to hand to engines. |
| `:914` `enrich` | `attachExtractedText`, `updateTitle`, `saveEmbedding` | `ClipEnriching` (moves to `EnrichmentService` in PR-E) |
| `:2625` Privacy Center | `syncedCount()`, `purgedItemCount(since:)`, `search` | `StoreStatsProviding`+`ClipSearching` |

**Rule of thumb the diff enforces:** feature code holds facets; only the composition
root (init) and engine construction see `GRDBClipboardStore`.

### 2.2 macOS: retype the parallel handle

`AppModel.grdbStore` (`AppModel.swift:48`) and `LibraryView`'s copy become
`(any FullClipStore)?` — every one of the ~31 `grdbStore.` call sites
(`attachExtractedText :364`, `updateTitle :370`, `saveEmbedding :385`,
`incrementUses :574`, `snippet(matchingKeyword:) :581`, `semanticSearch :637,1073`,
`search :640`, `deleteForSync :753`, pin/board CRUD `:982–:1154`, Library’s
`pinboards/snippets/pinnedCount/count/items/updateSnippet/setKeyword/demoteFromSnippet`)
is already a facet requirement. **Two exceptions:** `recentMCPAccesses` (`:929`) is not
in a facet (MCP surface in flight) — keep a narrow `mcpLog: GRDBClipboardStore?` or
inline cast at that one site until the MCP work settles; engine construction
(`RetentionEngine`, `TierEnforcement`, `GanchoArchive`, `SyncEngineFactory`) keeps the
concrete/`SyncLocalStore` handle at the composition root.

Default-argument fallout to make explicit: `semanticSearch(..., snippetsOnly: false)`,
`search(..., limit: 50)` where the defaults were relied on, `promoteToSnippet(id:,
title: nil)`, `createPinboard(name:, sfSymbol: "square.stack")`,
`deleteForSync(id:, now: .now)`, `deletePinboardForSync(id:, now: .now)`,
`saveSnippet(..., language: nil)`. Grep-able, finite, compiler-enforced.

### 2.3 Package-side retypes (same PR)

- `ClipboardQA.retrieve/answer(question:store:useSemantic:)`
  (`GanchoAI/ClipboardQA.swift:29,56`): `store: GRDBClipboardStore` →
  `store: any ClipReading & ClipSearching` (it calls exactly `semanticSearch`,
  `search`, `content(for:)`). Cross-module, source-compatible for callers passing the
  concrete store. *(Coordinate: GanchoAI has in-flight edits.)*
- `KeyboardModel.store` (`Apps/GanchoKeyboard/KeyboardModel.swift:45`):
  `GRDBClipboardStore?` → `(any ClipReading & ClipSearching)?` (it uses
  `recentForBrowse`, `thumbnailData`, `search`).

**Test impact:** none required (behavior-preserving), but add one regression test to
`ClientContractTests`: `#expect((store as any ClipboardStore) is any FullClipStore)` —
guards the init-time downcast pattern the apps now rely on.
**Size M** — wide but shallow; the compiler does the review.

---

## 3. PR-E — `GanchoAppCore`: one home for the duplicated app-model logic (M/L, structural)

**Problem (A3-2.4):** `AppModel` (macOS) and `IOSAppModel` duplicate `suggestedBoard`
byte-for-byte (`AppModel.swift:1055-1080` ≡ `GanchoiOSApp.swift:502-529`),
`configureSync` (differs only in state-file path), `enrich`, board CRUD +
`resetSyncAndRepull`, `askClipboard` (already drifted), and the telemetry bootstrap.
Every sync/boards bug is fixed twice; none of it is unit-testable.

### 3.1 Wiring

`Packages/GanchoKit/Package.swift` — new target + product:

```swift
.library(name: "GanchoAppCore", targets: ["GanchoAppCore"]),
...
// Platform-neutral app-layer coordinators shared by the Mac and iOS shells.
// May be @MainActor; must NOT import AppKit/UIKit/SwiftUI/CloudKit.
.target(name: "GanchoAppCore", dependencies: ["GanchoKit", "GanchoAI", "GanchoSync"]),
.testTarget(name: "GanchoAppCoreTests", dependencies: ["GanchoAppCore"]),
```

`project.yml` — add `GanchoAppCore` to the `products:` list of the `Gancho` and
`GanchoiOS` targets' GanchoKit package dependency (both app targets already depend on
the package; this is a one-line-each products addition), then `make project`.
Per AGENTS.md, no new top-level package is created (it's a target inside
`Packages/GanchoKit`), so the Makefile `PACKAGE` wiring is untouched. Update the
`Package.swift` header comment ("Four library products" is already stale — F-1.2).

### 3.2 Types (all `@MainActor @Observable` unless noted, all facet-typed)

| Type | Absorbs (today) | Constructor dependencies |
| --- | --- | --- |
| `SyncController` | `configureSync`, `resetSyncAndRepull`, status plumbing (`AppModel.swift:799-899`, `GanchoiOSApp.swift:286-325`) | `store: any SyncLocalStore`, `stateStore: SyncStateStore` (parameterizes the ONLY real platform difference: the state-file URL), `entitled: @Sendable () -> Bool`, `onRefresh: @MainActor () -> Void` |
| `BoardsController` | create/rename/delete board, membership, free-tier gate (`AppModel.swift:967-1151`, `GanchoiOSApp.swift:413-572`) | `store: any BoardStoring & StoreStatsProviding`, `tier: () -> UserTier`, `syncEnabled: () -> Bool` (chooses `deletePinboardForSync` vs `deletePinboard`) |
| `EnrichmentService` (actor, nonisolated target rules apply) | per-call `ContextualSentenceEmbedder()`/`TieredClipAnnotator()`/`ImageTextExtractor()` construction (A3-1.12) + the `enrich` body (`AppModel.swift:338-382`, `GanchoiOSApp.swift:896-931`) | `store: any ClipEnriching`; owns process-lifetime embedder/annotator/extractor instances |
| `BoardSuggestionService` | the byte-identical `suggestedBoard(for:)` | `store: any BoardStoring & ClipReading & ClipSearching`, `EnrichmentService` (for the query vector) |
| `AskClipboard` facade | the two drifted `askClipboard`s — standardize on the iOS shape (shared `ClipboardQA`), macOS drops its hand-rolled retrieval | `store: any ClipReading & ClipSearching` |

Both app models shrink to platform glue: pasteboard/scene wiring, window controllers,
purchases UI. **This is where the deleted duplication pays rent forever.**

**Test impact:** new `GanchoAppCoreTests` — sync enable/disable matrix (tier ×
iCloud × entitlement), board CRUD free-tier gates, suggestion ranking, enrichment
plan execution against an in-memory GRDB store. This logic has *zero* tests today
because it lives in app targets `swift test` can't reach (A3-3.3).
**Size M/L; structural.** Land it incrementally if needed: `SyncController` +
`BoardsController` first (biggest duplication), services second.

---

## 4. PR-F/PR-G — iOS god-file decomposition (2,673 lines → files, then view models)

### PR-F: file split only (M, mechanical — no declaration changes)

Move top-level types out of `Apps/GanchoiOS/GanchoiOSApp.swift` verbatim (all targets
list `path: Apps/GanchoiOS` in project.yml, so new files are picked up with no
project.yml change):

| New file | Moves |
| --- | --- |
| `GanchoiOSApp.swift` (remains) | `@main` App + scene + deep-link routing (~70 lines) |
| `IOSAppModel.swift` | the 744-line model (`:206-949`) unchanged |
| `IOSOnboardingView.swift` | onboarding flow |
| `CaptureView.swift` | capture UI + `PasteControlView` (`UIViewRepresentable`) |
| `ClipDetailView.swift` | detail + `FullScreenImageView` |
| `BoardsHomeView.swift` | boards home + `MoveToBoardSheet` + `BoardDot` |
| `ProInfoView.swift` | paywall |
| `IOSSettingsView.swift` | settings + `GanchoArchiveDocument` (`FileDocument`) |
| `IOSPrivacyCenterView.swift` | privacy center (the `:2623` refresh moves here) |

Rule: `git diff --color-moved` should show only moves. Accessibility identifiers,
strings, and behavior untouched. **Coordinate with the in-flight edit to this file —
land immediately after it merges, before drift re-accumulates.**

### PR-G: model split (L, structural — after PR-E and PR-F)

`IOSAppModel` (by then in its own file) decomposes into `@MainActor @Observable` units,
each constructor-injected with facets so `swift test` reaches them:

| New type | Absorbs (anchors in today's file) | Store dependency |
| --- | --- | --- |
| `HistoryListViewModel` | captures/sections/pagination/kind filter (`:210-233`, `:574-634`) | `any ClipReading & ClipSearching` |
| `CaptureIngestor` | ingest/makeItem/enrich handoff (`:806-948`) | `any ClipMutating` + `EnrichmentService` |
| `BoardsViewModel` | board UI state (`:413-572`) | `BoardsController` (PR-E) |
| `EntitlementModel` | tier/purchases/proGate (`:245-363`) | none (StoreKit) |
| `BackupModel` | archive make/restore (`:771-805`) | concrete store (engine rule, §2.1) |

`IOSAppModel` remains as a thin façade owning these, so views migrate incrementally.
**Test impact:** unit tests for pagination guards (the same-length page-shift bug,
A3-1.14), kind filtering, free-tier gates, ingest dedupe — all new coverage.

---

## 5. PR-H — Mac `AppModel` coordinators (L, structural, after PR-E)

`Apps/GanchoMac/AppModel.swift` (1,245 lines, nine responsibilities) becomes a
composition root (~200 lines) plus extracted `@MainActor` coordinators (new files in
`Apps/GanchoMac/`; App Intents keep resolving `AppModel` via `AppDependencyManager`
(`:217`) — it forwards):

| New file/type | Absorbs (anchors) | Notes |
| --- | --- | --- |
| `CaptureIngestPipeline.swift` | capture pipeline (`:302-467`) | uses `EnrichmentService` (PR-E) |
| `PasteCoordinator.swift` | paste actions, smart paste + QA (`:469-668`), paste stack (`:684-704`) | QA via the PR-E facade |
| `DeletionCoordinator.swift` | undo-window deletion state machine (`:713-758`) | **first target for a unit test** — pure timing/state logic that can't be tested today |
| `SyncCoordinator.swift` | thin shim over PR-E `SyncController` (`:799-899`) | |
| `EntitlementCoordinator.swift` | purchases/licensing (`:785-797`, `:926-965`) | |
| `BoardsCoordinator.swift` | shim over PR-E `BoardsController` (`:967-1151`) | |
| `WindowRegistry.swift` | the nine window controllers (`:59-69`) | |

Sequencing inside the PR: extract `DeletionCoordinator` first (self-contained, gets a
test), then Sync/Boards (mostly deleted in favor of PR-E types), then capture/paste.
Also fold in A3-3.2b here: the coordinators get the `withDiagnostics(_:) async -> Bool`
helper so success toasts gate on actual write success (`:982-983` bug class).

---

## 6. PR-I — `PanelView` decomposition (M/L, structural, independent)

`Apps/GanchoMac/PanelView.swift` (1,812 lines, ~20 `@State` vars of real view-model
state):

| New file | Contents |
| --- | --- |
| `PanelSearchModel.swift` | `@MainActor @Observable`: query → refresh → results/groups/paging/selection/snippet-match. The logic at `:1186-1244` and `:640-661` moves nearly verbatim off the `View`. Typed `any ClipReading & ClipSearching`. |
| `PanelKeyboardNavigation.swift` | the keyboard state machine (`:1071-…`) as a value-type reducer over `(key, currentSelection, rows)` — pure and testable |
| `PanelRails.swift`, `ClipPeek.swift`, `SnippetFillSheet.swift`, `PanelShortcutsOverlay.swift` | mechanical view moves (`:1294-1726`, `:1738-…`) |

**Test impact:** `PanelSearchModel` gets tests for debounce/refresh ordering, page
dedupe on shift (pairs with keyset pagination later), selection stability. After PR-G,
compare `PanelSearchModel` and `HistoryListViewModel` — if they converge, hoist the
shared skeleton into `GanchoAppCore` as a follow-up S PR (do NOT pre-abstract).

---

## 7. PR-J — Thumbnail unification (M, mechanical-ish, independent)

Four copies of the same ImageIO incantation with three cache policies (A3-2.7/A3-1.15):
`Apps/GanchoMac/ClipThumbnailStore.swift:49-59`, `Apps/GanchoiOS/ClipThumbnailStore.swift:45-60`,
`Apps/GanchoKeyboard/KeyboardModel.swift:173-188`, `BlobStore.makeThumbnailData`
(`BlobStore.swift:228-249`).

1. **`ImageDownsampler` in GanchoKit** (new file, pure `Data → Data?`, ImageIO +
   CoreGraphics only — both are platform-free): the single
   `CGImageSourceCreateThumbnailAtIndex` implementation, `maxPixel` parameterized.
   `BlobStore.makeThumbnailData` delegates to it.
2. **`ThumbnailCache` in GanchoDesign** (not GanchoAppCore, so the keyboard extension —
   which links GanchoDesign but should stay lean — can use it): generic `@MainActor`
   id-keyed cache with FIFO cap (default 64; keyboard passes 24), the pattern
   `KeyboardModel.swift:37,163-167` already proves. Platform `Image` bridging stays in
   the two app files, which shrink to ~20 lines each.
3. **Behavioral fix riding along:** macOS `ClipThumbnailStore` currently decodes the
   FULL blob per thumbnail (`AppModel.swift:172-177` wires `content(for:)`); switch it
   to `store.thumbnailData(for:)` (`ClipReading`) like iOS/keyboard — cheaper and
   correct for encrypted stores.

**Test impact:** `ImageDownsampler` unit test (decode 1×1 PNG fixture, assert ≤ maxPixel);
`ThumbnailCache` eviction test. If PR-P3 (interim FIFO caps) landed first, this PR
deletes it; if not, this PR subsumes it.

---

## 8. PR-K — Streaming export via `ClipExporter` (M, structural; prerequisite for PR-L)

A3-1.13: `exportJSON`/`exportCSV` materialize the full table (content included) twice in
memory. The `Data`-returning shape must not be frozen into the client contract.

- New `ClipExporter` type in GanchoKit owning CSV/JSON formatting (moves the
  formula-injection escape with it out of `GRDBClipboardStore`), writing incrementally
  over a `ClipRow.fetchCursor` to a `FileHandle`; API returns a file `URL`.
- `ExportProviding` gains URL-based requirements (e.g.
  `exportJSON(excludeSensitive:to:) async throws -> URL`); the `Data`-returning
  methods stay for compatibility but are documented as the legacy shape and excluded
  from the frozen `GanchoClientStore` composition (swap `ExportProviding` for a new
  `ArchiveExporting` facet in the typealias — a typealias change is source-compatible
  for existentials at the app layer, verify the few binding sites).
- Sensitive-by-default and CSV-injection hardening (F-3.2/F-3.3) land here if not
  already closed.

**Test impact:** extend `GRDBClipboardStoreTests` export tests to the URL API; add a
large-fixture memory assertion to `PerformanceHarnessTests` (peak RSS bounded while
exporting the 100k synthetic set).

---

## 9. PR-L — Contract freeze + module tightening (M, mechanical, LAST)

Once PR-D has moved all callers onto facets and PR-K has fixed the export shape:

1. **Narrow the class surface.** Audit every `public` member of `GRDBClipboardStore`
   and its nine extension files: anything now reachable through a facet stays public
   (it *is* the facet's witness); anything GRDB-shaped goes `internal` or
   `@_spi(GanchoInternal) public` — candidates: `migrate()` (needed by tests →
   `@_spi`), `thumbnailURL(for:)` (plaintext-only; keyboard/tests may still need it →
   `@_spi`), `importBatch` stays (facet), `writer`/`blobsForMaintenance` are already
   internal. The CLI and perf harness adopt `@_spi(GanchoInternal) import GanchoKit`
   where they touch these. *(Do not start this before the in-flight MCP/CLI branches
   merge — they touch the same files.)*
2. **Freeze the contract** (extends F-1.5/A3-2.6): `ClipItem`, `ClipContent`,
   `ClipSearchQuery`, `Pinboard`, `SmartCollectionRule`, the nine facets +
   `GanchoClientStore`, `GanchoArchive`, `SyncEngine`, `MCPClipStore`. Record it in
   `docs/ARCHITECTURE.md` and gate with a CI doc-coverage check on exactly that
   surface (DocC warnings-as-errors on the facet files), per A3-3.4.
3. **In-memory fallback parity (optional follow-up, S each):** conform
   `InMemoryClipboardStore` to facets incrementally (`ClipReading` first — it already
   has most of it), so previews/fallback degrade per-facet instead of wholesale.

---

## 10. Perf/reliability track details (already specified in audit 03 — PR shells only)

| PR | Content | Anchor |
| --- | --- | --- |
| PR-B (S) | Migration `v16-indexes`: partial/expression indexes for `items` (`isPinned DESC, IFNULL(lastUsedAt, createdAt) DESC WHERE isArchived = 0`), `recentForBrowse`, flag counters, retention (`expiresAt`), sync-pending; `EXPLAIN QUERY PLAN` assertions in `PerformanceHarnessTests`. | A3-1.1/1.2/1.3/1.4a/1.8 |
| PR-C (S) | `pendingUploadCount()`/`pendingUploadIDs()` on `SyncLocalStore` (+ GRDB impl); adapter's `emitCurrentStatus`/`reenqueuePendingWork`/`reconcilePendingChanges` stop hydrating content. Protocol change is additive (new requirements with default-throwing extension or implement in the one conformer). | A3-1.7 |
| PR-P3 (S) | FIFO-64 caps on both app thumbnail caches (interim until PR-J). | A3-1.15 |
| PR-P4 (S) | Normalize-on-write + vDSP dot product in `semanticSearch`; one-time re-normalize pass. | A3-1.11a |
| PR-P5 (S) | Skip orphan-blob sweep when `totalRowsPurged == 0`; retention `EXISTS` pre-check. | A3-1.4b/1.5 |
| PR-R1 (M) | Collect per-record failures in `handleFetchedRecordZoneChanges`; on failure emit `.failed`, log content-free diagnostics, and do NOT persist that event's state serialization (so the batch re-fetches). | A3-1.10 |
| PR-R2 (M) | Build CKRecords only for the batch's pending changes; batch the `systemFields`/`boardIDs` per-row lookups. | A3-1.9 |
| Later | Keyset pagination (A3-1.14, after PR-B + PR-I so the model owns paging), async store open (A3-1.16, pairs with `.audit/05`'s readiness work), warm `EmbeddingIndex` (A3-1.11b, inside PR-E's `EnrichmentService`). | |

---

## 11. Risk notes

- **Facet + default-argument interplay:** methods reached through an existential lose
  their concrete default arguments (protocols can't carry them). PR-D must make ~7
  defaults explicit; the compiler finds every site. Do NOT add protocol-extension
  convenience overloads that shadow concrete defaulted methods — overload resolution
  between a concrete defaulted method and a protocol-extension exact-arity method is
  subtle and adds no value here.
- **`GanchoAppCore` isolation:** app targets build with
  `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`; SwiftPM targets do not. Annotate the
  controllers `@MainActor` explicitly (do not rely on a default), keep the services
  that do IO as actors, and keep AppKit/UIKit imports out — that's what keeps them
  `swift test`-able on any Mac.
- **Two owners, one file:** PR-D/F/G/H touch files with in-flight edits. The facet
  layer (PR-A) was designed so those branches merge cleanly — it adds only new files.
  Rebase the cast-migration on top of whatever lands, using §2's table as the
  checklist rather than a patch.
