# Multimodal retrieval evaluation

An exploratory benchmark, not a feature. It measures how well today's OCR-based
retrieval finds saved images, so that any native visual model has a baseline to
beat before it can ship. Production code is unchanged: Gancho still keeps image
clips out of the semantic index.

## Run it

`GANCHO_MULTIMODAL_EVALUATION=1 swift test --disable-automatic-resolution --package-path Packages/GanchoKit --filter MultimodalRetrievalEvaluationTests`

It needs the installed English contextual embedding assets and fails, rather
than skipping, when they are missing. It never downloads anything. The run
prints a JSON receipt with the corpus revision, OS, hardware model, OCR and
embedding configuration, and per-bucket results. Keep the receipt with the
evidence for a decision; it is not a product claim.

Repeat the [text evaluation](HYBRID-RETRIEVAL.md#reproducible-relevance-evaluation)
in the same session to show that text retrieval did not regress.

## Corpus

Everything is rendered at test time with CoreGraphics and CoreText. No real
clipboard history is used.

- 100 captures: 20 error dialogs, 20 architecture diagrams, 15 bar charts,
  15 near-duplicate deploy screens, 15 text-free shape images and 15 text notes.
- 30 frozen queries, 15 English and 15 Spanish: exact identifiers, OCR
  paraphrases, visual relations, visual-only scenes and 6 unanswered queries.
- Every visual-relation answer has a hard negative with the same words, such as
  the same diagram with its arrows reversed or the same chart trending the other
  way. OCR text cannot separate them.
- Calibration and held-out queries never share an answer. Tune on calibration;
  report held-out.

Changing a capture, query or answer requires bumping
`MultimodalEvaluationCorpus.revision`.

## Strategies

| Name | What it does |
|---|---|
| `ocr-lexical` | Vision OCR text stored on the clip, searched with the default fuzzy mode |
| `ocr-apple-semantic` | The lexical results, then related clips from the current Apple contextual model over OCR text |

OCR text that reads as a secret is dropped before it is stored, as enrichment
does. Sensitive and expired clips never rank. A new candidate joins by
conforming to `MultimodalRetrievalStrategy` in the test target.

## Results reported

For each strategy, language, category and split: Recall@5, mean reciprocal rank,
missed queries, unanswered queries that still returned results, and wrong-image
selections (an unexpected image ranked first).

The opt-in run asserts only what must hold on any machine: every identifier is
found through OCR, literal search returns nothing for unanswered queries,
semantic results never reorder literal ones, and shape images yield no OCR text.
Relevance numbers are reported, not gated.

The corpus, scoring and privacy suites run in every `make test` without model
assets: corpus integrity, deterministic rendering, scoring arithmetic, secret OCR
dropped, and expired and sensitive clips vetoed by both strategies.

## Limits

Thirty queries over a synthetic corpus is a small sample. It can show that OCR
cannot answer visual questions; it cannot prove that a model will answer real
users' questions well. Latency, memory, download size and battery cost of a
native visual model are not measured here yet.
