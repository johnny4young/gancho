# Search outcomes without app services

History must tell a completed search with no matches apart from an invalid
pattern or a failed read. The store adapters used to turn any error into an
empty array, so the panel showed its ordinary no-results state for a search
that never ran.

Ranked search now returns a typed outcome through the shared list core into
`PanelSearchModel` and `HistoryListViewModel`:

- **Success**, including a successful empty result.
- **Invalid regular expression**: a notice with no retry button.
- **Read failure**: a notice with a retry button. A `CancellationError` thrown
  by a store whose caller was not cancelled also counts as a failed read.
- **Cancelled**: the caller's task was cancelled. Nothing is published; the
  previous rows stay on screen and no notice appears.

Failed main queries do not probe alternatives, and a failed alternative is
omitted rather than counted as zero matches. The paste resolver stops after
one failed read. Recent and board browsing keep their existing fallback.
This adds no regex timer or execution limit.

## Local reproduction

`scripts/test-search-outcomes.py` is a local tool, not a CI gate. It builds an
independent package from the GanchoKit sources and the real
`AppModel+PanelSearchSource.swift` (against a minimal `AppModel` shim) and
`HistoryStoreSource.swift` (against a temporary GRDB store). No app
composition root, clipboard, Keychain or other OS service runs.

Run serially, with fresh output directories outside the checkout:

```sh
python3 scripts/test-search-outcomes.py \
  --revision 8a21be3514a1cd05d75e09d5a763be0118795dd2 \
  --output /tmp/gancho-search-before
python3 scripts/test-search-outcomes.py \
  --output /tmp/gancho-search-after --snapshots
```

The baseline run is expected to fail
`failedAppStoreReadMustNotBecomeCurrentEmptyResults`: the injected store throws
an invalid-pattern error and the old panel reports `hasCurrentResults == true`.
A compile failure is not the expected regression; check `commands.json` and the
logs. `--working-tree` tests uncommitted source, and `--offline-cache` reuses a
prior fixture scratch directory with the same dependency pins.

`--snapshots` renders `SearchFailureNotice` in EN/ES, light/dark and two widths
(16 PNGs) in a never-ordered, non-key window, and calls each retry button's
action directly. These are component checks only: they do not cover iPhone or
iPad layout, VoiceOver, keyboard focus or full panel journeys.
