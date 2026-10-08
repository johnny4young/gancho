# Content-bound background embeddings

Capture enrichment and model-version refresh compute a vector from text read before
an asynchronous persistence call. A text edit can occur between those operations.
Deleting the old vector during the edit is insufficient: the older producer must
not restore it afterward.

`ContentBoundEmbeddingStoring` is the optional guarded-write capability. Gancho's
GRDB store implements it with one `INSERT ... SELECT` statement in a write
transaction. It compares the complete source text using SQLite's exact text
comparison and requires a live, visible, non-sensitive text-backed row. Visibility
uses the same expiry predicate as reads, so a pinned, boarded or snippet row that
retention keeps past its expiry stays indexable. A changed, deleted, hidden expired,
archived, masked or binary row causes a no-op, reported as false.
No unguarded read/write gap, model execution or asynchronous wait occurs inside the
transaction. The source body is never logged or persisted as extra metadata.

Both background producers use this capability. Refresh counts only accepted writes
as progress and stops after a zero-progress batch. The stale-vector queue excludes
the kinds the guarded write always rejects, so such a row cannot occupy a batch
forever and stall the rows behind it. A future pass can retry eligible
work; this correction does not introduce a new reindexing scheduler.

## Compatibility and identity

The existing `ClipEnriching` and `EmbeddingRefreshSource` requirements and their
unconditional write methods remain available. Existing conformers still compile.
Background producers skip embedding work for a store that lacks the guarded
capability, rather than fall back to an unsafe write. Production uses the conforming
GRDB store; title and OCR behavior is unchanged.

Vectors depend on body text and the current model version, not on title, keyword or
revision timestamps. Title-only changes are therefore allowed. Content-equal ABA
changes, including a deleted/recreated identity with the same eligible body, can
accept the vector because it describes the current body. Reuse of the same identity
with different text or changed privacy eligibility is rejected.

The input hash is unsuitable for this comparison: curation deliberately preserves
that hash so copying the original still deduplicates. Comparing only the first
1,000 characters would also discard evidence the producer had, so the guarded write
compares the full body even though current model computation truncates its input.

## Verification

Store tests cover changed bodies, deletion and identity reuse, title/content-equal
changes, and altered eligibility. Caller tests suspend at the write boundary with
continuations, change the body, then resume; they use no sleeps or model downloads.
An unchanged-body control proves a successful refresh can still make progress.
