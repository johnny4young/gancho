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
| `gancho mcp` | Run the stdio MCP server (see below). |
| `gancho status` | Print the store path, clip count, and MCP state. |
| `gancho enable [--scope metadata\|boards\|all]` / `gancho disable` | Toggle MCP access and pick its scope. |

The store directory defaults to the app's; override it with the
`GANCHO_STORE_DIR` environment variable (useful for tests or alternate
profiles). `search`/`copy`/`save`/`export` are your own actions and are **not**
logged; only the MCP server logs (it serves automated agents).

---

## Local MCP server (`gancho mcp`)

A stdio JSON-RPC server that lets local AI agents (Claude, Cursor) read the
clipboard. **Opt-in and OFF by default** — enable it in **Settings →
Integrations** or with `gancho enable`. State lives in a config file in the
store directory, so the app and the CLI share it without entitlements.

**Tools:** `search_clips`, `get_clip`, `create_pin`, `paste_stack`.

**Access scope** bounds how much an agent sees (sensitive clips excluded in all
three):

- `metadata` — titles and previews only, never a content body.
- `boards` — full content, but only for clips you marked (pinned).
- `all` — full content of every non-sensitive clip.

Every agent call is recorded to a **metadata-only** access log (tool, scope,
result count, denied flag, timestamp — never content), shown in
**Privacy Center → Local MCP access**.

### Connecting a client

The server is read once at process start, so set the scope **before** the
client spawns it.

**Claude Code (CLI):**

```bash
claude mcp add gancho -- /absolute/path/to/gancho mcp
```

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{ "mcpServers": { "gancho": { "command": "/absolute/path/to/gancho", "args": ["mcp"] } } }
```

**Cursor** — `~/.cursor/mcp.json`: same shape as Claude Desktop.

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

## Pending to publish (owner-gated)

These are distribution actions only the owner can take — the code is ready.

- **Homebrew (CLI).** `scripts/homebrew/gancho.rb` is a template. At a tagged
  release: fill `url` + `sha256` from the source tarball, confirm the `license`,
  and push the formula to a tap (e.g. `johnny4young/homebrew-tap`). Then
  `brew tap johnny4young/tap && brew install gancho`.
- **VS Code Marketplace (extension).** Needs a `vsce` publisher account. Set the
  real `publisher` in `integrations/vscode/package.json`, then
  `npx @vscode/vsce publish`. (Today `publisher` is a placeholder.)
- **Website.** The download funnel and the formula homepage point at
  `https://gancho.app`; confirming/registering that domain is its own task.
