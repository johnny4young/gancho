# Filtered panel refresh after store mutations

## Problem and expected behavior

A retention pass can delete a filtered result outside the first 50 recent clips.
The recent page then remains equal before and after the purge. Previously the
panel refreshed its results on that page's value change; its store-event
subscription refreshed scope counts only. The filtered row, selection and an
already-loaded benign text preview could remain in the headless composition even
though fresh store reads refused the deleted row.

A relevant store event must refresh the active panel scope independently of that
recent-page equality. It must invalidate pending result/preview reads, clear
loaded preview text, reconcile selection, and permit a still-valid unchanged
selection to reload its preview.

## Change

`PanelSearchModel.refreshAfterStoreChange(preview:)` invalidates existing requests
and the preview before asynchronous reads, then refreshes source-app options and
the active scope. The existing non-capture store-event subscriber calls it.
`PanelPreviewRequestKey` adds the handled store revision to the selected content
version so a valid selection can reload after an unrelated mutation too.

Capture events keep their existing recent-page refresh path. The change does not
alter retention rules, exports, regex matching, paste authorization, sync,
schema, dependency locks or visual styling.

## Reproduce without a personal app session

Base revision: `8a21be3514a1cd05d75e09d5a763be0118795dd2`.
Requirements: macOS, a full Xcode toolchain supporting Swift 6.2 or later, Python
3.9 or later, Git, and network access to the already-pinned dependencies. Run
serially under any host-wide build/test coordination used by your environment.
Do not install a beta SDK or launch an installed Gancho app for these checks.

From the repository root, use new output directories:

```sh
python3 scripts/test-panel-store-refresh.py \
  --baseline 8a21be3514a1cd05d75e09d5a763be0118795dd2 \
  --output /tmp/gancho-panel-before

python3 scripts/test-panel-store-refresh.py --output /tmp/gancho-panel-after
```

The baseline command intentionally exits nonzero: the inside-window control
passes, while the outside-window case fails the row/selection/preview assertions.
The baseline adapter copies that revision's production modules and models the
old recent-value callback; it does **not** execute the historical SwiftUI view.
The working-tree command calls the new production refresh method directly and
also runs the preview invalidation/reload-key tests. Neither command discovers
the other package tests or invokes real clipboard, Keychain, providers or GUI.

The runner creates an independent package with exact revisions from the selected
lockfile, verifies the resolved graph before building, uses one worker, and
retains stdout/stderr, argv, duration and exits in the owned output directory.
It does not inherit credentials or change the checkout. Synthetic stores use
fresh owned temporary directories and are removed by the fixtures. Do not upload
local raw logs without reviewing paths and content.

The two integration fixtures each seed 50 benign survivors plus one expiring
text clip, load a **persisted** selected snapshot, then purge with an injected
clock. One victim is within the recent page and one is outside. Both assert the
recent-page condition, real deletion and panel/preview cleanup. There are no
real-time sleeps or clipboard reads. The preview tests additionally check that
an already-started read cannot republish after invalidation and that a store
revision creates a new request for an unchanged selected item.

## Validation and limits

The local environment used Xcode 27.1 (27A9275), Swift 6.4 and macOS 27.0.1. Exact
before/after results and the published commit's CI status belong in the PR
description; a draft is not release qualification.

Run the canonical repository gates as well:

```sh
make format
make lint
make test
make build
```

The full test discovery includes OS-integration fixtures, including a synthetic
Keychain probe. Run those gates only on a disposable runner suitable for them;
the narrow script exists to keep local headless reproduction independent of
those capabilities. CI compiles the actual macOS shell and runs the package
suite; neither replaces native visual acceptance.

Still required on an isolated synthetic native runner: keep a filtered panel open
while the expiring match lies outside an unchanged recent page; verify row and
selection removal, preview clearing/reloading, valid-selection preservation,
and keyboard behavior. Collect app-owned renders there. No GUI or screenshot
claim follows from the headless test alone. The original regex execution-limit
observation is a separate design problem and is not changed by this repair.
