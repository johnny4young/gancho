# 05 — Startup performance (cold / warm launch, iOS + macOS)

Scope: time-to-first-paint for the iOS app, the macOS menu-bar agent, and the
store-opening extensions (keyboard, widget intents, share pipeline). Grounded
in file:line as of branch `claude/gancho-engineering-audit-byfy24`. Line
numbers reflect the state AFTER the Phase-1 change applied in this pass
(see "Applied in this pass" below).

---

## 1. Critical-path breakdown

### 1.1 What every store open costs (shared engine path)

`GRDBClipboardStore.convenience init(directory:passphrase:)` —
`Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift:32-73`.
Every process that opens the durable store pays, synchronously, in order:

| # | Step | Where | Steady-state cost | First-run / worst cost |
|---|------|-------|-------------------|------------------------|
| 1 | `createDirectory` | GRDBClipboardStore.swift:33 | <1 ms (exists) | ~1 ms |
| 2 | Plaintext-header check `encryptPlaintextStoreIfNeeded` | GRDBClipboardStore.swift:48, 100-133 | <1 ms (16-byte read + compare) | **seconds** — full `sqlcipher_export` re-encrypt of a legacy plaintext DB (one time ever, correctness-critical, keep) |
| 3 | `DatabasePool(path:configuration:)` + SQLCipher `PRAGMA key` | GRDBClipboardStore.swift:60, 49-51 | **~50–250 ms** — see §1.2, the KDF is the likely dominant term | same |
| 4 | `BlobStore.encryptPlaintextFilesIfNeeded()` | GRDBClipboardStore.swift:64 → BlobStore.swift:144-152 | <1 ms (one `fileExists` on the `.blobs-encrypted` marker) | one full directory scan + header-read per blob/thumbnail (one time ever, guarded by marker, keep) |
| 5 | `migrator.migrate(pool)` — 15 registered migrations (v1–v15, GRDBClipboardStore.swift:194-364) | GRDBClipboardStore.swift:68 | ~1–5 ms (reads `grdb_migrations`, applies nothing) | fresh install: all 15 (tens of ms); post-update: only the new ones (v2 FTS rebuild over existing rows is the expensive historical case) |
| 6 | ~~`reformatLegacyImagePreviews(in: pool)`~~ **REMOVED from the open path in this pass** | was GRDBClipboardStore.swift:69 | was: a **write transaction** running `SELECT … WHERE kind=? AND preview LIKE 'Image (% bytes)'` on *every* open — `LIKE` with a leading-anchored-but-wildcarded pattern cannot use an index, so it scanned every image row (~1–50 ms for a few-thousand-clip history) **and took the write lock**, contending with the keyboard/widget/app opening the same App Group DB | n/a — now post-launch, §3 |

Additional cost feeding step 3: `GRDBClipboardStore.encrypted(directory:keychainAccessGroup:)`
(GRDBClipboardStore.swift:83-89) first does a synchronous Keychain round-trip —
`KeychainPassphraseStore.loadOrCreateKey()` → `SecItemCopyMatching` with
`kSecAttrSynchronizableAny` (KeychainPassphraseStore.swift:68-82, 109-134).
Typically ~5–30 ms; can be slower right after boot/unlock or under
`securityd` contention. First launch also does `SecRandomCopyBytes` + `SecItemAdd`.

### 1.2 The likely dominant term: SQLCipher key derivation (needs on-device verification)

GRDBClipboardStore.swift:49-51 keys the database with
`db.usePassphrase(passphrase)` where the passphrase is a **64-char hex string**
(KeychainPassphraseStore.generateKey, KeychainPassphraseStore.swift:153-160).
SQLCipher treats any string passphrase as input to its KDF (PBKDF2-HMAC-SHA512,
default 256,000 iterations in SQLCipher 4) — and runs it **per connection**,
so a `DatabasePool` pays it again for each reader connection it spins up, not
just once per open. On mobile hardware this is plausibly 50–150 ms per
connection: very likely the single largest fixed cost of cold launch, paid by
the app, the keyboard, and every widget-intent invocation.

Because the key is already a random 256-bit value (never user-derived), the KDF
adds **zero security** here — SQLCipher's raw-key syntax
(`PRAGMA key = "x'<64 hex>'"`) exists exactly for this case and skips the KDF
entirely. But switching is a *different effective key*: existing databases were
encrypted with `KDF(hex-string)`, so a migration (open with passphrase →
`sqlcipher_export` into a raw-keyed sibling → swap, mirroring
`encryptPlaintextStoreIfNeeded`) is required. **Not applied** — cannot be
verified without a device and it touches the at-rest encryption path. See
Phase 2 (P2-B). Verify the magnitude first with a signpost around
`DatabasePool` creation (Phase 3).

### 1.3 iOS cold launch (first paint blocked by ALL of this)

`Apps/GanchoiOS/GanchoiOSApp.swift`:

- `@main GanchoiOSApp` line 18: `@State private var model = IOSAppModel()` —
  the model is constructed inside `App.init`, on the main thread, **before
  SwiftUI renders anything**.
- `IOSAppModel` is `@MainActor` (line ~211). Its stored-property initializers
  and `init()` (lines ~268-288) run synchronously:
  - `store` (lines 745-758): immediately-invoked closure →
    `GRDBClipboardStore.encrypted(...)` — the full §1.1 + §1.2 chain
    (Keychain → pool open + KDF → migrations; the backfill scan is now gone).
  - `thumbnails = ClipThumbnailStore(store: store)` (line 270) — forces the
    `store` lazy-let to resolve even earlier in init order.
  - `telemetry` IIFE (line 374): `TelemetryDeckSender` construction +
    `record(.appLaunched)` — SDK init on the main thread (~ms, but nonzero).
  - `IntelligencePreferences.load`, `StoreKitPurchaseHandler` construction,
    a `Task` for `purchases.currentTier()` (async, fine),
    `recordStorageHealthIfNeeded()` (cheap).
- Only after all of that does `WindowGroup` produce `CaptureView` /
  `IPadSplitView` and the first frame commit.

**Cold-launch critical path (iOS):** dyld + Swift runtime → `IOSAppModel.init`
(Keychain ~10 ms + pool open/KDF ~50–250 ms + migrator check ~2 ms + telemetry
init) → first SwiftUI body evaluation → first commit. The store open is the
only triple-digit-millisecond item and it is 100% serial on the main thread.

**Warm launch (iOS):** process alive, scene re-foregrounds — the model already
exists, so warm cost is `DatabaseSuspension.resume()` (a notification post,
GanchoiOSApp.swift:60-64 / DatabaseSuspension.swift:26-28), `refreshHints` +
`search()` off an async task. Warm launch is fine; the problem is cold.

**iOS extensions (memory- and time-constrained):**
- Keyboard: `KeyboardModel.init` → `IntentStore.open()` **synchronously**
  (Apps/GanchoKeyboard/KeyboardModel.swift:59,
  Apps/GanchoShared/SharedCaptureIntent.swift:10-17) — pays §1.1+§1.2 every
  time the keyboard comes up.
- Widget intents / Control Center save: same `IntentStore.open()` per
  invocation.
- Removing step 6 (the every-open write-transaction scan) directly shortens
  keyboard bring-up and removes a source of write-lock contention between the
  keyboard/widget and the app opening the same App Group database.

### 1.4 macOS cold launch

`Apps/GanchoMac/GanchoMacApp.swift`:

- `GanchoMacApp.init` (lines 17-23) runs, in order, on the main thread:
  1. `GanchoSingleInstance.terminateOlderCopies()` (lines 61-85) — normally
     ~0 ms, **but if an older copy is running (e.g. relaunch after update) it
     busy-waits the RunLoop up to 1 s per copy, then force-terminates and
     waits up to another 0.5 s**. Worst case adds ~1.5 s before anything else.
  2. `AppModel()` — synchronous, `@MainActor` (Apps/GanchoMac/AppModel.swift:162-):
     - line 168: `GRDBClipboardStore.encrypted(directory:)` — full §1.1+§1.2
       chain (backfill scan now removed).
     - `monitor.start()` (line 211), retention + screen-share timers,
       `panel.attach`, KeyboardShortcuts registration, telemetry init +
       `record(.appLaunched)` (line 243).
     - Async after init (fine): `refreshRecents()`, StoreKit tier,
       welcome/permission windows, and (new) the legacy-preview backfill at
       utility priority (line 253-257).
- The status item / helper only appears in
  `applicationDidFinishLaunching` (GanchoMacApp.swift:99-135), which cannot
  run until `App.init` (and thus the full `AppModel.init`) returns. So the
  menu-bar icon and ⇧⌘V panel availability are gated on the synchronous store
  open exactly like iOS first paint.

**Warm on macOS** is not a lifecycle event (resident agent); the equivalent is
panel-show latency, which is unaffected by this dossier except that launch-time
write locks no longer collide with the first `refreshRecents()`.

---

## 2. Staged plan

### Phase 1 — SAFE mechanical wins

| ID | Size | Change | Status |
|----|------|--------|--------|
| P1-A | S | **Move `reformatLegacyImagePreviews` off the synchronous open path.** Remove the call from `convenience init`; expose `public func backfillLegacyPreviews() async throws` (async `writer.write`, so it runs on GRDB's queue, not the caller's thread); call it post-first-render from both apps. Safe because it is purely cosmetic AND the UI already humanizes legacy previews at display time (`ByteSize.humanizedPreview`, ByteSize.swift:15-18, used by GanchoDesign/Components.swift:106,214 and WidgetClips.swift:58) — so even a clip rendered before the background pass completes shows "Image (717 KB)". Idempotence unchanged (a rewritten row no longer matches the LIKE pattern). Sync churn unchanged (still does not touch `updatedAt`/`needsUpload`). | **APPLIED** (see §3) |
| P1-B | S | Optionally also gate the backfill behind a one-time app-side flag (e.g. a `UserDefaults` "legacy-previews-backfilled" bool) so steady-state launches skip even the background scan. Not applied: the scan is now off the critical path and runs at background QoS; a defaults flag adds state that can go stale across restores/sync-ins ("synced-in" legacy previews arrive later — the doc comment in LegacyPreviewBackfill.swift explicitly anticipates them). Revisit only if Instruments shows the background pass mattering. | documented only |
| P1-C | S | iOS: move the `telemetry` IIFE (`TelemetryDeckSender` init, GanchoiOSApp.swift:374) into a post-launch task or make it `lazy`. Not applied: `@Observable` macro interaction with `lazy var` + the IIFE's `record(.appLaunched)` ordering semantics are easy to get subtly wrong without compiling; est. saving is single-digit ms. | documented only |
| P1-D | S | macOS: cap `GanchoSingleInstance.waitForTermination` (GanchoMacApp.swift:79-84) — e.g. don't block on graceful termination at all; force-terminate stale copies and proceed, or move the wait off the launch path. Only bites on update-relaunch, but then it costs up to 1.5 s. Not applied: single-instance correctness (two agents fighting over one status item / DB) needs on-machine verification. | documented only |
| P1-E | S | CLI note: `gancho` CLI opens (GanchoCLI.swift:178,230) no longer run the backfill. Intentional — the apps own maintenance; the CLI open gets faster too. If CLI-only installs matter, add one `backfillLegacyPreviews()` call to a maintenance subcommand. | documented only |

### Phase 2 — STRUCTURAL (specified, NOT implemented — too invasive to land unverified)

**P2-A (L): async store bootstrap on iOS — render a launch shell immediately.**

Goal: first frame paints before the store opens; the store opens off the main
actor; the UI publishes readiness.

Sketch (`IOSAppModel`):

```swift
enum StoreState { case opening; case ready(any ClipboardStore); case failed }

@Observable @MainActor final class IOSAppModel {
    private(set) var storeState: StoreState = .opening
    // Transitional shim so existing call sites keep compiling:
    var store: any ClipboardStore {
        if case .ready(let s) = storeState { return s }
        return pendingStore  // a shared InMemoryClipboardStore placeholder
    }
    private let pendingStore = InMemoryClipboardStore()

    init() {
        // ... everything that does NOT need the store ...
        Task.detached(priority: .userInitiated) { [weak self] in
            let opened: any ClipboardStore =
                (try? GRDBClipboardStore.encrypted(
                    directory: SharedStorageLocation.storeDirectory(
                        appGroupID: SharedInbox.appGroupID),
                    keychainAccessGroup: KeychainPassphraseStore.iosSharedAccessGroup))
                ?? InMemoryClipboardStore()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.storeState = .ready(opened)
                self.recordStorageHealthIfNeeded()
                Task { await self.search(); await self.refreshBoards() }
                self.configureSync()
            }
        }
    }
}
```

`GanchoiOSApp.body` renders `CaptureView` immediately; `CaptureView` shows its
existing empty/loading state until `storeState` flips (add a subtle
`ProgressView` only if it can reuse an existing localized string — otherwise
none; the list simply populates ~100–250 ms after first paint).

Blast radius — every place that must tolerate "not ready yet"
(all in Apps/GanchoiOS/GanchoiOSApp.swift unless noted; line numbers post-edit):

- Construction-order dependency: `thumbnails = ClipThumbnailStore(store: store)`
  (line 270) — `ClipThumbnailStore` must take the model or a closure instead of
  the store value (the macOS one already takes a closure, AppModel.swift:172-177 —
  copy that pattern).
- `storageIsEphemeral` (line ~762) — must not report "ephemeral" while
  `.opening`, or the data-loss banner flashes on every launch. Gate on
  `.ready`/`.failed`.
- `recordStorageHealthIfNeeded` (line ~770) — call on readiness, not in init.
- `configureSync` (line ~294, `store as? GRDBClipboardStore` guard) — call on
  readiness (the tier Task can land before the store; today's code silently
  no-ops and never retries — that bug becomes visible with async open, so
  re-invoke `configureSync()` from the readiness transition).
- Every `store as? GRDBClipboardStore` guard already degrades gracefully to a
  no-op/empty result, which makes this refactor tractable: `handleDeepLink`
  (~403), `refreshBoards` (~420), `clipCount` x2 (~433, ~439), `saveAsSnippet`
  (~446), `createBoard` x2 (~461, ~483), `boardMembership` (~500),
  `suggestedBoard` (~509), `setBoardMembership` (~540), `renameBoard` (~554),
  `deleteBoard` (~567), `search`/`loadRecentPage` (~591/~613), `togglePin`
  (~724), `delete` (~730), `askClipboard` (~707), `makeBackupArchive` (~783),
  `restoreBackup` (~800), `enrich` (~914), plus `store.content(for:)` in
  `copyToPasteboard` (~645) and `FullScreenImageView` (~169), and
  `store.insert` in `ingest` (~888).
  With the placeholder-store shim they all keep compiling; the ones that must
  *retry* after readiness are exactly `search`, `refreshBoards`,
  `drainSharedInbox`, and `configureSync` — trigger those from the readiness
  transition.
- `ingest` during `.opening` (share-sheet cold start, paste control): either
  buffer captures until ready, or accept the placeholder-store write and replay
  it into the real store on readiness. Buffering is simpler and lossless:
  captures already flow through one `ingest(_:precomputedKind:)` funnel (~873).

**P2-B (M): SQLCipher raw-key adoption (kills the per-connection KDF).**
Add a one-time migration in `convenience init`: if the DB opens with the
passphrase-KDF key (current behavior) — detected by attempting
`PRAGMA key = "x'<hex>'"` first and falling back — run `sqlcipher_export` into
a raw-keyed sibling and swap, exactly mirroring
`encryptPlaintextStoreIfNeeded` (GRDBClipboardStore.swift:100-133), then
change `prepareDatabase` to raw-key `PRAGMA`. Must be verified on-device
(SQLCipher build flags, GRDB `usePassphrase` semantics, WAL siblings) and
covered by a reopen test in GRDBEncryptionTests. Expected win: removes
~50–150 ms *per connection* from every open in every process. Do not attempt
without a device.

**P2-C (M): macOS — construct `AppModel` with the same async-open pattern**
(open the store in a detached task, keep `grdbStore` as published state,
let `applicationDidFinishLaunching` put the status item up immediately). Same
call-site tolerance analysis; macOS is easier because `grdbStore` is already
`GRDBClipboardStore?` everywhere (AppModel.swift:48).

### Phase 3 — Measurement (do FIRST on a device, before P2)

- **MetricKit** (iOS): subscribe in `GanchoiOSApp`/an app-side helper via
  `MXMetricManager.shared.add(_:)`; read `MXAppLaunchMetric`
  (`histogrammedTimeToFirstDraw`, `histogrammedApplicationResumeTime`) from
  daily payloads. App-side only — never in `Packages/GanchoKit` (logging sweep).
- **Signposts** (app targets only, never engine modules): wrap
  (a) `KeychainPassphraseStore.loadOrCreateKey` call site,
  (b) `GRDBClipboardStore.encrypted(...)` call site (GanchoiOSApp.swift:754,
  AppModel.swift:168), with `OSSignposter.beginInterval/endInterval` — this
  splits Keychain vs pool-open/KDF vs migrate without touching GanchoKit.
- **Instruments**: App Launch template + os_signpost track; confirm the KDF
  hypothesis (§1.2) by watching `sqlite3_key` / PBKDF2 frames under the pool
  constructor.
- **xcodebuild**: `xcrun xctrace record --template 'App Launch' --launch
  <bundle-id>`; and a unit-level perf check in the existing perf harness that
  measures `GRDBClipboardStore(directory:passphrase:)` open time at v15 with a
  populated store (the harness already knows how to populate at a version,
  GRDBClipboardStore.swift:150).

---

## 3. Applied in this pass (Phase 1, P1-A)

1. `Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift` — removed
   `try Self.reformatLegacyImagePreviews(in: pool)` from
   `convenience init(directory:passphrase:)` (was line 69); left a comment
   pointing at the post-launch entry point.
2. `Packages/GanchoKit/Sources/GanchoKit/LegacyPreviewBackfill.swift` —
   added `public func backfillLegacyPreviews() async throws` (async
   `writer.write`, mirroring every other async method in the store); kept the
   static `reformatLegacyImagePreviews(in:)` (still used by
   `LegacyPreviewBackfillTests.swift:35`) and factored the shared body into a
   private `static reformatLegacyImagePreviews(db:)`. No logging added.
3. `Apps/GanchoiOS/GanchoiOSApp.swift` — `.task { … backfillLegacyPreviews() }`
   on the root view group (runs after first render; no-op on the in-memory
   fallback / `-force-ephemeral-store`).
4. `Apps/GanchoMac/AppModel.swift` — `Task(priority: .utility) { … }` at the
   end of `init`, only when the GRDB store opened.

No new user-facing strings. No engine logging. Tests unaffected
(`LegacyPreviewBackfillTests` calls the static directly; no other test or
production path depends on init-time backfill — display-time humanization via
`ByteSize.humanizedPreview` covers rendering in all surfaces).

## 4. Expected wins

| Change | Removed from the critical path | Est. saving (steady-state cold launch) |
|--------|-------------------------------|----------------------------------------|
| P1-A backfill off open path (**applied**) | one write transaction + unindexed LIKE scan of all image rows, per open, in app + keyboard + widget intents + CLI; plus cross-process write-lock contention at launch | ~1–50 ms per open (history-size dependent); keyboard bring-up benefits every invocation |
| P1-D macOS single-instance wait cap | up to ~1.5 s busy-wait on update-relaunch | 0 ms typical, ~1.5 s worst case |
| P2-B SQLCipher raw key | PBKDF2 (~256k iter) per pool connection, every process | ~50–150 ms per connection (verify with signposts first) |
| P2-A/P2-C async bootstrap | the entire store open (Keychain + pool + KDF + migrate) off first paint | first paint improves by the full remaining open cost (~60–300 ms); content pops in asynchronously |
| P1-C telemetry off init | TelemetryDeck SDK init on main | low single-digit ms |
