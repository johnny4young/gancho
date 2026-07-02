# Retention / tier P0-P1 fixes (B-10 … B-14)

Scope: dossier `04-bugs-features-worldclass.md`, PART A §A.2. Branch
`claude/gancho-engineering-audit-byfy24`. Validation is the GanchoKit test
suite on CI (no local toolchain).

## B-11 (P1) — TierEnforcement gated on the legacy `pinboardID` column

**Fix** (`Packages/GanchoKit/Sources/GanchoKit/TierEnforcement.swift`): both
free-tier UPDATEs now use `id NOT IN (SELECT clipID FROM clip_board)` — the
same subquery phrasing RetentionEngine uses — instead of `pinboardID IS NULL`,
which nothing has written since the v10 junction migration.

**Semantics:** a clip filed on any board (Favorites included) is exempt from
both the 30-day window and the 2,000-item ceiling, matching the type's doc
comment ("board members are never archived"). The rest of each predicate is
unchanged; the Pro release path is unchanged.

**Not addressed here (dossier's "bonus inconsistency"):** `items(inBoard:)`
still shows archived members (`Pinboards.swift:163-173`). With this fix a
board member can no longer *become* archived, so the visible inconsistency
can only arise from pre-fix rows until the next Pro pass releases them.
Making all surfaces agree on archived-member visibility is a product decision
left open.

## B-12 (P1) — sensitive clips were archived despite the doc's claim

**Fix** (same file): `AND isSensitive = 0` added to both free-tier UPDATEs.

**Semantics:** sensitive rows are never archived; retention owns their
lifecycle (10-minute default expiry). Archiving one would hide it from
`sensitiveCount()` / the Privacy Center while it still sat on disk — and a
later Pro upgrade would release ("hide-then-release") the secret back into
history.

## B-14 (P1/P2) — re-copying archived content made the copy invisible

**Fix** (`Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift`,
`insert` dedupe branch only): the dedupe path now sets
`existing.isArchived = false` alongside the existing `lastUsedAt`/`updatedAt`
touch.

**Semantics:** a fresh copy is fresh activity — content whose row tier
enforcement archived re-enters visible history immediately on re-copy instead
of the capture silently landing in the hidden set. Note the count-ceiling
clause orders by `createdAt`, so a revived old row may re-archive on a later
free-tier pass if it is still beyond the newest-2,000 window; the dossier's
prescription is intentionally limited to reviving on dedupe-touch.

## B-10 (P0) — iOS never ran RetentionEngine / TierEnforcement

**Fix** (`Apps/GanchoiOS/GanchoiOSApp.swift`):

- New `IOSAppModel.runMaintenance()`: guards `store as? GRDBClipboardStore`,
  runs `RetentionEngine(store:).runPurge(policy:)` then
  `TierEnforcement(store:).enforce(tier:)`, then `await search()` to refresh
  the visible list (the same reload every other mutation path uses).
- Wiring: the App's existing `.onChange(of: scenePhase)` handler now, on
  `.active`, calls `DatabaseSuspension.resume()` first and then fires
  `Task { await model.runMaintenance() }` — so every return to foreground
  runs a purge + tier pass. This mirrors the Mac's timer-driven
  `runRetention()` (`Apps/GanchoMac/AppModel.swift:1241-1250`) in order and
  parameters.
- **Policy source:** iOS has no retention-policy UI, so the policy comes from
  `RetentionPolicy.load(from: UserDefaults.standard)` — identical to the
  Mac's persistence key; it decodes to the same `RetentionPolicy()` defaults
  (global 365d, sensitive 600s) until an iOS settings surface writes one.
- **Tier source:** the model's existing `tier` property (StoreKit
  `purchases.currentTier()` on launch, `onTierChange`, and the debug
  force-pro toggle) — the same source of truth the Pro screen and pin/board
  gates already use.
- No new user-facing strings; no new imports (GanchoKit was already
  imported).

**Deliberately NOT added (out of prescribed scope):** `BGAppRefreshTask`
scheduling and the read-time `expiresAt` filter on `items`/`search`/widget
feeds that the dossier lists as defense-in-depth — those touch
`GRDBClipboardStore` read paths and app entitlements beyond this task's
editable file set.

## B-13 (P2) — boarding/pinning a secret cancels its expiry: DEFERRED

The prescription requires changing RetentionEngine purge clauses 1–2 (drop
the pin/board/snippet exemptions for sensitive/expiring rows) or adding a UI
warning. `RetentionEngine.swift` is owned by another in-flight agent (it was
concurrently rewritten during this task to add sync tombstones to every purge
clause), and this task's constraints exclude it. Dossier's exact fix, for
whoever picks it up: clauses 1 (per-item `expiresAt`) and 2 (sensitive
lifetime) should apply regardless of `isPinned`/`clip_board`/`isSnippet`
status, or the UI must warn when favoriting a sensitive clip; either way pin
the decision in a test. Note the CHANGELOG claim "detected secrets always
follow the shorter Sensitive items limit" stays false until this lands.

## Tests (`Packages/GanchoKit/Tests/GanchoKitTests/TierEnforcementTests.swift`)

New cases, existing fixture style (in-memory `DatabaseQueue`, fixed `now`):

- `junctionBoardMembersExempt` — junction-only board member older than the
  free window survives `enforce(tier: .free)`; the 3 non-member seeds
  archive. Regression for B-11 (fails pre-fix: `pinboardID IS NULL` matched
  it).
- `sensitiveExempt` — an over-window sensitive clip survives; also asserts
  `sensitiveCount() == 1` (the Privacy Center under-count from the dossier).
  Regression for B-12.
- `countCeilingSkipsExemptRows` — with the 2,000-item ceiling exactly full,
  an older sensitive clip and an older board member are NOT pushed into the
  archive by the count clause (covers the second UPDATE for both B-11 and
  B-12; the two tests above cover the age clause).
- `dedupeRevivesArchivedRow` — archive the oldest row via the count ceiling,
  re-insert identical content (same `contentHash`, nil device), assert
  `archivedCount()` drops to 0 and the row is back in `items()`. Regression
  for B-14.

**B-10 coverage:** the wiring is app-side (SwiftUI scene lifecycle) and not
package-testable; the engine behaviors it invokes are covered by
RetentionEngineTests and the TierEnforcementTests above, so the iOS pass
exercises only already-tested code paths.
