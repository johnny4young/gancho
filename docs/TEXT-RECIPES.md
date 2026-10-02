# Deterministic text recipes

This unreleased core contract does not yet add an editor or persist definitions.
Existing Transform and Smart Paste entry points remain unchanged.

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
