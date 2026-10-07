# Content-bound generated titles

An annotation is computed from the captured body. While the annotator awaits its
model, the user may replace that body and leave the title empty. Checking only
`title = ''` prevents overwriting a manual title but still lets the old annotation
label the new body.

Capture enrichment now requires the optional `ContentBoundTitleStoring` capability
for generated titles. Its GRDB implementation uses one guarded UPDATE: the body
must exactly match the source supplied to the annotator, the title must still be
empty, and the row must remain a live, unarchived, non-sensitive text-backed item
of a known eligible kind. A rejected guarded update changes neither the revision
nor the upload flag. The coordinator's existing follow-up sync enqueue policy is
unchanged. The title-written callback fires only after an accepted write, so a
stale result does not consume the free title taste or announce a title update.

The existing `ClipEnriching` requirements and `updateTitleIfEmpty` implementation
remain available for source compatibility. A custom store without the guarded
capability skips generated titles rather than using an unsafe fallback. Production
GRDB supports the capability. OCR, model choice, prompt, input budget, manual-title
editing and enrichment scheduling are unchanged.

The full body is compared, not the capture hash: curation deliberately retains that
hash for deduplication. Content-equal ABA changes are acceptable when the current
row remains eligible and untitled; the annotation describes that same current
body. Recreated IDs with different text are rejected. A manual title always wins,
even if the body never changed.

Tests pause an injected annotator with continuations, edit the captured body before
releasing the annotation, then assert both title and callback behavior. An unchanged
body is the positive control. Persistence tests independently verify the database
predicate, upload bookkeeping, manual-title precedence and eligibility changes.
No sleep, model asset download or wall-clock race threshold is required.
