# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed

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
