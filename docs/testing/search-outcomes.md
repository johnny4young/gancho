# Search outcomes without app services

History must distinguish a completed search with no matches from an invalid
pattern, failed read, cancelled request or provider-reported timeout. Previously
the store adapters used `try?` plus an empty array, so the panel marked a failed
read as current and rendered its ordinary no-results state.

The change preserves outcomes through the shared list core and both platform
models. AppModel and HistoryStoreSource call the same narrow throwing-store
adapter. Existing nonthrowing callers remain compatible; the panel/history
loading paths explicitly consume the typed result. Recent/board browse methods
retain their existing fallback behavior and are outside this search repair.

## Reproduce before and after

Use the PR branch on macOS with stable Xcode selected through `DEVELOPER_DIR`.
The observed toolchain was Xcode 27.1 (27A9275), Swift 6.4, macOS 27.0.1 arm64.
The project still targets macOS 15.4 and iOS 26; local compilation on a newer OS
does not qualify those minimum targets.

Run serially with fresh output directories outside the checkout:

```sh
python3 scripts/test-search-outcomes.py \
  --revision 8a21be3514a1cd05d75e09d5a763be0118795dd2 \
  --output /tmp/gancho-search-before
python3 scripts/test-search-outcomes.py \
  --output /tmp/gancho-search-after --snapshots
make format
make lint
make test
```

The baseline command intentionally exits nonzero. In
`failedAppStoreReadMustNotBecomeCurrentEmptyResults`, the injected store throws
the existing invalid-pattern error, but the baseline panel reports
`hasCurrentResults == true`. The successful-empty control must pass. Inspect
`commands.json` and the test logs: a compile failure or timeout is not the
expected regression. The same two adapter-regression tests run after the fix.

Default extraction uses exact `HEAD` source bytes. `--revision` selects another
local commit; `--working-tree` explicitly permits testing uncommitted source,
recording that fact and the exact source SHA-256 map. No checkout is switched or
reset. Fixture/oracle files come from the branch containing this reproduction
script, while production source comes from the selected revision.

The independent package uses these existing exact revisions:

- GRDB: `d036a07fd43b5302443f2c2c0e0e3ca84f8b7ebf`.
- SQLCipher: `39f212458aeb88e33bdac2200a793a3f0d55d32b`.
- Sauce: `1fce89ccc9cbb091022c17ef8f9939901d4e951a`.

Normal preparation resolves only these known URLs/revisions. An optional
`--offline-cache` accepts a prior three-pin fixture scratch directory, verifies
its source revisions and lock, and copies its checkouts/repositories/artifacts
into the new output. It never borrows a running server or mutates that cache.
Canonical package and Xcode locks remain unchanged.

## What runs

- Selected baseline Core/Panel/History tests plus the new outcome/reader tests.
- The **actual** `AppModel+PanelSearchSource.swift` file compiled against a
  minimal AppModel shim containing only the fields the adapter needs. Its store
  is synthetic and injectable. This executes the extension's mapping and
  milestone hook, not the real AppModel initializer or its services. Normal app
  builds must also verify the extension against the real composition type.
- The actual iOS `HistoryStoreSource.swift` with a new owned temporary GRDB
  store. An invalid pattern exercises the existing real store error; closing
  only that store exercises a failed read after a successful empty search.
  Running this platform-neutral adapter on macOS is not an iOS app execution.
- With `--snapshots`, the shared passive `SearchFailureNotice` renders EN/ES,
  light/dark, four outcomes and two widths (32 PNGs). A tiny owned bundle carries
  copies of the app catalog translations. Its executable renders directly with
  an owned NSHostingView: no app delegate, app event loop or composition root.
  One never-ordered non-key window supplies AppKit layout; activation is
  prohibited. The fixture captures only its own view drawing and sends each
  retry button's target/action locally, without global input or accessibility
  access. Invalid patterns have no retry button. `controls.json` records all
  32 cases, button/callback counts and invisible/non-key window assertions.
  ImageRenderer alone cannot capture these native buttons and must not be
  treated as complete control evidence.

The script creates a new package and explicit HOME/TMPDIR/cache/config/security
directories, bounds each owned process group, and stores argv, environment
allowlist, PID, exit code, duration and source hashes. Temporary databases and
fixture values are synthetic. No real clipboard/history, Keychain, account,
StoreKit, Spotlight, global shortcut, device, simulator, capture or accessibility
permission is used. HOME alone is not treated as an OS-service sandbox: those
services are absent from the selected code path.

## Acceptance and limits

The required distinctions are success with items, successful empty results,
invalid pattern, read failure, cancellation and explicitly reported timeout.
Task cancellation is checked before and after the provider; old replies cannot
replace a newer request or clear its loading indicator. Pending reads show a
loading state rather than claim zero matches. Failed main queries do not probe
alternatives, and failed alternative probes are omitted rather than counted as
zero results. The panel's paste resolver returns after one terminal failed read
instead of retrying forever or treating old rows as current.

The timeout enum case is a delivery contract for a provider that explicitly
reports it. **This change adds no regex timer or execution limit.** It changes
no regex semantics, dependency, retention, export, storage schema or capture
permission. No raw store error, query or clipboard content appears in the
failure notice or new telemetry/logging.

Cancellation prevents a returned result from being published after the request
was cancelled. It does not preempt a provider that never returns; in particular,
Foundation regex matching is not made interruptible by this UI contract.

## Observed local validation

At the recorded baseline, all 91 selected model tests passed and the two common
adapter cases produced one pass plus the expected failed-read/current-results
assertion. With the repair, 113 selected model/reader tests and five actual
adapter-source tests passed, with zero selected skips. Parameterized cases
exercise all four terminal errors as separate invocations.

The native component fixture captured 32 combinations and invoked 24 local
retry actions exactly once each. The eight invalid-pattern combinations had no
retry button. Every window stayed invisible and non-key. Human review covered
both languages/themes and the narrow Spanish layout. These are component and
local target/action checks, not a claim of complete app interaction coverage.

The CI job also runs the adapter reproduction without `--snapshots`, so its
selected functional regressions require no GUI or app services. Its explicit
child environment honors the job's pinned `DEVELOPER_DIR`. On failure, only
synthetic fixture logs, command records and source hashes are retained.

Component PNGs qualify the notice's local macOS rendering, including narrow
layout and Spanish wrapping. They do not qualify iPhone/iPad native rendering,
VoiceOver/keyboard journeys, real-window focus, or complete panel interactions.
Validate those on a disposable synthetic native runner; never start the real
AppModel on an active user desktop merely to obtain screenshots. Do not enable
Developer mode or grant new capture/accessibility permissions for this lane.

`make test` includes broader OS-integrated fixtures than this safe lane. The
published-head CI must run canonical formatting/lint/package tests and app
builds; a draft PR or passing component render alone is not merge readiness.
Keep observed test counts, skips, visual evidence and remaining native
acceptance in the PR description.
