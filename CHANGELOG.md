# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
