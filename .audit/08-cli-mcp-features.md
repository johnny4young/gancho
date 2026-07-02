# 08 — CLI + MCP integration-surface features

Scope: expose boards/pins to the terminal and to local AI agents, reusing
existing store APIs only. No new store/protocol methods, no schema changes.

## What was added

### CLI (`Packages/GanchoKit/Sources/gancho/GanchoCLI.swift`)

Three new verbs, all following the existing dispatch/Options/openStore
patterns and printing to stdout like the other commands:

- `gancho boards [--json]` — lists boards via the existing
  `GRDBClipboardStore.pinboards()` (public, `Pinboards.swift`). Human format
  is tab-separated `id \t sfSymbol \t name` (mirrors `search`); `--json`
  emits a pretty-printed array via a new private `CLIBoard` wire struct
  (mirrors `CLIClip`).
- `gancho pin <clip-id>` / `gancho unpin <clip-id>` — one shared
  `runSetPinned(_:pinned:)` calling the existing public
  `GRDBClipboardStore.setPinned(id:_:)`. Both methods were verified reachable
  directly on the concrete store the CLI holds (`Pinboards.swift` defines
  `setPinned`/`pinboards` as public extension methods; `item(id:)` is public
  in `MCPAccessStore.swift`), so no protocol dance was needed.
- `printUsage()` and the file's header doc comment were updated with the new
  verbs.

Privacy guard: `pin`/`unpin` first fetch the clip with `store.item(id:)` and
refuse (`exit(1)`, stderr message) when `isSensitive` — pinning would exempt
a detector-flagged secret from short-expiry retention, so the CLI mirrors the
MCP runner's sensitive veto. Unknown ids and malformed UUIDs follow the
existing `copy` error/exit-code conventions (usage errors exit 2, lookup
failures exit 1).

Logging: like `search`/`copy`/`save`/`export`, these are the user's own
actions and are NOT written to the MCP access log (consistent with the
existing carve-out documented at the top of `GanchoCLI.swift`). `print` is
used only inside the `gancho` executable, per the NoContentLoggingTests
carve-out; no os_log/Logger/NSLog anywhere.

### MCP `list_boards` tool — NOW IMPLEMENTED (follow-up pass, 2026-07-02)

The skip below is historical. A later pass was granted edit access to
`Apps/GanchoMac/PrivacyCenterView.swift`, unblocking the recipe exactly as
documented in Follow-up 1:

- `MCPAccess.swift` — `case listBoards = "list_boards"` added to
  `MCPToolName` (doc comment bumped to "five tools").
- Every exhaustive switch over `MCPToolName` was found and extended (a repo
  grep confirmed there are exactly two):
  - `MCPToolRunner.call(tool:arguments:)` — `case .listBoards:` dispatch arm.
  - `PrivacyCenterView.mcpToolSymbol(_:)` — `case .listBoards:
    "rectangle.stack"` (NOT the recipe's "square.stack", which `.pasteStack`
    already uses in that same switch; `rectangle.stack` is the boards glyph
    the iOS app uses). SF Symbol names are not user-facing localized strings,
    so no String Catalog change was needed. `MCPAccessView.swift` holds a
    static `tools` ARRAY, not a switch — it compiles untouched, but its
    "Tools exposed" list now shows four of the five tools (that file is owned
    by other agents; adding the row there is a one-liner follow-up).
- `MCPToolRunner.listBoards()` — returns `store.pinboards()` mapped to a new
  `BoardSummary` (id, name, sfSymbol) via the shared `ok(...)` encoder.
  Allowed in EVERY scope (board names are organization, not clip content) but
  still logged via `record(.listBoards, count: boards.count)` — the "every
  MCP call is logged" invariant that blocked the string-dispatch workaround
  now holds properly.
- `MCPToolTypes.swift` — `BoardSummary` + `ListBoardsResult`, and a fifth
  descriptor in `toolDescriptors` with an empty-object input schema (no args;
  the server already defaults missing `arguments` to `.object([:])`, and the
  runner decodes nothing for this tool).
- Tests — `MCPServerTests.toolsListEnabled` now asserts 5 tools including
  `"list_boards"`; `MCPToolRunnerTests` gains two positive tests (metadata
  scope returns the migration-seeded Favorites board plus a created board
  with its sfSymbol; the access log records `.listBoards` with the board
  count and `wasDenied == false`). The tests run against the real GRDB store
  from `MCPTestSupport.swift`, whose `v11-favorites` migration always seeds
  the Favorites board — counts assert 2 (Favorites + created) and 1
  (Favorites only) accordingly.

## What was SKIPPED, and why (historical)

### MCP `list_boards` tool — skipped (would break an unownable file)

Plan was: `case listBoards = "list_boards"` in `MCPToolName`, a runner case,
an empty-args + result type, a descriptor, and test updates. This was
abandoned before writing code because `MCPToolName` appears in an exhaustive
`switch` with no `default` in a file this change is not allowed to touch:

- `Apps/GanchoMac/PrivacyCenterView.swift:237` — `mcpToolSymbol(_:)`
  switches over all four `MCPToolName` cases exhaustively. Adding a fifth
  enum case makes that file fail to compile, and `Apps/` is owned by other
  agents in this audit.

A workaround (dispatching the `"list_boards"` string in `MCPToolRunner.call`
BEFORE the `MCPToolName(rawValue:)` lookup) was considered and rejected: the
access log (`MCPAccessEvent.tool`) is typed as `MCPToolName`, so a
string-only tool could not be recorded to the Privacy Center — violating the
"every MCP call is logged" invariant. Shipping an unlogged tool is worse than
shipping no tool.

Consequently NO test changes were needed or made: `toolDescriptors` still has
exactly 4 entries, so `MCPServerTests.toolsListEnabled` ("advertises all four
tools", count == 4) and the tool-name assertions in `MCPToolRunnerTests`
remain correct as-is.

## Follow-ups (need coordination or new store methods — out of scope here)

1. **`list_boards` MCP tool**: DONE — see "NOW IMPLEMENTED" above. Remaining
   one-liner: add a `list_boards` row to the static `tools` array in
   `Apps/GanchoMac/MCPAccessView.swift` (a display list, not a switch — no
   compile impact) so the "Tools exposed" screen shows all five.
2. **`get_board` contents (clips on a board)**: `MCPClipStore` has no
   "clips for board id" method (`assign` writes, nothing reads the
   junction) — needs a new store/protocol method, so not done.
3. **CLI `gancho boards` clip counts / `gancho assign`**: same gap;
   `assign(clipID:toBoard:)` exists and is public, so a CLI `assign` verb is
   feasible later, but was out of the requested scope.
4. **CLI tests**: the `gancho` executable target has no test target today
   (its logic is private statics); extracting the verb bodies into a testable
   module would let `boards`/`pin` gain coverage.

## Files touched

- `Packages/GanchoKit/Sources/gancho/GanchoCLI.swift` — new verbs
  `boards`/`pin`/`unpin`, `CLIBoard`, usage + header updates.
- `.audit/08-cli-mcp-features.md` — this document.

Follow-up `list_boards` pass additionally touched:

- `Packages/GanchoKit/Sources/GanchoKit/MCPAccess.swift` — new enum case.
- `Packages/GanchoKit/Sources/GanchoMCP/MCPToolRunner.swift` — dispatch arm +
  `listBoards()`.
- `Packages/GanchoKit/Sources/GanchoMCP/MCPToolTypes.swift` — `BoardSummary`,
  `ListBoardsResult`, fifth descriptor.
- `Apps/GanchoMac/PrivacyCenterView.swift` — `mcpToolSymbol` arm.
- `Packages/GanchoKit/Tests/GanchoMCPTests/MCPServerTests.swift` — 4 → 5.
- `Packages/GanchoKit/Tests/GanchoMCPTests/MCPToolRunnerTests.swift` — two
  new `list_boards` tests.
