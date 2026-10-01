# Deterministic text recipes

The core contract and macOS editor described here are unreleased. Existing
Transform and Smart Paste entry points remain unchanged.

`TextActionCatalog` assigns stable version-1 descriptors to existing transforms,
PII redaction, literal selected-context formatting and three whitespace operations.
Recipes have a name, UUID, format version and an ordered list of up to eight uniquely
identified steps. There are no scripts, provider calls, models or new paywalls.

Description, validation and execution are separate. Decoding preserves unknown
versions and actions; execution rejects them rather than deleting or skipping steps.
Version 1 accepts no action parameters. Invalid parameters fail before any execution.

`TextRecipeExecutor` runs on a detached worker with cancellation propagation. Input
and every intermediate result must fit 1 MiB of UTF-8. Context formatting additionally
uses its existing 64 KiB output limit, including headers. Exceeding a limit throws;
no text is truncated. Existing transforms preserve their original behavior.

Normalize line endings maps newline characters to LF. Trim trailing line spaces
preserves indentation, paragraphs and original newline delimiters. Trim each line
also removes leading whitespace. None repairs hyphens or joins OCR words.

The executor has no UI, store or clipboard dependency. Results remain in memory;
this contract never edits clips, grants permissions, copies or pastes automatically.
Unit tests cover every existing transform, Unicode, CRLF, ordering, preservation,
invalid versions and parameters, admission cancellation and byte-limit boundaries.

## Local editor and reviewed delivery (unreleased)

In the macOS text peek, choose **Transform > Text recipes…**. Create, rename, edit,
reorder or delete a definition, then review **Before** and **After** and explicitly
choose **Copy result**. Unsaved changes require an explicit discard before choosing
another recipe. The first release supplies Clean OCR, Clean list and Prepare
redacted context. Sorting is never an implicit part of list cleaning.

Definitions live in the existing encrypted local database's append-only version-25
migration, not preferences, CloudKit records or sync snapshots. Presets are seeded
once; reopening never resurrects a deleted preset. Damaged rows are isolated and
can be explicitly deleted. Unknown action/version definitions remain readable but
cannot run or overwrite their stored definition until corrected to supported steps.
Serialized definitions are capped at 64 KiB before decoding or saving.

Preview display is capped at 8,000 characters and labeled accordingly; copying
always delivers the entire bounded result. Inputs/intermediates retain the 1 MiB
limit, with the stricter context-format limit when applicable. No result is saved
automatically. Cancellation clears temporary content. Copy revalidates the original
clip and privacy/deletion state immediately before writing an own-marked clipboard
item. A clipboard changed since processing is preserved; explicitly copying again
after reviewing acknowledges the newly observed clipboard revision.

PII redaction uses the existing pattern set and is best-effort, not a guarantee
that every personal identifier was removed. Review the result before sharing.

Preview shaping is bounded to 8,000 Unicode scalars (at most 32 KiB of text),
not only grapheme count: a single grapheme can contain arbitrarily many combining
marks. This display-only bound does not alter the input, intermediate results or
explicitly copied output.
