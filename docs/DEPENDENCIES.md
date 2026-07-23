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

Version 3.0.1 is the current baseline. Its Swift 6 implementation replaced the
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
