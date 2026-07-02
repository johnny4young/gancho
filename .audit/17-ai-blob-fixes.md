# AI / blob fixes (B-3, B-7, A-7)

Scope: dossier `14-security-performance-deep-dive.md`. Branch
`claude/gancho-engineering-audit-byfy24`. Validation is the GanchoKit test
suite on CI (no local toolchain).

## B-3 (P2, perf) — semantic search now scores with Accelerate

**Fix** (`Packages/GanchoKit/Sources/GanchoKit/SemanticSearch.swift`):
`semanticSearch` keeps the exact cosine formula — `dot / (‖v‖ · ‖q‖)` — but
computes the per-row dot product and norm with `vDSP.dot` /
`vDSP.sumOfSquares` (import Accelerate) instead of a scalar `for` loop,
mirroring `EmbeddingIndex`. Scores, ranking, and the zero-denominator skip
are unchanged; only the arithmetic is vectorized. A defensive
`vector.count == queryVector.count` guard replaces the old `zip` truncation
(the SQL `e.dimension = ?` filter already guarantees equality, and
`vDSP.dot` asserts on mismatched lengths).

**Deliberately NOT done:** normalize-on-write in `saveEmbedding`. Existing
rows are unnormalized; changing the stored semantics would need a migration
or a dual-format query path for zero ranking benefit. The dossier's
alternative (i) — vectorize the identical math, keep the stored format —
is what landed. Follow-up if the scan ever tops the 100 ms budget at scale:
store unit vectors (with a one-shot re-normalize migration) and drop to a
pure `vDSP_dotpr` over a contiguous buffer like `EmbeddingIndex.search`.

**Tests** (`Tests/GanchoKitTests/SemanticSearchTests.swift`): new `ranking`
test pins exact cosine order across three well-separated vectors (cos = 1,
1/√2, 0) and asserts a stored zero vector is skipped (never NaN). Existing
nearest-neighbor, library-scope, and dimension-exclusion tests unchanged.

## B-7 (P3, perf) — warm thumbnail generation bounded on the capture path

**Fix** (`Packages/GanchoKit/Sources/GanchoKit/BlobStore.swift`): `write()`
still warms the thumbnail cache from the in-memory data (so the memory-tight
keyboard never loads a full blob just to build one), but only for payloads
≤ `thumbnailWarmMaxBytes` (8 MiB). Larger images skip the warm pass — their
ImageIO decode/encode would gate the capture write — and build lazily on
first request via the existing cold-cache path in `thumbnailData(for:)`.
`write()`'s contract, hashing, and all sealing behavior are unchanged.

**Why the threshold, not async:** `BlobStore` is a `Sendable` value type with
no executor/queue reference; detaching thumbnail work from inside it would
change the type's nature (or push queueing onto every caller). Threshold
bounds the worst case now; follow-up: have the store actor that owns the
writer schedule warm generation as a post-insert utility task, then drop the
warm-at-write path entirely.

**Verified:** `GRDBEncryptionTests` thumbnail assertions still hold — the
tiny-PNG fixtures are far below the threshold (warm path still runs), and the
sealed/migration tests exercise the lazy path independently.

## A-7 (P3, security) — masking tail leak + entropy-gate bypass

**Fix** (`Packages/GanchoKit/Sources/GanchoAI/SensitiveDataDetector.swift`):

1. `SensitiveMasking.maskedPreview` masks entirely (`●●●●`) when the
   whitespace-stripped value is ≤ 8 characters — a 6-digit OTP or short PIN
   no longer reveals 4 of its few characters. Longer values keep the
   existing `●●●● xxxx` last-4 reveal; multiline behavior unchanged.
2. `isProbablePassword` gains a third (additive, last-resort) route: a
   single token of ≥ 24 chars, no whitespace, all ASCII alphanumerics, with
   Shannon entropy > 4.0 — catching base32 TOTP seeds and similar
   single-class generator output that the four-class route missed. The
   `pk_` public-key guard still runs first; all existing routes unchanged.
   The no-whitespace requirement keeps prose out, and the > 4.0 bar keeps
   ordinary long identifiers out (English-like text lands well below 4
   bits/char). Known limit: pure lowercase hex tops out at exactly 4.0 bits
   (16 symbols), so long hex stays uncaught unless mixed-case — the bar was
   kept high deliberately to avoid false positives.

**Tests** (`Tests/GanchoAITests/SensitiveDataDetectorTests.swift`): a
32-char base32-shaped seed (split mid-literal per the file's GitGuardian
convention) is flagged `probablePassword`; a long lowercase sentence with
spaces and a long low-entropy single-class token stay clean; short secrets
(6-digit OTP, spaced OTP, 8-char password) mask fully with no last-4 reveal.
