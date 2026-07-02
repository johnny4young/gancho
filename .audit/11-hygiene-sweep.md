# 11 — Hygiene sweep (small verifiable wins)

Scope: audit findings F-1.2 (Package.swift comment drift), F-7.3 (pre-push
hook), the 02-security denylist depth note, a CHANGELOG catch-up for this
branch, and the F-6.1 localization-sweep widening probe. Environment: Linux,
no Swift toolchain — shell work verified by execution here; Swift edits kept
to literals/comments/`#expect` lines only.

## 1. Denylist expansion — DONE

`Packages/GanchoKit/Sources/ClipboardCore/SourceAppDenylist.swift`
(`suggestedBundleIDs`).

Pre-check: grepped `Tests/ClipboardCoreTests/` for assertions on the set's
exact contents or count — none exist. `SensitiveContentTests.swift` only
calls `contains(_:)` on individual ids (`suggestedListPreloaded`,
`suggestionOverrides`, `denylistRoundTrip`), so growing the set breaks no
test. Two `contains` expectations for new entries were added to
`suggestedListPreloaded` in the same pass.

### Added (6), with confidence source per id

| Bundle id | App | Confidence source |
|---|---|---|
| `com.markmcguill.strongbox.mac` | Strongbox (macOS, App Store) | Id declared in the open-source Strongbox repo's Mac targets; widely referenced in clipboard-manager ignore lists. |
| `com.keepassium.ios` | KeePassium | macOS build is the universal-purchase Catalyst app; universal purchase requires the same bundle id as iOS, and `com.keepassium.ios` is the id in the open-source KeePassium repo. |
| `com.hicknhacksoftware.MacPass` | MacPass | Open source; id is in the project's Info.plist on GitHub. |
| `com.nordpass.macos` | NordPass desktop | Vendor's macOS bundle id as referenced in third-party ignore-list configurations. |
| `com.venmo.TouchFree` | Venmo | Venmo's long-standing iOS bundle id (ubiquitous in URL-scheme/bundle-id registries); iPhone apps run unchanged on Apple-silicon Macs under the same id. |
| `com.squareup.cash` | Cash App | Cash App's iOS bundle id (same registries); same iOS-on-Mac rationale. |

### Deferred — needs verification on a real install (do NOT guess)

- Keeper for Mac — `com.keepersecurity.keepermac` unconfirmed (desktop app is
  Electron; the actual id may be a different `com.keepersecurity.*` string).
- RoboForm for Mac — vendor is Siber Systems; no confident id
  (`com.siber.*`? `com.roboform.*`?).
- Zoho Vault — no confident macOS/desktop bundle id.
- Bank wrappers (Chase, Bank of America, Monzo, N26, Wise iOS variant) — iOS
  ids exist but weren't confidently recalled; verify with
  `osascript -e 'id of app "..."'` or `mdls -name kMDItemCFBundleIdentifier`
  on a machine that has them installed.

A wrong id is dead weight, not a security hole (the veto is allow-nothing-
extra), but the instruction was to prefer few verified ids over many guesses.

## 2. Package.swift header comment (F-1.2) — DONE

`Packages/GanchoKit/Package.swift:2-10`: "Four library products" → now
enumerates all seven libraries (GanchoKit, ClipboardCore, GanchoAI,
GanchoDesign, GanchoTelemetry, GanchoSync, GanchoMCP) plus the `gancho`
executable, with the same one-line role notes the manifest's inline comments
use. Comment-only; no manifest semantics touched.

## 3. CHANGELOG catch-up — DONE, gate verified

Added an `## [Unreleased]` block to `CHANGELOG.md` with Added / Changed /
Security subsections in the file's benefit-first voice, covering: 18 Dev
Actions (`9e23b1a`), CLI `boards`/`pin`/`unpin` (`17f80f5`),
exclude-sensitive-by-default exports + `--include-sensitive` (verified in
`6e78d0a`: macOS `SettingsView.swift:205`, iOS `GanchoiOSApp.swift:792`, CLI
`GanchoCLI.swift`), the CSV formula-injection guard (`'`-prefix for fields
starting `=`/`+`/`-`/`@`/tab/CR), the 8 new detector patterns (Slack webhook,
Google API, GCP service account, OpenAI, npm, Azure, Authorization/Bearer,
PGP), the launch backfill move (`8be004d`), the GRDB fork revision pin, and
this sweep's denylist additions.

Gate evidence (`./scripts/check-version-sync.sh` after the edit):

```
✓ project.yml MARKETING_VERSION 0.3.2 and build 5 are valid
✓ CHANGELOG.md top release matches 0.3.2
✓ Homebrew formula template matches 0.3.2
✓ Info.plist bundle versions expand from project.yml build settings
```

## 4. Pre-push hook (F-7.3) — DONE, dry-run verified

Added `scripts/githooks/pre-push` (executable, same `#!/bin/sh` + `set -e` +
`cd "$(git rev-parse --show-toplevel)"` style as `pre-commit`). Behavior:

- No `swift` on PATH → prints a skip note and exits 0. This gates **lint
  too**, deliberately: `make lint` runs `swift format lint …`, so running it
  unconditionally would hard-fail every Linux push — the opposite of the
  finding's intent. CI enforces both gates regardless.
- `swift` present → `make lint`, then `make test`, each with a pointed
  failure message (and a `--no-verify` escape hatch mentioned for tests).

Opt-in stands: hooks only run after `make hooks` sets
`core.hooksPath scripts/githooks` (verified: hooksPath is unset by default;
the existing `chmod +x scripts/githooks/*` in the recipe covers the new file,
so **no Makefile wiring change was needed** — only the `##` help text was
updated to mention pre-push).

Dry-run evidence (executed directly on this Linux box):

```
$ scripts/githooks/pre-push
pre-push: no Swift toolchain found — skipping lint+tests (CI still enforces them).
exit=0
```

With a stub `swift` on PATH (both commands succeed): runs `make lint` then
`make test`, exit 0. With a stub whose `swift test` fails: exit 1 with
"pre-push: tests failed — fix before pushing (or bypass once with
'git push --no-verify')." — all three paths observed.

## 5. Localization-sweep widening (F-6.1) — NOT APPLIED; gap found

Per instructions, the widened sweep was replicated outside the test first
(Python re, same semantics as NSRegularExpression here: `\s` spans newlines,
first capture group, prose = contains a space, skip `\(` interpolations,
same per-bundle catalog mapping as `LocalizationTests.swift:117-133`).

Proposed new patterns, in the test's existing no-word-boundary style:

```
(?:Button|Toggle|Menu|Section)\(\s*"([^"\\]+)"
\.(?:navigationTitle|alert|confirmationDialog)\(\s*"([^"\\]+)"
```

Result: **86 prose literals matched; 1 missing from its required catalog** —
so widening the test today would turn CI red, and the test was left
untouched.

### Missing literal (the follow-up work)

| File | Literal | Missing from |
|---|---|---|
| `Apps/GanchoMac/PaywallView.swift:61` | `Get Gancho Pro` | `Apps/GanchoMac/Localizable.xcstrings` (absent from every catalog) |

Context: `ActionButton("Get Gancho Pro", systemImage: "cart.fill", …)` on the
direct-download paywall (`#if GANCHO_DIRECT_DOWNLOAD`, shown when
`LicenseSigningKey.isConfigured`). This is a real user-facing gap: the buy
button ships English-only in the es locale. Fixing it needs an en+es catalog
entry (bilingual round-trip → wants Xcode), and both `PaywallView.swift` and
the catalogs are owned by other agents in this audit — out of scope here.

Note for whoever lands the fix: a `\b`-anchored variant
(`\b(?:Button|Toggle|Menu|Section)\(`) *passes* today (10 literals, all
present) — but only because it skips wrapper components like `ActionButton`,
which is exactly where the one real gap lives (76 of the 86 matches come via
wrappers and are all correctly catalogued). Prefer the unanchored patterns +
the catalog fix over the anchored patterns that would grandfather the bug.

Follow-up sequence: (1) add `Get Gancho Pro` (en+es) to
`Apps/GanchoMac/Localizable.xcstrings`; (2) add the two unanchored regexes to
the `regexes` array at `LocalizationTests.swift:136-145`; (3) `make test` on
macOS.

## Files touched by this sweep

- `Packages/GanchoKit/Sources/ClipboardCore/SourceAppDenylist.swift`
- `Packages/GanchoKit/Tests/ClipboardCoreTests/SensitiveContentTests.swift`
- `Packages/GanchoKit/Package.swift` (header comment only)
- `CHANGELOG.md`
- `scripts/githooks/pre-push` (new, executable)
- `Makefile` (hooks help text only)
- `.audit/11-hygiene-sweep.md` (this file)

Not compile-verified (no Swift toolchain on this box): the two Swift file
edits and the manifest comment. All are literals/comments/`#expect` lines in
existing style, ≤100-char lines per `.swift-format`.
