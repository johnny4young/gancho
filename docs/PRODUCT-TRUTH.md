# Product truth contract

Gancho's public copy must describe what the current source and released
artifacts actually do. This matrix is the review boundary for README, website,
security, architecture, release notes, and App Store copy.

| Claim | Canonical evidence | Safe public wording | Automated gate |
| --- | --- | --- | --- |
| Supported OS versions | `project.yml` deployment targets | Requires macOS 26+ and iOS/iPadOS 26+ | `ReleaseMetadataTests`, `scripts/check-product-truth.sh` |
| Local storage | `GRDBClipboardStore`, `BlobStore`, encryption tests | History is encrypted locally with SQLCipher; binary blobs use the shared sealed envelope | Encryption and no-content-logging tests |
| iCloud boundary | `GanchoSync`, app entitlements, sync tests | Content stays on the user's devices or, when enabled, in the user's private iCloud database; Gancho operates no intermediary sync server | Sync configuration and contract tests |
| Optional diagnostics | `TelemetryEvent`, `TelemetryConsent`, privacy manifests | Anonymous counts and broad buckets are off until explicit consent; clipboard content, titles, searches, and source-app names never enter telemetry | Telemetry and privacy-manifest tests |
| Main history search | `ClipSearch`, `GRDBClipboardStore`, prefix-index migrations | Main search offers FTS exact, fuzzy, and regex modes; dedicated short-prefix indexes keep fuzzy recall responsive while typing | Search tests plus the 100k cold/warm performance harness |
| Semantic retrieval | `EmbeddingIndex`, `ClipboardQAService`, `BoardSuggestionService` | A local 512-dimension embedding index powers Ask your clipboard and board suggestions; it is not the main history-search path | Semantic-search, Q&A, and board-suggestion tests |
| Board identities | `Pinboard.colorHex`, `Pinboard.emoji`, `BoardIdentityEditor`, `BoardIdentityMark` | Boards can use a fixed accessible color and an optional emoji identity across Mac, iPhone, and iPad; changes use the durable board mutation and sync path | Board identity unit tests plus macOS and iOS UI persistence tests |
| Rich clipboard formats | `NSPasteboardReader`, `PasteBackService` | macOS captures RTF or HTML with a plain-text companion and can paste the stored rich representation back; plain-text paste is an explicit alternative | Pasteboard-fidelity and paste-back tests |
| Paste stack | `PasteStackStrip`, `PasteStack` | Clips are queued from the panel, visible in its footer strip, and pasted with the configurable stack shortcut | Paste-stack unit tests and macOS UI coverage |
| Package topology | `Packages/GanchoKit/Package.swift` | One package exposes eight libraries plus the `gancho` CLI | `ReleaseMetadataTests`, `scripts/check-product-truth.sh` |
| Current direct download | GitHub release `v0.6.0`; last Gatekeeper-verified artifact `v0.5.0` | The Developer ID-signed, notarized, stapled lane that produced the accepted v0.5.0 DMG cuts v0.6.0 the same way; Gatekeeper acceptance is re-verified per published release | Version sync plus explicit release-copy assertions |
| Cross-device confidence | Sync tests and completed hardware smoke | A real-device pass has completed; repeat the full device matrix for every release candidate | Tests plus the manual release checklist |

## Maintenance rules

1. Prefer a precise boundary over an absolute slogan. “No intermediary sync
   server” and “no clipboard-content telemetry” remain true when optional
   private iCloud sync and consented diagnostics are enabled.
2. Treat source code and reproducible tests as canonical for product behavior.
   External state such as notarization, App Store products, or device smokes
   needs dated release evidence.
3. Update this matrix, README, both website languages, and their gates in the
   same commit when a claim changes.
4. Keep private planning identifiers out of committed prose. Public comments
   explain behavior and invariants, not internal scheduling labels.
