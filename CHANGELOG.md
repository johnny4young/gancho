# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.2] - 2026-06-28

### Added

- An **Undo window** for deleting a clip (macOS): the clip disappears at once,
  but the destructive removal — and the iCloud tombstone that propagates it to
  your other devices — only commits after a few seconds, with a "Deleted · Undo"
  toast. A mis-tap never loses history, and pins, boards, and timestamps all
  survive an Undo intact.
- A **Gancho Pro screen on iPhone/iPad** (Settings → Gancho Pro): it shows what
  Pro unlocks, whether you're on the free or Pro plan, and a Restore Purchase
  button — and it now opens automatically when you reach a free-tier limit,
  instead of a note that vanished with no way forward.
- **VoiceOver announcements** for action confirmations across the Mac app, the
  iPhone app, and the keyboard: copy, paste, save, pin, delete, and "Synced"
  are now spoken aloud, not just shown.

### Changed

- The Mac panel's sync indicator now reads **"Synced · &lt;time&gt; ago"** with a
  live relative timestamp, so a finished sync reads as current rather than stale.
- Activating a Pro license on the Mac now explains **exactly why** a key didn't
  take — a wrong or used-up key, no network, or a save failure — instead of one
  generic message, and a successful activation shows a "Welcome to Pro" moment.
- Count labels are grammatically correct in English and Spanish now ("1 clip",
  not "1 clips").

### Fixed

- A valid Pro license that couldn't be saved to the Keychain no longer shows a
  false "Welcome to Pro": activation confirms the license actually persisted
  before unlocking, and reports a clear error otherwise (direct-download Mac).
- Deleting your most-recent clip no longer leaves the menu-bar "Last copied"
  preview pointing at the clip you just removed.

## [0.3.1] - 2026-06-28

### Added

- Gancho Pro is now purchasable from the direct-download Mac app: the paywall
  opens the checkout and activates your license key on the spot (it previously
  showed "Pro is coming soon"). The Mac App Store build keeps using in-app
  purchase.

## [0.3.0] - 2026-06-28

### Added

- iPhone/iPad can now **back up and restore your history** from Settings → Your
  history, using the same portable `.ganchoarchive` format as macOS — so a
  backup made on one device imports on another. The export goes through the
  system file picker (save anywhere in Files), restore merges and de-dupes by
  content, and the archive is checksummed and never auto-uploaded.
- iPad **hardware-keyboard shortcuts**: with a Magic Keyboard or Smart Keyboard
  Folio attached, ⌘F focuses search, ⌘1–9 copy the first nine clips, and ⌘↩
  copies the selected clip (↑↓ already walk the list) — the macOS panel's
  keyboard-first flow now reaches iPad.
- A content-free **error log** ("Recent issues") in the Privacy Center on both
  macOS and iPhone/iPad: records operational failures — storage that wouldn't
  open, a sync that failed (macOS), a clip that couldn't load to copy or a
  backup that wouldn't restore (iOS) — with no clip text, a fixed in-memory
  cap, nothing persisted or uploaded, and a "Copy for support" button. Backed
  by a shared `DiagnosticLog`.

### Changed

- On iPad, the clip detail pane no longer stretches its action row and text
  edge-to-edge across a wide pane — it's capped to a readable column and
  centred, instead of reusing the iPhone sheet's full-width shape.

## [0.2.0] - 2026-06-28

### Added

- Shortcuts/Siri automation grew: the **Search Clips** intent now takes a
  **type filter** (Any / Text / Link / Code / Color / Image / Secret) and a
  **maximum results** count; a new **Ask Your Clipboard** intent answers a
  question grounded only in your history (on-device, secrets filtered out); and
  Search Clips, Copy Last URL, and Ask Your Clipboard are now offered as
  Siri/Spotlight app shortcuts (previously only Save Clipboard and Clear
  Sensitive were). The ask retrieval is shared with the in-app feature via a
  new `ClipboardQA` coordinator — no logic fork.
- Free taste of on-device AI: the first 25 text clips a free user copies get a
  real AI title (titles only — semantic search and OCR stay Pro). It is now
  surfaced where users can read it — the paywall's free column, the onboarding,
  and a one-time tappable nudge when it runs out — so the sample is a deliberate,
  enticing feature rather than a silent one.
- Settings → Pro shows how many clips Gancho is keeping for you.
- Keyboard shortcut cheat-sheet in the panel (press ⌘/ or the footer "?"):
  surfaces the power shortcuts the footer can't fit — ⌘P pin, ⌘S snippet,
  ⌥⏎ paste-plain, ⌘1-9 quick-paste.
- In-panel capture notice: when capture is paused (Private Mode), off (no
  clipboard access), or paused while screen sharing, the panel now says so —
  with a one-tap Resume / Fix — so a copy that doesn't appear reads as
  "paused", not "broken".
- Onboarding now points to the menu-bar home and offers a "Show in Dock"
  toggle, so a Dock-less app stays discoverable even if you forget the shortcut.
- A first-run welcome on iPhone/iPad explains Gancho's novel capture model up
  front — there's no background clipboard watching, so it walks through the
  three ways to save (the Paste button, the share sheet, and Shortcuts/Action
  Button) before dropping you on an empty list.
- macOS app icon — the Gancho hook mark.
- Release automation foundation: version-sync checks, a tagged GitHub Release
  workflow, macOS app ZIP packaging, artifact QA, and GitHub Pages deployment.

### Changed

- More generous free tier: 30-day / 2,000-item history (was 7-day / 500), and
  15 pins across 3 boards (was 10 pins, 1 board) — the free plan is the
  distribution engine, so it should feel complete on its own.
- The Library shows a live used/limit count next to Boards and Snippets for
  free users, and the Pro footer escalates (neutral → "almost full" → "limit
  reached"), so the upsell forewarns instead of ambushing at the ceiling.
- Retention settings now explain how the windows stack: a per-type limit
  overrides the global one, and a callout makes clear that detected secrets
  always follow the shorter "Sensitive items" limit — even when history is set
  to keep everything longer — so "Forever" never silently keeps a password.
- The "Never capture from these apps" denylist gains an "Add a running app…"
  picker (no need to know an app's bundle identifier) plus a format hint, so
  the feature is usable without hunting for bundle ids.
- The panel's Smart Paste menu now states the rewrites run on your Mac and
  nothing leaves the device — the reassurance lands right where a privacy-
  conscious user hesitates.
- The snippet editor now explains how snippets work up front: type the keyword
  in the panel to insert one, and add `{field}` placeholders to fill in before
  pasting (previously the `{field}` hint only appeared after you'd typed one).
- Plainer snippet wording: "Save as snippet" / "Move to history" replace the
  jargon "Promote to Library" / "Remove from Library" (and the demote action no
  longer wears a destructive red trash icon — it doesn't delete anything).
- The panel's no-results state now offers a "Clear filters" button when a type
  or board filter is narrowing the list, replacing a hint that wrongly told you
  to "press esc to clear the search" (esc hides the panel).
- On iPhone/iPad, search and filters now show a context-aware empty state —
  "No clips match …" when a search misses, or "No clips in this filter" with a
  Clear filters button — instead of the generic "Nothing captured yet" that
  appeared even mid-search.
- On iOS, Smart Paste actions sit one tap from the clip's Smart Actions section
  instead of inside a nested menu (Translate stays a submenu for its languages).
- Saving from the iOS share sheet now plays a success haptic when a clip lands —
  the sheet used to disappear with no confirmation that anything was captured.
- Accepting a board suggestion in the macOS peek now offers a one-tap Undo in
  the confirmation toast, so a mis-file is reversible without the board menu.
- Tapping an image clip on iOS opens it full screen with pinch- and
  double-tap-zoom (loading the full image, not the 340pt preview) — screenshots
  of small text are finally legible.
- The iOS keyboard's compact strip ends with a chevron that expands it to the
  full, searchable list — the control-bar toggle alone wasn't discoverable.
- The active filter and board pills now carry a checkmark and the "selected"
  accessibility trait, so the selection reads without relying on the accent
  colour alone (WCAG 1.4.1) and announces correctly in VoiceOver.
- Toasts that carry an action (e.g. Undo) now stay up long enough to read and
  reach the button instead of vanishing after the fire-and-forget 2.4s.
- "My Clipboard, Wrapped…" is now reachable from Settings, not just the
  menu-bar command, so the shareable stats card is actually discoverable.
- The iOS Recent Clips widget's empty state now says how to fill it ("Copy or
  share to Gancho") instead of a bare "Nothing yet".
- Distinct icon for "Smart paste" in the Intelligence list (it shared the
  "sparkles" glyph with "Smarter titles"), and the internal "Developer actions
  run" counter is now hidden from the release Privacy Center (DEBUG-only).
- Settings → Integrations now explains how to actually use the MCP server: a
  "Connect an agent" section with the CLI install + `claude mcp add` command,
  and a note that scope changes apply the next time `gancho mcp` starts —
  enabling the toggle alone never started a server.

### Fixed

- Data-loss warning: when the encrypted store can't open, Gancho now shows a
  prominent "History isn't being saved" banner (panel + iPhone/iPad history
  lists + Privacy Center) instead of silently running on a throwaway in-memory
  store and losing every clip on quit.
- On iOS, tapping Copy when a clip's content can't be loaded now says so
  ("Couldn't load this clip — try again") instead of silently leaving stale
  content on the pasteboard; a paused or failed sync gains a Retry button.
- On iPad, selecting a clip and then searching/filtering no longer leaves a
  ghost detail pane, and the history column shows an empty state when there's
  nothing to list.
- The Privacy Center's "Secrets masked" stat now counts detected sensitive
  clips (via a new `sensitiveCount()`) instead of a fragile match on the masked
  preview string, and it warns when storage is ephemeral (its counters would
  otherwise all read 0).
- The MCP access log shows relative timestamps ("3 hours ago") so yesterday's
  access is distinguishable from this minute's.
- "Add to board → New board…" from a clip now prompts for a name and files the
  clip into the board it creates, instead of silently making a board literally
  named "Board".
- Deleting a board now asks for confirmation first — the clips always stay in
  your history; only the board is removed.
- The iOS clip detail sheet now has a Done button — previously it could only be
  dismissed by dragging it down, with no visible affordance.
- The paywall and StoreKit test product copy no longer present iCloud sync as a
  shipped Pro benefit — it's marked "coming soon", and the Settings Pro note
  now separates what Pro unlocks today (unlimited history, pins, boards) from
  what arrives with launch (sync), so nobody upgrades expecting sync that isn't
  there yet.
- The direct-download paywall no longer dead-ends every license key on "That
  license key could not be activated" when the build ships without a signing
  key — it shows an honest "Pro is coming soon — purchases aren't open in this
  build yet" instead of a field that can never succeed.

## [0.1.0] - 2026-06-25

### Added

- Initial pre-release baseline for the privacy-first clipboard history system:
  macOS capture, encrypted local storage, FTS search, retention, paste-back,
  pins and boards, snippets, local MCP/CLI integration, and content-free
  telemetry boundaries.
- iPhone/iPad companion app with share, keyboard, widgets, App Intents,
  encrypted App Group storage access, and iCloud sync plumbing through
  `CKSyncEngine`.
- StoreKit entitlement plumbing and owner-gated launch surfaces for future
  public distribution.
- XcodeGen project, Swift 6 strict-concurrency package layout, localization,
  privacy, accessibility, and performance gates.
