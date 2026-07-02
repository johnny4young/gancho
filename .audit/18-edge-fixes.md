# 18 — Edge fixes: A-4, B-4, A-5 (from `.audit/14`)

**Date:** 2026-07-02 · **Branch:** `claude/gancho-engineering-audit-byfy24` · **Scope:** the
three edge findings from `.audit/14-security-performance-deep-dive.md` — the pasteboard-veto
TOCTOU window (A-4), the per-foreground iOS maintenance storm (B-4), and visibility for an
elevated MCP scope (A-5). No Swift toolchain in this environment; every edit mirrors an
in-file pattern and is gated on CI.

---

## A-4 — Pasteboard veto re-checked at read time (P3, security)

**Files:**
- `Packages/GanchoKit/Sources/ClipboardCore/MacPasteboardMonitor.swift`
- `Packages/GanchoKit/Tests/ClipboardCoreTests/MacPasteboardMonitorTests.swift`

**What changed.** `pollOnce` vetoes on the types observed at `changeCount = N`, but the
detached read (`readDetached`) returns whatever is on the pasteboard when it runs — a fast
A→B swap could slip vetoed content under the old change's clean types. The fix re-fetches
`reader.currentTypes()` **inside the detached task, immediately before `readPayload()`**, and
drops (returns nil) if the current types now contain `MacPasteboardMonitor.selfWriteMarker`
or intersect `SensitivePasteboardTypes.captureVeto`.

**Placement.** The re-check lives inside the `Task.detached` closure in
`MacPasteboardMonitor.readDetached`, after the existing cancellation guard and before the
one `readPayload()` call — the same detached context as the read, so no new window opens
between the re-check and the read beyond the irreducible types→payload gap.

**Ignore semantics.** The drop is silent, matching what the code does for a cancelled read:
by the time the re-check fires, a swap has bumped `changeCount`, so the next `pollOnce`
re-vetoes the new change and fires `onIgnore(.sensitiveType)` through the normal path. No
double-counting in the Privacy Center.

**Test.** `FakePasteboard` gained an opt-in `typesOnRecheck` (returned from the second
`currentTypes()` call on — deterministic, no sleep-race), and a new case
`sensitiveVetoRecheckedAtReadTime` asserts that clean types at poll time + a concealed
marker at re-check time yields **no capture and zero `readPayload` calls**. The shared
`ProductionMonitorTests` suite is unaffected (the knob defaults to nil; the extra
`currentTypes()` call per read has no scripted side effects).

## B-4 — iOS foreground maintenance throttled (P2, perf)

**File:** `Apps/GanchoiOS/GanchoiOSApp.swift`

**What changed.** `IOSAppModel.runMaintenance()` (RetentionEngine purge + TierEnforcement +
the orphan-blob directory sweep) ran on **every** scenePhase `.active`. It now runs at most
once per **10 minutes**: the guard lives inside `runMaintenance()` (the `.active` call site
is untouched), reading a persisted `lastMaintenanceAt` Date from the model's existing
`defaults` (`UserDefaults.standard`, key `ios-last-maintenance-at`, via the same
`defaults` property `IntelligencePreferences` already uses) and returning early when less
than `maintenanceInterval` has elapsed. The timestamp is written **after** a successful
pass (purge + enforce), so a throttled foreground skips the whole pass including the
follow-up `search()` refresh — the existing `refreshHints()`/`activate()` foreground paths
already refresh the list.

**Interval choice.** 10 min sits inside the audit's 5–15 min band and matches the
"auto-expires after 10 minutes" sensitive-clip promise: a flagged secret is still purged by
the first pass at-or-after its expiry, one foreground later at worst.

**Test state.** The throttle is three lines of app-side lifecycle around UserDefaults and
`Date()`; it is not extractable into a pure helper without inventing a seam solely for the
test (the app target has no unit-test bundle wired for `IOSAppModel`). Recorded here per
the dossier convention instead of adding a test-only abstraction.

## A-5 — Elevated MCP scope made loud at server start (P2, security)

**Files:**
- `Packages/GanchoKit/Sources/GanchoKit/MCPAccess.swift`
- `Packages/GanchoKit/Sources/gancho/GanchoCLI.swift`
- `Packages/GanchoKit/Tests/GanchoKitTests/MCPAccessScopeTests.swift` (new)

**What changed.** Minimal, non-breaking visibility — no change to the on-disk
`mcp-config.json` format or the `gancho enable`/`disable` semantics:

1. `MCPServerConfig.isElevated` (computed, `scope != .metadata`) with a doc comment naming
   the threat: the config file is plaintext, so any local process can raise the scope —
   callers surface elevation, they don't gate on it.
2. `runMCP` in the CLI, right after the existing `gancho mcp: ready …` stderr line, prints
   (stderr — allowed for the CLI executable, never mixed into the stdio MCP protocol on
   stdout) when `isEnabled && isElevated`:
   `gancho mcp: ⚠ scope=all exposes the full content of ALL non-sensitive clips to any
   connected client. Run `gancho enable --scope metadata` to restrict.` (`boards` gets the
   analogous "pinned/board clips" wording.)
3. A small `GanchoKitTests` suite pins `isElevated` for all three scopes and the default
   config.

**No new user-facing app strings** — CLI stderr text is unlocalized by existing convention,
so the bilingual (en+es) String Catalog gate is not triggered.

**Follow-up (deliberately NOT built now): capability-token handshake.** The full fix for
the plaintext-flip exploit chain (local process writes `scope: all`, spawns `gancho mcp`,
reads all non-sensitive history) is app-minted authority:

- The **app** (menu-bar agent) mints a random capability token when the user raises scope
  above `metadata`, stores it keychain-side (app-only access group), and writes only a
  token **hash** + expiry into `mcp-config.json`.
- `gancho mcp` must present the token (env var or `--token`, obtained via an app-brokered
  handout such as `gancho enable` deep-linking into the app for user confirmation) and the
  server verifies it against the hash before honoring `boards`/`all`; a missing/stale token
  degrades to `metadata` — fail-safe, mirroring the existing "missing file means OFF".
- The app posts a user-visible notification when scope becomes `all` and on a new client's
  first connect, complementing the Privacy Center access log.
- Breaking-change surface: the documented `gancho enable --scope all` one-liner becomes a
  two-step (app confirmation) flow — which is exactly why it needs a docs + UX pass and is
  not bundled into this warning-only change.

---

## CI expectations

- New/changed tests: `MacPasteboardMonitorTests` (+1 case, +1 fake knob),
  `MCPAccessScopeTests` (new, 2 cases). Existing suites untouched.
- No logging added to engine modules (`ClipboardCore` change is pure control flow;
  `MCPAccess.swift` gains a computed property); the only new prints are CLI stderr.
- No new localized strings; `LocalizationTests` unaffected.
