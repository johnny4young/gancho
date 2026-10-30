# Preparing selected context for AI

Select text-backed clips in the macOS panel and choose **Prepare context for AI…**. Review the excerpts, change their order or remove incompatible items, then choose **Copy Markdown**. Copying does not enable MCP, create a clip, modify the originals or connect to a provider.

The maximum is 100 clips and 64 KiB of UTF-8 output, including Markdown headers and code fences. Missing, protected, expired, image and file clips are not silently omitted. Reduce or correct the selection before continuing.

## Text recognized from an image

An image whose text Gancho already recognized shows **Use recognized text** in the review. Until you choose it, the image blocks copying and granting like any other incompatible clip. Once chosen, the full recognized text appears in the preview under a heading that marks it as recognized from an image: it is OCR output, not the original text.

Only that text is shared. Copying and grants never include the image or its file, and a granted client sees only the image's ID, type and capture time: its title, preview, pin state and source app stay hidden. Recognized text that reads as a secret is protected and cannot be chosen. A grant stores a SHA-256 digest of the reviewed text. If Gancho recognizes the image again and the text changes, the grant stops returning it, search stops matching it, and the review asks you to choose it again. An image without recognized text stays incompatible.

Over MCP, `get_clip` and `paste_stack` label that text with `"representation": "recognizedText"`, and the hidden fields are omitted from the response rather than sent empty. `search_clips` matches a chosen image only on its reviewed text, never on its hidden title or preview, and under metadata-only access it matches no text of a chosen image at all. Grants created before this change, or for clips you did not choose this way, behave exactly as before and never return recognized text.

## Reviewed images

Any image in the review also offers **Share image**. Gancho prepares a copy for review: the first frame, rotated upright, at most 1,568 pixels on its longest side, re-encoded as PNG (or JPEG when PNG would exceed 2 MB) with no EXIF, GPS or other metadata from the original. The review shows exactly those pixels. Images that declare more than 50 million pixels are refused before anything is decoded.

Choosing the pixels never shares the recognized text, and choosing the text never shares the pixels; you can choose both. Markdown cannot carry pixels, so a context that shares any image can be granted but not copied.

The reviewed copy is stored encrypted with the rest of the store, under a name derived from its SHA-256 digest, and the grant records that digest. `get_clip` returns the JSON block followed by an MCP image block with exactly those bytes. If the file is missing or no longer matches, the JSON reports the image as withheld and no image block is sent; the original image is never sent instead. `paste_stack` is text only, so an image shared only as pixels is skipped. Search never matches the recognized text of an image shared only as pixels; an empty query still lists it. Revoking a grant, creating a new one, or the next launch deletes reviewed copies that no active grant can still serve.

Whether a client actually shows the image to its model is up to that client.

Sharing recognized text and reviewed images is not in a published release yet. The output preserves excerpt text in dynamically sized fences; quotation is not a guarantee that an external model will ignore hostile instructions.

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

This workflow is published in v0.10.0.

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
