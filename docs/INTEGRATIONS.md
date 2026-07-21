# Gancho integrations — CLI, MCP server, VS Code

Gancho exposes the clipboard history to the terminal, to local AI agents, and
to the editor — all **local, offline, no account, no network**. Every
integration opens the same on-device store the app uses
(`~/Library/Application Support/Gancho/`); the macOS app is unsandboxed, so a
Homebrew-installed binary reaches the exact same database (GRDB in WAL mode →
safe concurrent access, app open or closed).

> Sensitive clips (passwords, keys, cards the detector flagged) are **never**
> exposed through any integration, in any scope.

---

## The `gancho` CLI

A single executable (`Packages/GanchoKit` → product `gancho`). Build it with:

```bash
swift build -c release --package-path Packages/GanchoKit --product gancho
# → Packages/GanchoKit/.build/release/gancho
```

| Command | What it does |
| --- | --- |
| `gancho search <query> [--limit N] [--mode exact\|fuzzy\|regex] [--json]` | Search history; prints `id⇥kind⇥title` (or JSON with `--json`). |
| `gancho copy <clip-id>` | Put a clip's content back on the system pasteboard. |
| `gancho save [--title <t>] [--language <id>] [--content-base64 <b64>]` | Save a snippet into the Library (or pipe raw text on stdin). |
| `gancho export [--csv] [--out <path>]` | Export the whole history as JSON (default) or CSV. |
| `gancho boards [--json]` | List board identifiers used to create explicit MCP contexts. |
| `gancho pin <clip-id>` / `gancho unpin <clip-id>` | Organize one clip from the terminal. |
| `gancho mcp --grant <grant-id>` | Run one authorized stdio MCP session (see below). |
| `gancho status` | Print the store path, clip count, and MCP state. |
| `gancho enable` / `gancho disable` | Toggle the MCP server globally; enabling it does not authorize a client. |
| `gancho grant --client <name> --board <id> ...` | Create an expiring client grant with explicit board/time context. |
| `gancho revoke <grant-id>` | Revoke a client; its next call fails closed without a restart. |

The store directory defaults to the app's; override it with the
`GANCHO_STORE_DIR` environment variable (useful for tests or alternate
profiles). `search`/`copy`/`save`/`export` are your own actions and are **not**
logged; only the MCP server logs (it serves automated agents).

---

## Local MCP server (`gancho mcp`)

A stdio JSON-RPC server that lets approved local AI agents (Claude, Cursor)
work inside an explicit Gancho context. **Opt-in and OFF by default** — enable
it in **Settings → Integrations** or with `gancho enable`. Enabling the server
does not authorize a process: every MCP launch also needs one live client grant.
State lives in an owner-only config file in the store directory, so the app and
CLI share revocation and expiry without entitlements.

**Tools:** `search_clips`, `get_clip`, `create_pin`, `paste_stack`,
`list_boards`. Read-only grants do not advertise `create_pin`.

Every grant combines four independent limits:

- **Client identity and lifetime.** A bounded display name plus an expiry date;
  revoke takes effect when an already-running server resolves its next call.
- **Explicit context.** One approved board (or a curated clip set in embedded
  clients), optionally narrowed to the last hour/day/week/month. There is no
  ambient-history fallback.
- **Read policy.** `metadata` returns titles/previews only; `boards` can return
  content for marked clips inside the context; `all` can return non-sensitive
  content, still only inside the context.
- **Mutation policy.** Read-only is the default. Read-write permits pinning or
  organizing only inside the approved context, never arbitrary board creation.

Sensitive clips are excluded under every policy. Database queries apply context
filters before results leave the store, and out-of-context IDs look identical
to missing IDs. Every call is recorded to a **content-free** access ledger
(grant/client, tool, policy, result count, denial reason, timestamp — never
clip content), shown in **Privacy Center → Local MCP access**.

### Connecting a client

Create the smallest practical grant in Settings, or from the CLI:

```bash
gancho boards --json
gancho grant --client "Claude Code" --board <board-id> \
  --scope metadata --time last-week --expires-hours 24
# Copy the printed command: gancho mcp --grant <grant-id>
```

The examples below use the printed grant ID. Do not reuse one grant across
clients; separate identities make expiry, revocation, and the access ledger
meaningful.

**Claude Code (CLI):**

```bash
claude mcp add gancho -- /absolute/path/to/gancho mcp --grant <grant-id>
```

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{ "mcpServers": { "gancho": { "command": "/absolute/path/to/gancho", "args": ["mcp", "--grant", "<grant-id>"] } } }
```

**Cursor** — `~/.cursor/mcp.json`: same shape as Claude Desktop.

Use `gancho status` to inspect grant state and `gancho revoke <grant-id>` to
stop a client. Disabling MCP remains a global emergency stop.

---

## VS Code extension

At `integrations/vscode/` (TypeScript; not an Xcode target). Adds the
**“Gancho: Save Selection”** command: it takes the current selection (or the
whole document) plus its `languageId`, base64-encodes it, and runs
`gancho save`. If the CLI isn't on `PATH`, it offers a **Download Gancho** link
instead of failing.

```bash
cd integrations/vscode
npm install
npm run compile        # tsc → out/extension.js
```

Press <kbd>F5</kbd> for an Extension Development Host, or package a `.vsix` with
`npx @vscode/vsce package`. The `gancho.path` setting overrides the binary
location.

---

## Distribution status

- **Homebrew cask — published.** The public tap installs the signed Mac app and
  exposes its bundled CLI and MCP server on `PATH`:

  ```bash
  brew tap johnny4young/tap
  brew install --cask gancho
  ```

  `scripts/homebrew/gancho.rb` remains an optional source-only CLI formula
  template. Publishing that separate formula is owner-gated and is not needed
  to use the CLI included with the cask.
- **VS Code Marketplace — not published.** The extension already uses the
  `johnny4young` publisher identifier and builds locally. Marketplace account
  access, final package inspection, and `npx @vscode/vsce publish` remain
  owner-gated.
- **Website — published.** The canonical download and product site is
  [gancho.app](https://gancho.app).
