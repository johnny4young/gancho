# Scoped hybrid retrieval

Implemented source contract after v0.9.1; not availability in a published release.
This delivery is the retrieval engine, not the panel opt-in UI.

## Retrieval and privacy

The existing semantic API delegates to a scoped API. Metadata predicates (type,
source application, capture dates, board, marked, pinned and explicit IDs) apply
before cosine top-K. Sensitive, masked, archived and expired rows are always
excluded. Current-version local embeddings remain the only index. Non-finite
vectors cannot rank. Ties use clip UUID, independent of cursor order.

The scan streams vectors and retains only K candidates. Metadata is queried again
under the same predicates, with an update timestamp comparison; changed rows are
not delivered as obsolete semantic hits. Retrieval returns metadata only. Reading
or copying content still needs the existing current-state authorization checks.

Hybrid results preserve conventional ordering, then add distinct related IDs.
Empty queries and regex never invoke semantic retrieval. Cancellation propagates;
semantic failure reruns conventional retrieval instead of returning a stale snapshot.
There is no change to exact/fuzzy/regex, CLI or MCP contracts.

## Reproducible relevance evaluation

`GANCHO_SEMANTIC_EVALUATION=1 swift test --disable-automatic-resolution --package-path Packages/GanchoKit --filter HybridRelevanceEvaluationTests`

The versioned synthetic corpus has 120 queries, 60 per language: identifiers,
paraphrases, intersected filters and ten distinct unanswered topics. Calibration
and reserved topics are disjoint. The real contextual sentence model and its
already-installed assets are mandatory; this command does not download assets.
The existing default-English contextual embedder is reused for both query
languages, matching production; no separate model is introduced for Spanish.
Contract fakes are not relevance evidence. Reserved paraphrase Recall@5
must improve by at least ten percentage points in each language, with literal
results unchanged. The evaluation also reports unrelated suggestions for
unanswered queries; top-K is retrieval, not an abstention or confidence guarantee.

Missing real evidence, failed relevance or other required gates keeps this engine
and its dependent panel PR draft. Raw output and toolchain belong in PR evidence,
not claims that a synthetic corpus proves all real-world relevance.
