# Dependency management

How Gancho's dependencies stay current without ever letting automation touch
the storage, encryption, signing, or updater path.

## The three lanes

| Lane | Covers | Mechanism |
| --- | --- | --- |
| Dependabot | GitHub Actions; safe SwiftPM packages | Weekly grouped PRs (`.github/dependabot.yml`); security advisories arrive separately, ungrouped |
| Upstream canary | GRDB, SQLCipher.swift, Sparkle, Sauce, KeyboardShortcuts | Weekly workflow (`upstream-canary.yml`) compares `scripts/upstream-pins.env` against the latest upstream releases and opens ONE deduplicated issue on drift |
| Hand-rebased fork | `johnny4young/GRDB.swift` (branch `sqlcipher-7.11.1`) | This runbook only — excluded from Dependabot by name |

**Nothing auto-merges.** The repository has no auto-merge workflow, and the
encrypted store (GRDB fork + SQLCipher.swift), the signing pipeline, and the
Sparkle updater are excluded from Dependabot entirely. A canary report is a
prompt for a human, never a change.

## Pins (`scripts/upstream-pins.env`)

One file records the upstream versions Gancho builds against. The canary
cross-checks the pins that have a tracked source of truth — `SPARKLE` against
`scripts/fetch-sparkle.sh`, `SAUCE` and `SQLCIPHER` against the package lock,
and `KEYBOARDSHORTCUTS` against the app lock — so a pin cannot silently drift
from what the repo actually builds. Update a pin only inside the PR that adopts
the new version.

## Reproducible resolution

Gancho has two dependency roots and therefore two canonical locks:

- `Packages/GanchoKit/Package.resolved` records the standalone package graph
  used by `swift test` and the CLI build.
- `Dependencies/Package.resolved` records the app-wide Xcode graph: every
  GanchoKit dependency plus the project-level `KeyboardShortcuts` package.

The generated `Gancho.xcodeproj` remains ignored. XcodeGen's post-generation
hook copies the app lock to the workspace location Xcode expects; never edit
that generated copy. `make dependency-check` proves shared dependencies resolve
to the same revisions in both graphs. Normal SwiftPM and Xcode gates disable
automatic resolution, so an incompatible manifest fails instead of silently
rewriting a lock.

After deliberately changing a package requirement, run
`make resolve-dependencies`. Review both lock diffs and the manifest change,
run the matrix below, and commit them together. Do not run a resolver and then
commit whichever generated lock happened to change. A Dependabot SwiftPM PR
will initially fail the lock-coherence gate until its package update is also
resolved into the app-wide lock with this command.

## Runbook: rebasing the GRDB fork

The fork exists because SQLCipher support requires trait edits GRDB does not
ship. Its branch name encodes the upstream base (`sqlcipher-7.11.1`).

1. **Fetch + branch.** In a clone of `johnny4young/GRDB.swift`:
   `git remote add upstream https://github.com/groue/GRDB.swift` →
   `git fetch upstream --tags` → create `sqlcipher-<newTag>` from the new
   upstream tag.
2. **Re-apply the patch.** Cherry-pick the fork's patch commits (everything on
   the old branch after the old base tag). The patch is deliberately minimal:
   `Package.swift` gains the `SQLCipher.swift` dependency and the `SQLCipher`
   define; `GRDBSQLite` (system SQLite) is removed in favor of
   `GRDBSQLCipher`. Resolve `SQLCipher.swift` to its current release and record
   it — this is the `SQLCIPHER` pin.
3. **Diff the patch.** `git diff <newTag>..sqlcipher-<newTag>` must show ONLY
   the SQLCipher enablement. Anything else means an upstream conflict was
   resolved wrong — stop and re-do the cherry-pick.
4. **Point Gancho at it.** Update the exact fork revision in
   `Packages/GanchoKit/Package.swift`, run `make resolve-dependencies`, and
   update `GRDB`/`SQLCIPHER` in `scripts/upstream-pins.env`.
5. **Test matrix (all must pass before the PR):**
   - `make test` (package suite; includes `GRDBEncryptionTests`,
     `GRDBRawKeyAdoptionTests`, migration + durability suites);
   - `make build && make build-ios` (both shells compile);
   - `GANCHO_PERF=1 make bench` (FTS + semantic budgets at scale);
   - a real-store migration check on a device day: the signed build must open
     the existing encrypted store (see `docs/SECURITY-MODEL.md`).
6. **Rollback.** The old branch is never deleted. Reverting the Gancho-side
   pin commit (branch name + pins) is a complete rollback; no store migration
   is implied by a GRDB rebase alone. If a rebase DID migrate the schema,
   restore from the pre-update backup instead of downgrading in place.

## KeyboardShortcuts

KeyboardShortcuts is an app-level macOS dependency, not part of GanchoKit.
`Apps/GanchoMac/GlobalShortcuts.swift` owns the stable shortcut names and
initial panel binding; changing those raw names would orphan existing user
preferences. Feature controllers register handlers, while Settings and
onboarding use the package's recorder UI.

Version 3.1.0 is the current baseline. The 3.0 Swift 6 implementation replaced the
registration engine and renamed `Name(default:)` to `Name(initial:)` without
changing Gancho's stored Carbon key-code/modifier representation. Signed UI
coverage must prove that an existing shortcut restores and has an active
registration without rewriting the maintainer's preference.

Treat every future major update as its own PR. Review the complete upstream API
and registration-lifecycle delta, update `project.yml`, refresh the app lock
with `make resolve-dependencies`, update `KEYBOARDSHORTCUTS` in
`scripts/upstream-pins.env`, and run package, macOS/iOS build, conflict, and
signed shortcut-registration gates before merge.

## Sparkle

Sparkle is not an SPM dependency: `scripts/fetch-sparkle.sh` downloads the
release tarball and verifies a pinned SHA-256. Updating = new version + new
checksum in that script (the canary's `SPARKLE` pin cross-checks it), then the
signed direct-download DMG must build with re-signed helpers and pass
`codesign --verify --deep --strict` before merging.

## October 2026 maintenance review

The adopted stable releases match the October 5 canary. This is a dependency
update, not a GRDB fork rebase or an application schema migration.

- **SQLCipher.swift 4.17.0 → 4.19.0.** The existing GRDB fork requirement
  (`from: "4.17.0"`) already admits this version. The annotated release tag
  peels to `39f212458aeb88e33bdac2200a793a3f0d55d32b`; both canonical locks
  use that commit. Its Swift 6.0 / macOS 10.13 / iOS 12 floors fit Gancho.
  [Zetetic's advisory](https://www.zetetic.net/blog/2026/09/08/sqlcipher-4.19.0-release/)
  describes two low-risk issues in older versions: unquoted attached schema
  aliases in `sqlcipher_export` and invalid `hexkey` URI input. Gancho uses a
  fixed `encrypted` alias and `usePassphrase`, not a `hexkey` URI. The reviewed
  paths do not establish exploitability in Gancho; the update still brings
  upstream error-handling and migration fixes. The encryption migration test
  now covers an apostrophe in the directory name and reopening after export.
- **KeyboardShortcuts 3.0.1 → 3.1.0.** The existing app requirement already
  admits it. The annotated tag peels to
  `772133d9dbe800fdac0473226822994c5c162c58`. Swift 6.2 and macOS 10.15 remain
  compatible with the supported build toolchain and deployment floor.
  [The upstream delta](https://github.com/sindresorhus/KeyboardShortcuts/compare/3.0.1...3.1.0)
  changes menu tracking, synthesized Fn handling, and recorder pause/resume;
  it does not require changing Gancho's stable names or stored key codes.
- **Sparkle 2.9.6 → 2.10.0.**
  [The release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
  raises its macOS floor to 12, below Gancho's 15.4, and fixes update progress,
  delta handling, and signed-feed diagnostics. The tarball checksum is the
  official release asset's SHA-256. The fetch cache now records both version
  and checksum; an old unmarked framework can no longer silently survive a
  pin update. Offline fixture tests cover reuse, invalidation, missing tools,
  forced downloads, and preservation after failed verification.

### Verification and merge gates

The lock revisions above were checked against the upstream annotated tags and
immutable commit manifests; they were not regenerated locally with Xcode.
Manifest requirements and origin hashes are unchanged. CI must consume both
locks with automatic resolution disabled and pass dependency coherence,
formatting, lint, package encryption/raw-key/migration/durability tests,
StoreKit tests, and both app builds. A local fixture test is not evidence that
the real Sparkle binary was downloaded or signed correctly.

Before merge, also record the results that ordinary unsigned PR CI cannot
supply:

- `GANCHO_PERF=1 make bench` for storage/search budgets.
- A signed build reopening a backed-up, existing store produced by the old
  SQLCipher version, checking clips and binary payloads; fresh test databases
  created and reopened with the new version do not prove cross-version upgrade.
- A signed direct-download DMG with re-signed helpers and
  `codesign --verify --deep --strict`, plus the signed updater smoke check.
- Signed shortcut restoration without preference changes, re-recording the
  existing shortcut, cancelling/switching recorders, conflict rejection, and
  function-key activation with a menu open. Check the lowest supported macOS
  and a current supported system. Package conflict tests do not exercise the
  global registration or AppKit recorder lifecycle.

Keep this work in draft until those gates have evidence. Do not close the
upstream canary issue merely because its original body mentions older releases.
