# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Free taste of on-device AI: the first 25 text clips a free user copies get a
  real AI title (titles only — semantic search and OCR stay Pro), so new users
  see the on-device intelligence on their own clips before deciding.
- macOS app icon — the Gancho hook mark.
- Release automation foundation: version-sync checks, a tagged GitHub Release
  workflow, macOS app ZIP packaging, artifact QA, and GitHub Pages deployment.

### Changed

- More generous free tier: 30-day / 2,000-item history (was 7-day / 500), and
  15 pins across 3 boards (was 10 pins, 1 board) — the free plan is the
  distribution engine, so it should feel complete on its own.

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
