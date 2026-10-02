# Preparing selected context for AI

Select text-backed clips in the macOS panel and choose **Prepare context for AI…**. Review the excerpts, change their order or remove incompatible items, then choose **Copy Markdown**. Copying does not enable MCP, create a clip, modify the originals or connect to a provider.

The maximum is 100 clips and 64 KiB of UTF-8 output, including Markdown headers and code fences. Missing, protected, expired, image and file clips are not silently omitted. Reduce or correct the selection before continuing. The output preserves excerpt text in dynamically sized fences; quotation is not a guarantee that an external model will ignore hostile instructions.

Each review owns an ordered manifest. MCP authorization uses a separate set of exactly those IDs, never the manifest's presentation order or all clipboard history. Gancho revalidates the reviewed content immediately before copying or creating a grant. A changed clipboard is preserved.

## Optional, explicit MCP grant

Enter a client name and choose **Grant selected context access**. This enables local MCP and creates a read-only, selected-ID grant expiring in one hour. Existing grants are not replaced. Enabling MCP also reactivates any other still-valid existing grants; the review discloses this before authorization. Deleting or protecting an excerpt does not expand the authorized set. Revoke the grant in **MCP Access**; expiry and revocation are checked by the existing server authorization path.

The command shown after authorization starts Gancho's local stdio server. These examples are manual instructions, not configuration Gancho changes for you. Use your installed `gancho` executable and replace `GRANT_UUID` with the grant shown in the review. An expired grant must be replaced explicitly.

### Codex CLI

```sh
codex mcp add gancho-selected -- gancho mcp --grant GRANT_UUID
```

See [OpenAI's MCP configuration guide](https://developers.openai.com/codex/mcp/) for client configuration and removal.

### Claude Code

```sh
claude mcp add --transport stdio gancho-selected -- gancho mcp --grant GRANT_UUID
```

See [Anthropic's MCP guide](https://code.claude.com/docs/en/mcp) for client scope, configuration and removal. For Claude Desktop, configure a stdio entry manually using command `gancho` and arguments `mcp`, `--grant`, `GRANT_UUID`; no external settings are edited by Gancho.

Local extraction and formatting do not call a cloud service. A connected external client may send the content to its own model/provider: review that client's privacy policy before granting access. Read-only access prevents Gancho mutations, not downstream copying by the authorized recipient.

This documents the source implementation after v0.9.1; it is not a claim that this workflow is already available in that published release.

Grant creation and app/CLI policy updates read the latest local configuration under a nonblocking interprocess lock; contention produces an explicit retryable error instead of blocking the app. A malformed configuration is not replaced by a new grant; existing revocations remain intact. Snapshot `save` remains a low-level initialization API, not the runtime mutation route.

The generated connection command has an explicit copy action using Gancho's
self-write marker, just like Markdown delivery. Native text selection is disabled
in the temporary review so copying the command does not recapture it into history.
Copying a command does not renew or broaden its grant; the server rechecks the
current grant and clip state on every request.

Both Markdown copying and grant creation check the captured clipboard revision
immediately before delivery. A replacement during loading produces a reviewable
changed-state result instead of creating access or overwriting the new clipboard.

Selection-list excerpts are capped at 80 Unicode scalars (at most 320 UTF-8
bytes), not 80 potentially unbounded grapheme clusters. This is only a display
preview: validation, ordering, Markdown and permission checks use the complete
original text.
