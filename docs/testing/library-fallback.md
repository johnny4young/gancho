# Library RAM request semantics

When the durable store cannot open, the app uses `InMemoryClipboardStore` and
`fullStore == nil`. The Library must still honor its supported all-clips and
pinned scopes, kind chips, metadata search, sort direction and offset window.
This repair changes only that fallback adapter. SQL queries, persistence,
retention, quotas, capture, board writes and user-facing strings are unchanged.

The old adapter filtered an already truncated raw page. A kind or pin absent
from the first 100 raw rows produced an empty page and false EOF, even when
older matching rows remained. Its text-search fallback also omitted pinned-only
filtering. The fix reads one coherent RAM **metadata** snapshot, applies the
supported request predicates and stable ordering, then slices offset/limit.
Zero limits and unsupported board/saved-filter scopes return without a read.
No clip body is loaded. This adds no caching, new store facet, global app service,
or automatic recovery/migration from RAM to disk.

## Reproduce before and after

Base: `ad8d2c6aa8879c59d9f5e90de011e822df8d8179` (v0.10.2/build21), which includes
PR239, PR240 and the boards/Library changes. Use fresh output directories outside
the checkout, serially, on macOS with Swift 6.2+ and the installed Xcode toolchain:

```sh
python3 scripts/test-library-fallback.py \
  --revision ad8d2c6aa8879c59d9f5e90de011e822df8d8179 \
  --mode regressions --output /tmp/gancho-library-before
python3 scripts/test-library-fallback.py --output /tmp/gancho-library-after
```

The baseline command intentionally exits nonzero: three of five regression cases
fail (four assertions). A build failure or zero discovered tests is not the
expected failure. The two-row pinned search returns both rows in RAM versus one
in the GRDB control. A 130-row fixture places 30 links and an old pin behind the
first raw page: RAM returns zero and EOF while all rows remain stored. The
unfiltered RAM paging and small-scope controls pass.

The after command defaults to the checked-out commit. During local development,
use `--working-tree` to label uncommitted production inputs explicitly. Fixtures
always come from the checkout containing the script, so both commands use the
same assertions. Production modules and the real `AppModel+Library.swift`
extension are extracted from the selected revision into an independent package.
The replacement AppModel contains only the store fields and a no-op toast shape;
it does not construct the actual application composition root.

The script resolves only the three required revisions selected from the
canonical lock: GRDB `d036a07fd43b5302443f2c2c0e0e3ca84f8b7ebf`, SQLCipher
`39f212458aeb88e33bdac2200a793a3f0d55d32b`, Sauce
`1fce89ccc9cbb091022c17ef8f9939901d4e951a`. An optional `--offline-cache` points
to an existing scratch directory whose checkout pins are verified before copying
sources/artifacts. Other canonical dependency targets are not required by this
isolated package. No canonical lock is edited.

## Assertions and boundaries

The five original regressions/controls are supplemented by:

- 252 paired RAM/GRDB page comparisons: all/pinned, all/links/code, both sort
  directions, seven offsets and limits 0/1/50, including empty/end windows.
- Capture-time ties resolved by ID, using an independent fixture-index oracle.
- Combined case/accent-folded text, kind and pinned predicates.
- No read for zero limits or unsupported scopes; one metadata snapshot and zero
  body reads for a supported page.
- Recopy/new-capture paging reconciliation and real EOF without duplicate IDs.
- Explicit transfer of owned fixtures from RAM to GRDB: count, IDs, content and
  request parity. This tests a fixture transition, not a production hot-swap or
  new recovery feature. The SQL control uses temporary in-memory SQLite and
  does not claim disk durability.
- Recorded metadata-adapter timings at 100/1,000/10,000 rows with a preloaded
  synthetic provider, All/Links and five repetitions per size/kind. First-store-call/warm labels and
  overhead are retained. There is no latency threshold and no native render,
  launch, heap-leak or full-app performance claim.

The safe existing selection retains the previous Library/boards/retention,
History and terminal-search tests, plus the integrated PR239 model cases.
One preferences round-trip case is explicitly omitted. This package is a partial
selection, not canonical `make test`, full app coverage or native UI acceptance.

All stores, file outputs, HOME/TMP/cache/config/security paths are owned by the
fresh output. No real clipboard/history, Keychain, StoreKit, Spotlight, global
shortcut, account provider, simulator/device or GUI is used. Database operations
run against owned fixtures only; the suite never damages an installed store to
force fallback. Test data contains no real credentials or user content.

The runner records source hashes, exact commands, environment allowlists, PIDs,
exit codes, timeouts and durations. It uses one build worker and terminates only
fresh owned process groups on timeout. Inspect `commands.json`, `fixture.json`,
`logs/` and the counts/booleans/timing JSON files under `fixtures/`. CI runs this
adapter regression in addition to its existing canonical gates; failure artifacts
contain only this isolated harness's logs and metadata.

Before merge, review exact-head CI, targeted native Library presentation on an
isolated runner, and the snapshot cost for the expected RAM history sizes. The
extra full metadata scan is the correctness tradeoff; a cache or broader store
refactor requires separate evidence. No merge/deployment follows from a draft.

## Recorded local validation

Xcode27.1 (27A9275), Swift6.4, macOS27.0.1 (26A434), arm64 Mac15,6,
11 CPUs/18GiB. Compilation used one worker. Required pins above were reused from
an owned cache; no system toolchain or security setting was changed.

| Check | Base | Repaired |
| --- | --- | --- |
| Original fallback regression/control suite | 2 passed /3 failed | 5 passed |
| Existing safe tests | Prior selection102 passed | 106 passed, including4 integrated PR239 cases |
| Boundary/search/read/mutation/fixture-transfer cases | Not part of the baseline failure oracle | 5 passed |
| Isolated snapshot observation | Not a comparable correct implementation | 1 passed,30 recorded samples |
| Scoped Swift formatting/lint | Base unchanged | Passed |
| Strict SwiftLint on changed Swift files | Base unchanged | Passed,4 files/zero violations |
| Python/YAML syntax and diff whitespace | Base unchanged | Passed |

Reported after total:117 tests. Parameterized invocations and252 matrix page
pairs are not added to that framework count. The broader canonical/native gates
were not executed locally; follow the published commit's CI and retain the
specific native acceptance limits above.

Preloaded-provider Debug observations, one isolated process, five calls per cell:

| Rows | All first /warm median | Links first /warm median |
| --- | --- | --- |
| 100 | 0.560 /0.437ms | 0.168 /0.139ms |
| 1,000 | 5.254 /5.478ms | 1.605 /1.621ms |
| 10,000 | 42.952 /42.322ms | 19.295 /19.208ms |

The full metadata snapshot/filter/sort has an observable cost at larger histories.
These include actor/adapter overhead and are not Release, native rendering,
user-journey or cold-launch measurements. Five calls provide limited variability
information; no absolute budget or performance improvement is claimed. Keep
Release/UI profiling at expected history sizes open before merge rather than
silently caching mutable store state.
