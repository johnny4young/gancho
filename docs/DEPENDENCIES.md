# Dependency management

How Gancho's dependencies stay current without ever letting automation touch
the storage, encryption, signing, or updater path.

## The three lanes

| Lane | Covers | Mechanism |
| --- | --- | --- |
| Dependabot | GitHub Actions; safe SwiftPM packages | Weekly grouped PRs (`.github/dependabot.yml`); security advisories arrive separately, ungrouped |
| Upstream canary | GRDB, SQLCipher.swift, Sparkle, Sauce, KeyboardShortcuts | Weekly workflow (`upstream-canary.yml`) compares `scripts/upstream-pins.env` against the latest upstream releases and opens ONE deduplicated issue on drift |
| Hand-rebased fork | `johnny4young/GRDB.swift` (branch `sqlcipher-7.11.0`) | This runbook only — excluded from Dependabot by name |

**Nothing auto-merges.** The repository has no auto-merge workflow, and the
encrypted store (GRDB fork + SQLCipher.swift), the signing pipeline, and the
Sparkle updater are excluded from Dependabot entirely. A canary report is a
prompt for a human, never a change.

## Pins (`scripts/upstream-pins.env`)

One file records the upstream versions Gancho builds against. The canary
cross-checks the pins that have a tracked source of truth — `SPARKLE` against
`scripts/fetch-sparkle.sh`, `SAUCE` and `SQLCIPHER` against
`Packages/GanchoKit/Package.resolved` — so a pin cannot silently drift from
what the repo actually builds. Update a pin only inside the PR that adopts the
new version.

## Runbook: rebasing the GRDB fork

The fork exists because SQLCipher support requires trait edits GRDB does not
ship. Its branch name encodes the upstream base (`sqlcipher-7.11.0`).

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
4. **Point Gancho at it.** Update the branch name in
   `Packages/GanchoKit/Package.swift`, run a full resolve, and update
   `GRDB`/`SQLCIPHER` in `scripts/upstream-pins.env`.
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

## KeyboardShortcuts 3

When the canary reports KeyboardShortcuts 3.x: migrate it in ITS OWN PR, with
tests that prove recorded shortcuts persist across the upgrade and that the
conflict-detection behavior (`ShortcutConflictsTests`) is unchanged. Its pin
is maintained by hand (the project-level resolved file is generated).

## Sparkle

Sparkle is not an SPM dependency: `scripts/fetch-sparkle.sh` downloads the
release tarball and verifies a pinned SHA-256. Updating = new version + new
checksum in that script (the canary's `SPARKLE` pin cross-checks it), then the
signed direct-download DMG must build with re-signed helpers and pass
`codesign --verify --deep --strict` before merging.
