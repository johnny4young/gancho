# 07 — Dev Actions added

Eighteen new pure, offline, deterministic text transforms added to
`Packages/GanchoKit/Sources/GanchoAI/DevActions.swift`, following the existing
`ActionID` / `action(_:)` / `actions(for:)` / `(String) throws -> String`
pattern exactly. No new dependencies (Foundation + CryptoKit only, and
CryptoKit is already used throughout GanchoKit). No logging added anywhere in
the engine module.

## Actions added

| id | title | surfaces on | behavior |
|---|---|---|---|
| `sha256Hex` | SHA-256 hash | text, code | Lowercase hex SHA-256 digest of the UTF-8 text (same hex idiom as BlobStore). |
| `sha1Hex` | SHA-1 hash | code | Lowercase hex SHA-1 digest (CryptoKit `Insecure.SHA1`). |
| `md5Hex` | MD5 hash | code | Lowercase hex MD5 digest (CryptoKit `Insecure.MD5`). |
| `urlEncode` | URL encode | text, code, url | Percent-encodes everything outside the RFC 3986 unreserved set (`A–Z a–z 0–9 - . _ ~`). |
| `urlDecode` | URL decode | code, url | `removingPercentEncoding`; throws `notApplicable` on malformed escapes / invalid UTF-8. |
| `caseConvert` | Convert case | text, code | Tokenizes on non-alphanumerics + camel humps; emits labeled camel/snake/kebab/title/upper/lower lines. |
| `epochToDate` | Epoch to date | text | Integer Unix timestamp (12+ digits read as ms) → labeled ISO-8601 UTC + local lines; bounds-checked. |
| `dateToEpoch` | Date to epoch | text (via epoch pairing), date | ISO-8601 (with or without fractional seconds) → labeled epoch seconds + milliseconds. |
| `sortLines` | Sort lines | text, code | Lexicographic sort of `\n`-separated lines; needs ≥ 2 lines. |
| `dedupeLines` | Dedupe lines | text, code | Stable dedupe, first occurrence wins; needs ≥ 2 lines. |
| `reverseLines` | Reverse lines | text | Reverses line order; needs ≥ 2 lines. |
| `countStats` | Count stats | text, code | Labeled lines / words / characters (graphemes) / bytes (UTF-8). |
| `htmlEntityEncode` | HTML-entity encode | text, code | Escapes `& < > " '` (`&amp; &lt; &gt; &quot; &#39;`). |
| `htmlEntityDecode` | HTML-entity decode | code | Decodes named (`amp lt gt quot apos nbsp`) and numeric (`&#65;` / `&#x42;`) entities; stray `&` kept literal. |
| `slugify` | Slugify | text | Diacritic-folds, lowercases, hyphenates separators, strips non-alphanumerics, collapses repeats, trims edge hyphens. |
| `numberBaseConvert` | Convert number base | text | Parses dec / `0x` hex / `0b` bin / `0o` oct (optional `-`); emits labeled dec/hex/bin/oct lines. |
| `jsonEscape` | JSON-escape string | json, code | Wraps text as a JSON string literal (via one-element-array serialization, so escaping rules are JSONSerialization's, not hand-rolled). |
| `jsonUnescape` | JSON-unescape string | code | Unwraps a single JSON string literal back to raw text; throws on anything else. |

Kind wiring notes:
- `.jwt`, `.color`, `.uuid` catalogs are untouched (existing tests assert exact
  equality on those).
- `.date` kind now surfaces `dateToEpoch` (previously fell through to `[]`).
- `.text` and `.code` were split from the shared `case .text, .code:` into two
  curated lists: `.text` leans prose/free-form (case, slug, stats, line ops,
  epoch, number base), `.code` leans developer-string (JSON/HTML escaping, URL
  codec, all three hashes).
- Every action remains runnable on any input via `DevActions.run(_:on:)`, so
  App Intents can invoke all of them regardless of kind.

## Tests

Added 22 new `@Test` functions (one parameterized over 4 inputs) to
`Packages/GanchoKit/Tests/GanchoAITests/DevActionsTests.swift`, covering
positive vectors (canonical SHA-256/SHA-1/MD5 test vectors for "abc" and "",
round-trips for URL/HTML/JSON escaping, exact epoch 1500000000 ↔
2017-07-14T02:40:00Z both directions incl. milliseconds and fractional
seconds) and `notApplicable` negatives for every throwing transform, plus a
catalog test for the new kind wiring. Prior file had 9 tests; now 31 test
functions total.

`epochToDate`'s `local:` line is machine-timezone dependent by design, so the
test only asserts the `utc:` line.

## App Intent exposure

`Apps/GanchoMac/DevActionIntent.swift` — added the 18 matching cases to
`DevActionChoice` plus their `DisplayRepresentation` string literals, same
style as the existing eight. Raw values mirror `ActionID` raw values so the
existing `ActionID(rawValue:)` bridge picks them up with no other changes.

## Deliberately skipped

- Nothing from the requested list was skipped — all 11 groups landed.
- Named HTML entities beyond the core six (`amp lt gt quot apos nbsp`): the
  full WHATWG table is ~2k entries; out of scope for a deterministic v1.
- Locale-aware "Title Case" (small-word rules); `caseConvert` capitalizes
  every token, which is the DevTools-style expectation.
- Line ops intentionally treat a trailing newline as producing a final empty
  line (matches `components(separatedBy:)` semantics; same as `sort`/`uniq`
  behavior on such input).

## Follow-up

- **Localization**: `Action.title` is English-only today (the doc comment says
  "UI localizes via the String Catalog key"). The new titles follow the same
  terse English pattern; when the String Catalog pass happens, the 18 new
  titles ("SHA-256 hash", "Convert case", …) plus the matching
  `DisplayRepresentation` literals in `DevActionIntent.swift` need catalog
  entries. Labeled output prefixes (`camel:`, `utc:`, `dec:` …) are treated as
  machine-readable output, not UI copy, and should stay unlocalized.
- **App Intents**: cases were added to `DevActionChoice`; if the iOS app grows
  its own intent catalog, mirror there. Consider generating
  `DevActionChoice` from `ActionID.allCases` eventually to remove the manual
  mirror.
