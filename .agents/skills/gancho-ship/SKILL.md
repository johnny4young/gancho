---
name: gancho-ship
description: >
  Implement Gancho backlog tasks end to end: full code + architecture, unit and
  UI tests, commit only when green, update local shipped flags, continue to the
  next task. Use when the user says "implement the backlog", "next task",
  "work the backlog", "work the backlog", "continue with Gancho", "work on the
  backlog", "implement the next task", "ship the next task", or asks to build
  any pending Gancho feature or spike.
---

# gancho-ship — backlog implementation loop

You are implementing tasks from the **local** backlog of Gancho, a privacy-first
smart clipboard for macOS 26 / iOS 26. This skill is the working agreement;
follow it exactly. Built from the workflow that shipped vitrine
(`~/Personal/github/vitrine` — consult it for proven patterns: LocalizationTests,
release pipeline, XCUITest helpers, Settings, Sparkle/DMG scripts).

## Sources of truth

- `.planning/BACKLOG.md` — tasks, order, dependencies, acceptance criteria,
  state flags. Local only (git-ignored). Ticket IDs (`E1.1`, `S0.1`) exist ONLY
  here and in `.planning/` — never in committed text.
- `.planning/NOTES.md` — operational context, decisions log, gotchas.
- `.planning/notion-export/` — verbatim original definitions if more detail is
  ever needed.
- `AGENTS.md` + `docs/ARCHITECTURE.md` (committed) — engineering conventions
  and architecture decisions. They win over improvisation.

State lives ONLY in each ticket's header line (`- status: ... · shipped: ...`);
the dashboard table is order/metadata only and carries no state columns.
Canonical greps: `grep -n 'status: \`in-progress\`' .planning/BACKLOG.md`,
`grep -n 'shipped: false' .planning/BACKLOG.md`.

## The loop

0. **Reconcile on resume.** If any task is `in-progress`, check `git log`
   first: if its work is already committed and the gates pass, mark it
   `shipped` (with its hash) before doing anything else — never leave flags
   contradicting git history.
1. **Pick work.** Take the task the user named, or else the first `pending`
   task in implementation order whose dependencies are all `shipped`. Skip
   `blocked` tasks. Re-read its full definition + acceptance criteria.
2. **Flag it.** Set `status: in-progress` in `BACKLOG.md` BEFORE writing code.
   Flags are updated one task at a time, never in batch — if the session dies,
   the file must reflect reality (this is the crash-safe resume point).
3. **Implement fully.** Code + architecture decisions are yours to make within
   `docs/ARCHITECTURE.md` boundaries. No stubs left behind for the task's core.
   Follow TDD where natural: write the failing test from the acceptance
   criteria first.
4. **Gate (all must pass, in this order):**
   ```bash
   make format        # then make lint must be clean
   make lint
   make test          # Swift Testing package tests
   make build         # macOS app compiles
   make build-ios     # when iOS code was touched (needs -downloadPlatform iOS once)
   make test-ui       # when the UI-test target exists and UI was touched
   ```
   (`make test-ui` does not exist yet — the CI/UI-harness task creates the
   XCUITest target AND the Makefile target, including `.PHONY`.)
   Plus: new logic has unit tests; new UI has kebab-case accessibility ids
   (`history-panel`, `clip-row`) and UI tests once the XCUITest target exists;
   user-facing strings go through the String Catalog with en + es (inherit the
   LocalizationTests gate from vitrine `Tests/LocalizationTests.swift`).
5. **Commit only on green + high confidence.** High confidence = acceptance
   criteria demonstrably met (tests prove them), no known regression, docs
   updated. If confidence is low, keep iterating — do not commit "to save
   progress".
6. **Flag shipped.** Immediately after the commit: `status: shipped` +
   `shipped: true (YYYY-MM-DD, <hash>)` in the ticket header. Multi-commit
   tasks list hashes comma-separated (`abc1234, def5678`), main commit first.
   THEN move to the next task.
7. **If stuck, say so in the file.** A task that cannot advance (failed spike,
   external dependency, missing decision) gets `status: blocked` plus a
   one-line reason in its section; pick the next unblocked task. Never leave a
   stuck task sitting in `in-progress`.
8. **Repeat** until the user's requested scope is done or nothing is unblocked.

## Commits

- Conventional Commits, simplified, **English**, imperative:
  `feat: capture images from the pasteboard`, `fix: debounce rapid copies`,
  `test: cover expiry pruning`, `chore: bump toolchain`. Scope optional.
- Describe **functionality only**. Never ticket IDs, epic names, "backlog",
  "Notion", or internal codenames. Before committing, self-check the message:
  `grep -E '\b[ES][0-9]+\.[0-9]+\b'` on it must find nothing.
- **Never add AI co-authorship / generated-by trailers** (no `Co-Authored-By:
  Codex`, no watermarks). Repository + user policy.
- One commit per task (small follow-up `fix:`/`test:` commits are fine).
  Do not push unless the user asks.

## Execution model (token-lean — NO ultracode)

Do **NOT** use the Workflow tool or multi-agent fan-outs: the owner explicitly
ruled them out for this loop (token cost). Work inline and sequentially — one
task at a time, smallest diff that meets the acceptance criteria, then gate,
commit, flag, next.

- Subagents (Agent tool) are the exception, not the rhythm: at most one,
  read-only (e.g. an Explore digest of a large unfamiliar area), and only when
  reading it yourself would flood the main context. Never delegate the
  implementation itself.
- The `∥` / "Parallelizable" hints in the phase headers of `BACKLOG.md` describe
  task independence; under sequential execution they only inform pick order.
- Replace the old adversarial-review fan-out with a disciplined SELF-review of
  the fresh diff before the gate: each acceptance criterion provably covered
  by a test · Swift 6 isolation sound (nothing crosses an actor boundary
  unsafely) · privacy intact (sensitive-type veto before reads; no clipboard
  content in logs/telemetry) · docs updated · no internal IDs in anything
  committed.

## Hard rules (privacy & quality)

- Never store content carrying `org.nspasteboard.ConcealedType` /
  `TransientType` / `AutoGeneratedType`. The veto runs BEFORE reading content.
- No clipboard content in logs, telemetry, analytics, or error reports — ever.
  Telemetry sends metadata buckets only.
- `project.yml` is the source of truth; never hand-edit `Gancho.xcodeproj`;
  run `make project` after changing it.
- Swift 6 strict concurrency: app targets default `@MainActor`; the engine-room
  **modules of the `Packages/GanchoKit` package** (`GanchoKit`, `ClipboardCore`,
  `GanchoAI`, `GanchoDesign`) stay nonisolated + `Sendable`. They are targets
  of ONE SwiftPM package — do not create new top-level packages under
  `Packages/` without also extending the Makefile's `PACKAGE` wiring.
- Min macOS 26 / iOS 26; SDK-27 APIs behind `#available`; no beta SDKs locally.
- Storage is GRDB (SQLite) + FTS5; sync via `SyncEngine` boundary (CKSyncEngine
  impl); the core never imports CloudKit. No SwiftData.
- Document code well: `///` doc comments on every public symbol stating
  constraints and rationale (not narration); update `docs/ARCHITECTURE.md` when
  layering changes; all project documentation and committed prose are English unless the owner explicitly asks otherwise.

## Found work (bugs / improvements)

Fix opportunistic bugs and clear improvements immediately, without asking:
small ones fold into the current task's commit or get their own `fix:` commit;
larger ones become a fully-defined task in the backlog's "Discovered"
section. Either way, record them in `BACKLOG.md` with flags so nothing lives
only in one session's memory.

## Environment gotchas (from vitrine experience)

- The Makefile already auto-exports `DEVELOPER_DIR` when `xcode-select -p`
  points at CommandLineTools — the prefix is only needed when invoking
  `xcodebuild` DIRECTLY outside make (e.g. `xcodebuild -downloadPlatform iOS`).
- iOS builds need `xcodebuild -downloadPlatform iOS` once per machine.
- If text-rendering tests crash under parallel Swift Testing (CoreText is not
  thread-safe), serialize: `env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1`.
- CI runner must have Xcode 26+; if `macos-latest` lags, pin `macos-26`.
- UI tests on hosted runners: small virtual displays — make window-geometry
  tests self-skip with a printed reason (vitrine pattern).

## Definition of done (per task)

Acceptance criteria proven by tests · gates green · code documented · committed
clean (semantic, English, no internal refs, no AI trailers) · `BACKLOG.md`
flags updated · discovered work recorded · non-trivial operational decisions
and new gotchas appended to `.planning/NOTES.md`. The repo and the backlog must
be consistent at every commit boundary, so any interruption resumes cleanly
from the flags.
