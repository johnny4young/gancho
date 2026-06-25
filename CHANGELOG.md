# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Release automation foundation: version-sync checks, a tagged GitHub Release
  workflow, macOS app ZIP packaging, artifact QA, and GitHub Pages deployment.

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
