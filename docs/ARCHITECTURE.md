# Gancho — Architecture

This document records the engineering decisions the code must respect. Product
planning, pricing, and acceptance criteria live in the maintainer's git-ignored
local planning docs.

## Engineering goal

Gancho is a private, local-first system for capture → recall → reuse:

1. capture clipboard material safely,
2. persist and search it locally at interactive speed,
3. sync it across trusted devices without Gancho-operated servers by default,
4. promote valuable items into a curated snippet library, and
5. keep enough platform boundaries that Android, Windows, and Linux clients can
   be added later without replacing the Apple implementation.

The core product bet is not “AI clipboard.” It is trustworthy reuse: the user
can find, understand, transform, and paste the thing they already copied faster
than recreating it.

## The two worlds

| | History | Library |
| --- | --- | --- |
| Lifetime | Ephemeral, governed by retention and expiry rules | Permanent until the user deletes it |
| Entry | Automatic capture on macOS; intentional capture elsewhere | Promoted from a clip or authored directly |
| Contents | Recently copied material | Snippets, templates, pins, reusable references |
| Default privacy posture | Can expire, mask, or be skipped | User-curated, syncable, exportable |

The bridge is the signature gesture: promote a useful clip into the Library in
one action.

## Layering

```text
Apps and extensions (@MainActor by default)
  ├─ macOS menu-bar / panel / paste-back UI
  ├─ iOS + iPadOS app, Share Extension, keyboard, widgets, App Intents
  └─ future visionOS/watchOS/non-Apple shells

Platform adapters
  ├─ ClipboardCore: macOS polling, iOS intentional capture contracts
  ├─ paste-back and permission/onboarding adapters
  └─ extension-safe entry points

Shared engine-room targets (nonisolated + Sendable)
  ├─ GanchoKit: ClipItem, GRDB store, retention, snippets, sync boundary, diagnostics log
  ├─ GanchoAI: deterministic classifiers, annotation, embeddings, QA, model seams
  ├─ GanchoDesign: tokens and shared component primitives
  ├─ GanchoSync: the CKSyncEngine adapter (only module importing CloudKit)
  ├─ GanchoTelemetry: metadata-only analytics transport (network-isolated)
  └─ GanchoMCP: local MCP tools over the store boundary (driven by the `gancho` CLI)

App-layer models and coordinators (actor-isolated when mutable; NO AppKit/UIKit/SwiftUI/CloudKit)
  └─ GanchoAppCore: the testable app logic both shells share and forward to —
       PanelSearchModel + PanelNavigation + PanelCapturePresentation (macOS
       panel), HistoryListViewModel (iOS list), SyncController,
       ClipIngestionCoordinator, CaptureLifecycleController (macOS),
       ReuseController, ClipCurationController, ClipEditingController,
       ClipPreviewLoader, BoardsController, EnrichmentService,
       DeletionCoordinator, BoardSuggestionService, ClipItemFactory. Store
       access is facet-typed, so each unit runs against an in-memory fake in
       GanchoAppCoreTests.

Persistence and sync implementations
  ├─ GRDB / SQLite / FTS5 local store with content-addressed disk blobs
  ├─ iCloud-side content encryption via CKRecord `encryptedValues`
  ├─ CKSyncEngine over the user's private iCloud database
  └─ future LAN / self-hosted / non-Apple transports behind SyncEngine
```

App targets stay thin. If feature logic cannot be tested from a SwiftPM target,
it probably lives in the wrong layer.

`GanchoAppCore` depends only on the transport-neutral `SyncEngine`,
`SyncStateStore`, and `SyncEnablement` contracts in `GanchoKit`. The macOS and
iOS composition roots inject `GanchoSync.SyncEngineFactory`; the app layer
cannot construct or import the CloudKit implementation.

`ClipIngestionCoordinator` is the shared capture workflow: it maps payloads,
persists and deduplicates them, enqueues the durable row, computes and runs the
enrichment plan, and enqueues enriched metadata. Platform shells own only
capture mechanics and presentation effects such as telemetry buckets, list or
widget refresh, feedback, and Live Activity state.

On macOS, `CaptureLifecycleController` owns the monitor lifecycle rather than
pasteboard content: start/stop/ignore commands, observable status mirroring,
capture-preference persistence, and the periodic screen-share auto-pause check.
`AppModel` remains the observable facade and retains platform composition such
as monitor construction, denylist callbacks, windows, and presentation effects.
`PanelCapturePresentation` converts that content-free runtime state into a
deterministic notice, action, and footer indicator. SwiftUI rendering and AppKit
actions stay in the macOS shell, while notice precedence remains pure and
covered by `GanchoAppCoreTests`.

`ReuseController` owns the reusable session state that follows successful user
actions: the recent metadata page, local use/search signals, exact-threshold
snippet candidates, cyclic selection, paste-stack ordering, and the
reversible-delete window. The candidate is resolved atomically with the third
successful use and excludes sensitive, archived, and existing-snippet rows;
exact equality makes dismissal one-shot without another persistence flag. The
platform shells keep presentation and give a confident board suggestion
priority so curation prompts never compete. The macOS `AppModel` also keeps
AppKit paste-back, toasts, telemetry, helper publishing, and the concrete
sync-aware deletion mutation, while exposing facade properties so views do not
couple themselves to controller composition.

`ClipCurationController` gives macOS and iOS one policy and mutation sequence
for pinning and promoting snippets. It returns content-free outcomes after the
free-tier gate and durable write, and enqueues successful pin changes. Each
shell maps those outcomes to its own paywall, diagnostics, confirmation, and
list refresh; failed writes never produce success feedback.

`ClipEditingController` applies the same durable-write-before-sync boundary to
user-owned clip metadata. Title edits are shared across macOS and iOS, compare
against the authoritative stored row, and enqueue sync only after a real local
change. AI enrichment uses an atomic title-if-empty write, so an asynchronous
suggested title can never replace a title the user saved while enrichment was
running. Explicit text-body edits preserve the user's exact whitespace, reject
blank/sensitive/binary/file/structured-color payloads, recompute the preview and
FTS projection in one transaction, and delete the now-stale semantic vector.
Receiving a changed text body from sync performs the same vector invalidation;
metadata-only remote updates keep the existing vector.

`ClipPreviewLoader` is the privacy boundary for explicit full-content previews.
It runs only after the user invokes the macOS Command-Y sheet, returns the
sanitized metadata preview for sensitive or intrinsically masked kinds without
reading durable content, and otherwise preserves text, binary, and file-reference
representations in memory. The macOS sheet decodes images and rich text lazily,
uses a read-only `NSTextView` for large selectable documents, and never writes a
temporary Quick Look file.

`BoardsController` applies the same boundary to board creation, metadata,
deletion, and clip membership. Board limits fail closed if the authoritative
list cannot be read, protected system boards are rejected before persistence,
and sync work is enqueued only after its local mutation or tombstone commits.
The shells receive content-free outcomes and retain selection, refresh,
diagnostic, paywall, and toast behavior.

## Platform contracts

| Platform family | What is allowed | What is forbidden |
| --- | --- | --- |
| macOS | Automatic monitoring via cheap metadata polling, then off-main content reads | Reading content before the sensitive-type veto; blocking the main actor on pasteboard permission prompts |
| iOS / iPadOS | Share Extension, `UIPasteControl`, foreground capture, App Intents, keyboard extension with explicit user action | Background pasteboard polling or marketing that implies silent iPhone capture |
| visionOS | iPad-compatible app first; Universal Clipboard and sync viewer workflows | Native spatial UI before usage data justifies the extra surface |
| watchOS | Viewer, pins, complications/widgets, handoff to iPhone | Capture or pasteboard writes that watchOS APIs do not support |
| Android / Windows / Linux | Analysis only for now: capability matrix, data envelope, and stack options | Implementation commitments, capture adapters, or backend work before an explicit post-PMF decision |

## Frozen client contract

The store is not one wide class to everyone. `Packages/GanchoKit/Sources/GanchoKit/ClientContract.swift` splits it into twelve capability **facets** — `ClipReading`, `ClipSearching`, `SourceAppProviding`, `ClipMutating`, `ReuseSuggestionProviding`, `ClipEnriching`, `BoardStoring`, `SnippetStoring`, `StoreStatsProviding`, `PrivateActivityReceiptStoring`, `ExportProviding`, `StoreMaintaining` — plus two compositions: `GanchoClientStore` (the read/search/board/export surface a third-party or cross-target client may depend on) and `FullClipStore` (everything the first-party apps hold, including content-free source-app discovery, atomic local reuse suggestions, and the bounded local activity receipt). Feature code takes the narrowest facet it needs; only the composition root sees the concrete `GRDBClipboardStore`.

That surface is **frozen**: it is the supported API, so changes to it are deliberate, documented, and reviewed. GRDB-shaped members that are not facet witnesses (`migrate()`, `thumbnailURL(for:)`) live behind `@_spi(GanchoInternal)` so they stay off the ambient app-facing and external surface; the few internal call sites (tests, the perf harness) opt in with `@_spi(GanchoInternal) import GanchoKit`. `ContractFreezeTests` enforces this in CI: every frozen facet stays declared, every requirement stays documented, and the SPI-gated members stay gated.

### Local-agent authorization boundary

The MCP server has no ambient authority. Enabling it only opens the protocol
edge; each process must select an `MCPClientGrant` with an expiry, explicit
`MCPContextPack`, exposure scope, and independent read/write mode. The runner
reloads that grant before every tool call, so disable, expiry, and revoke affect
already-running stdio clients. Context filters are expressed in the store query
where possible and rechecked before content reads; an out-of-context identifier
is indistinguishable from a missing one. Sensitive clips are excluded under all
grants, and the ledger schema can carry policy/count/denial metadata only.

The CLI and Settings UI are two control surfaces over the same owner-only config
file. Read-only grants omit mutating tools at the protocol edge. Read-write
grants may organize only inside their approved context and cannot create an
arbitrary board or widen their own scope.

Database internals are split by stable responsibility rather than hidden behind a generic repository. `GanchoDatabaseMigrator` is the only ordered registry for the append-only v1–v20 migration identifiers; feature-owned migration bodies can remain beside their feature but must source their identifier from that registry. `ClipRow` and `PinboardRow` are focused internal domain mappings, while `GRDBClipboardStore` owns the database handle and query/write behavior. `DatabaseMigrationTests` freezes the identifier sequence, upgrades plaintext and SQLCipher fixtures from v1, v8, and v16, and proves a failed DDL migration rolls back before a clean resume.

## Privacy invariants

1. **Veto before read.** `ConcealedType`, `TransientType`, and
   `AutoGeneratedType` veto capture before any content read.
2. **Metadata is not content.** Polling `changeCount` and type lists is the only
   always-on macOS loop. Full content reads are isolated, cancelable, and never
   run on the main actor.
3. **No clipboard content in observability.** Logs, telemetry, crash reports,
   analytics, and support bundles may contain metadata buckets only.
4. **No silent iOS capture.** iOS, iPadOS, and visionOS capture is user-initiated
   by design and by App Review reality.
5. **Sync through encrypted envelopes.** The local store may index safe metadata,
   but full content must be encrypted before it is synced.
6. **External processing is opt-in.** Any Private Cloud Compute or third-party
   model action is explicit per action and displays the outbound payload.

## Storage and search

Production storage is GRDB over SQLite with FTS5. SwiftData is not the v1 store:
Gancho needs explicit schema control, fast search, portable export/backup, and a
sync layer whose failure modes are visible.

Store shape:

- `clip` metadata table: id, kind, timestamps, source app/device, sensitivity,
  retention, pin state, content hash, and sync state.
- content-addressed disk blobs for payload bytes and rich representations,
  encrypted in iCloud via `encryptedValues` on sync; the local database is
  whole-database encrypted with SQLCipher (see "Encryption at rest" below).
- FTS5 tables for searchable text, titles, tags, and snippet bodies.
- embedding tables for on-device semantic retrieval.
- a `clip_board` junction plus board metadata and board tombstones.
- `clip_app_stats`: local-only UTC-day integer aggregates for the 13-month,
  explicitly clearable private activity receipt; no content-shaped columns.
- tombstones for sync-compatible deletion.
- an open JSON/CSV export so users can leave without data lock-in.

### Encryption at rest

The whole local database — every table **and the FTS5 index** — is encrypted with
SQLCipher (256-bit AES). We chose whole-database encryption over field-level
encryption deliberately: field-level would leave the FTS index (and therefore the
searchable text) in cleartext, so a stolen `.sqlite` would still leak content.
With SQLCipher a stolen file reveals nothing — no content, previews, titles, or
searchable tokens — and full-text search keeps working unchanged because it runs
inside the decrypted database.

- **Dependency.** Upstream GRDB cannot enable SQLCipher through a plain SwiftPM
  dependency (package traits need Xcode-UI support GRDB still lacks). The supported
  path is a fork that uncomments the marked `// GRDB+SQLCipher:` lines, pulling
  Zetetic's official `sqlcipher/SQLCipher.swift`. Gancho depends on that fork and
  compiles `GanchoKit` with `SQLITE_HAS_CODEC`. No other SQLite library avoids the
  fork (SQLite.swift ships its own `SQLiteCipher.swift` variant; shareup/sqlite
  wraps GRDB; Realm is end-of-life).
- **Key.** A random 256-bit key, never derived from user input, lives in the
  Keychain (`KeychainPassphraseStore`). Entitled builds use
  `kSecAttrSynchronizable` for multi-device restore plus
  `kSecAttrAccessibleAfterFirstUnlock` so background capture can open the store
  while the device is locked. The direct-download Developer ID build has
  intentionally slim entitlements, so when iCloud Keychain access is unavailable
  it falls back to a device-local (`…ThisDeviceOnly`) key that needs no
  entitlement and never leaves the Mac. Reads prefer that device-local key when
  both forms exist, then fall back to the synchronizable key for restores that
  only have the iCloud copy. The key is never logged. On iOS the app writes it
  to a shared keychain access group (`…gancho.keys`) so the keyboard and widget
  extensions — which open the same App Group database — can read it. The macOS
  app uses its default keychain; the Homebrew CLI needs signing to reach the key
  (a known gap, tracked separately).
- **Wiring.** `GRDBClipboardStore.encrypted(directory:)` loads the key and opens
  the pool with `Configuration.prepareDatabase { try db.usePassphrase(key) }`.
  In-memory test stores and the perf harness stay plaintext.
- **Migration.** On the first encrypting launch, a pre-encryption plaintext store
  (detected by its SQLite magic header) is re-encrypted in place with
  `sqlcipher_export`; no clip is lost.
- **Honest claim.** "Data encrypted on disk and in iCloud, without our own
  servers." Never "zero-knowledge" — the Keychain holds the key.

Performance budgets:

- idle macOS capture loop: <0.5% average CPU and no linear memory growth,
- FTS search at 100k items on a current Mac: cold first query <150 ms and warm
  interactive p95 <50 ms, measured separately over reproducibly shuffled rounds,
- semantic retrieval: <100 ms at 10k vectors before it can be user-facing,
- capture pipeline rules/classification before persistence: <10 ms excluding OS
  pasteboard permission stalls,
- UI list interactions: no main-thread content decryption for off-screen rows.

## Sync boundary

`SyncEngine` is a hard boundary. The shared core never imports CloudKit.

The first production implementation is CKSyncEngine over the user's private
iCloud database. It must persist engine state, system fields, tombstones, quota
errors, offline recovery, and reset handling explicitly. The same boundary is
what later permits LAN peer-to-peer, a self-hosted transport, or non-Apple
clients without rewriting capture, search, or the snippet model.

Inbound delivery is **push where push works, explicit pull where it doesn't**.
CKSyncEngine auto-fetches ONLY zones it believes changed, and that belief is fed
exclusively by push — `fetchChanges()` (even scoped to explicit zone IDs) never
asks the server otherwise; it logs "no zone IDs needing to be fetched" and skips.
Push needs the right entitlement key per platform (`aps-environment` on iOS,
`com.apple.developer.aps-environment` on macOS — the wrong one is silently
dropped at signing) plus an explicit `registerForRemoteNotifications()` at
launch on both shells. That works for the foreground iPhone app; the macOS
menu-bar **agent** (`.accessory`, resident, no key window) is not a reliable
APNs target, so the adapter's `pollRemoteChanges()` asks the server directly —
one `databaseChanges` round-trip when idle, incremental `recordZoneChanges`
pulls (own tokens, persisted beside the engine blob) only when the server
reports news — and applies through the SAME code path as the engine's push-fed
fetches. Every `start()` runs it (panel open, wake, the Mac's poll timer, iOS
foreground). The adapter reports fetch/apply/save trouble content-free to the
`DiagnosticLog` ("Recent issues"), so a sync break is diagnosed from the log,
not by guesswork.

## Intelligence tiers

1. **Tier 0 — deterministic and universal.** `RuleClassifier`, data detectors,
   local formatters (Dev Actions), secret detection and masking, and PII
   redaction. Runs on every supported device with zero network.
2. **Tier 1 — Apple on-device models.** Structured annotations, titles,
   embeddings, OCR, semantic retrieval for board suggestions and grounded
   "ask your clipboard" Q&A, plus Smart Paste rewrites/translation when the
   on-device models are available. Sensitive clips are filtered out first, and
   failures never block capture or paste-back. Main history search remains FTS.
3. **Tier 2 — opt-in external or private-cloud actions.** Used only for explicit
   transformations where the user approves the outbound content.

Model seams live in `GanchoAI`; UI and storage should not depend on any concrete
AI provider.

## Extension-safe storage

Share extensions, widgets, keyboard extensions, App Intents, and future desktop
extensions must not each invent their own persistence path. They should use a
shared app-group container with a narrow write/read API, short transactions, and
clear conflict behavior. SQLite WAL mode and extension memory limits are design
constraints, not afterthoughts.

## Portability strategy

Non-Apple clients are a future business decision, but the code should not make
them impossible:

- define a versioned content envelope before syncing rich content,
- keep privacy policy and retention rules in shared engine modules,
- keep platform capture adapters replaceable,
- expose a CLI/MCP surface that exercises the same store and sync contracts,
- prove export/import early, and
- document a capability matrix before committing to Android, Windows, or Linux.

For now, non-Apple work stops at analysis: capability matrix, portable envelope,
and stack options. A read/search/paste companion or native capture adapter only
becomes a planned workstream after an explicit product decision.

## Build and quality gates

- `project.yml` is the source of truth for the generated Xcode project.
- `make format`, `make lint`, and `make test` are required before commits.
- `make build` must pass for macOS; `make build-ios` must pass when shared or
  iOS code changes.
- Swift Testing is the unit-test framework. XCTest is reserved for UI tests.
- Public symbols in engine-room targets require documentation comments that
  explain constraints and rationale.
- User-facing strings go through a String Catalog with English and Spanish from
  the first real UI string.

## Decisions

1. **Minimum macOS 26 / iOS 26.** SDK-27 APIs are adopted only behind
   `#available`; beta SDKs are not installed on work machines.
2. **XcodeGen project.** `Gancho.xcodeproj` is generated; edit `project.yml` and
   run `make project`.
3. **Swift 6 strict concurrency.** App modules default to `@MainActor`; shared
   engine-room targets are nonisolated + `Sendable` unless a type has a real
   isolation requirement.
4. **GRDB + FTS5 + CKSyncEngine.** Explicit local storage and explicit sync beat
   hidden persistence magic for this product.
5. **Native Apple UI first.** Liquid Glass, keyboard access, accessibility, and
   platform idioms are not polish; they are part of the product surface.
6. **No backend by default.** A future backend must be a sync implementation,
   not a prerequisite for the product to function.

## Performance signposts and SLOs

The interactive-latency budgets, and the content-free `OSSignposter` intervals
that measure them (see `Apps/Gancho*/Signposts.swift`; the API takes no strings
or values, enforced by `SignpostHygieneTests`):

| Interval (signpost) | Budget (warm p95) | Where it begins → ends |
| --- | ---: | --- |
| `panel-to-first-frame` | < 100 ms | `PanelController.show()` → `PanelView.onAppear` |
| `query-to-results` | < 75 ms | search field change → results applied |
| `launch-to-store-ready` | — (cold) | `AppModel.init` start → durable store ready |
| `paste-dispatch` | < 100 ms | paste action → `⌘V` event posted (target-app time excluded) |
| iOS `capture-to-insert` | < 250 ms | ingest accepted → durable insert |

Baselines are collected from real warm runs, not asserted in CI (device- and
thermal-dependent). `-measure-panel` prints the panel first-frame wall-clock so
a manual/UI run collects samples; the opt-in `GANCHO_PERF=1` harness holds the
scale budgets (FTS, semantic retrieval, board paging). Instruments/energy
traces (30-min idle CPU, repeated-round RSS) are reference-Mac evidence.
