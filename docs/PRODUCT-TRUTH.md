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
| Private activity receipt | `PrivateActivityReceipt`, `clip_app_stats`, both Privacy Centers | Capture, reuse, skipped/protected-copy, and sensitive-expiry totals stay on each device for a rolling 13 months and can be cleared independently; they never sync, export, or enter diagnostics | Receipt schema, atomicity, retention, clear, and UI tests |
| Guided history import | `ClipImporter`, `ClipMigrationCoordinator`, macOS import views | Maccy archives and CSV are previewed before writing; protected and malformed rows are skipped, accepted rows deduplicate atomically, cancellation leaves a consistent store, and the final summary contains counts only | Import parser, source-safety, batch, cancellation, and macOS UI tests |
| MCP client authorization | `MCPClientGrant`, `MCPContextPack`, `MCPToolRunner`, MCP Settings UI | Every local AI client needs an expiring, revocable grant with explicit board/time context and independent read/write permission; authorization and SQL filters fail closed, sensitive clips stay excluded, and the ledger is content-free | Grant/config, scope, tool-runner, protocol, CLI, and macOS UI tests |
| Consented activation funnel | `ActivationTracker`, `TelemetryConsent`, onboarding milestone calls | Before diagnostics consent, only a closed set of content-free first-value dates stays locally; after opt-in, Gancho emits one coarse aggregate snapshot rather than replaying actions | Activation tracker, telemetry lifecycle, and onboarding UI tests |
| Main history search | `ClipSearch`, `GRDBClipboardStore`, prefix-index migrations | Main search offers FTS exact, fuzzy, and regex modes; dedicated short-prefix indexes keep fuzzy recall responsive while typing | Search tests plus the 100k cold/warm performance harness |
| Semantic retrieval | `EmbeddingIndex`, `ClipboardQAService`, `BoardSuggestionService` | A local 512-dimension embedding index powers Ask your clipboard and board suggestions; it is not the main history-search path | Semantic-search, Q&A, and board-suggestion tests |
| Pre-model secret safety | `ModelInputSanitizer`, `PromptCatalog` | Key-, token-, card-, and private-key-shaped text is deterministically redacted before Gancho's on-device model sees it; prompts are versioned and evaluated separately | Sanitizer, prompt-catalog, and opt-in live prompt evaluation tests |
| Curated Spotlight index | `LibrarySpotlightService`, `CoreSpotlightIndexer` | Only snippets and pinned clips are donated to Spotlight; raw history, sensitive or masked kinds, and expiring clips are excluded, and disabling the setting removes Gancho's domain | Spotlight service tests plus macOS Settings UI evidence |
| Board identities | `Pinboard.colorHex`, `Pinboard.emoji`, `BoardIdentityEditor`, `BoardIdentityMark` | Boards can use a fixed accessible color and an optional emoji identity across Mac, iPhone, and iPad; changes use the durable board mutation and sync path | Board identity unit tests plus macOS and iOS UI persistence tests |
| Rich clipboard formats | `NSPasteboardReader`, `PasteBackService` | macOS captures RTF or HTML with a plain-text companion and can paste the stored rich representation back; plain-text paste is an explicit alternative | Pasteboard-fidelity and paste-back tests |
| Paste stack | `PasteStackStrip`, `PasteStack` | Clips are queued from the panel, visible in its footer strip, and pasted with the configurable stack shortcut | Paste-stack unit tests and macOS UI coverage |
| Batch panel workflow | `PanelSelection`, `DeletionCoordinator`, `ClipDragPayload` | macOS supports range or discontiguous selection, batch stack/board/delete actions with shared Undo, and a de-duplicated multi-file drag when every selected clip is a safe file reference | Selection, deletion, drag-payload, and focused macOS UI tests |
| Panel display preferences | `PanelController`, `PanelDisplayPreferences`, macOS General Settings | The Mac panel is edge-resizable, offers three size shortcuts, remembers manual geometry, and scales semantic text with a persistent three-level preference | Display-preference unit tests plus focused macOS UI persistence smoke |
| Package topology | `Packages/GanchoKit/Package.swift` | One package exposes eight libraries plus the `gancho` CLI | `ReleaseMetadataTests`, `scripts/check-product-truth.sh` |
| Current direct download | GitHub release `v0.8.0` and its published DMG | v0.8.0 is Developer ID-signed, notarized, stapled, checksum-matched, Gatekeeper-accepted, and the first artifact to embed a production CloudKit/Push provisioning profile, so it is sync-capable; a fresh Free install still runs local-only because sync is Pro-gated and secure direct activation is not yet available | Version sync, mounted-DMG QA, profile validation, and explicit release-copy assertions |
| Next direct-download artifact gate | Production entitlements, Developer ID profile validator, release workflow | A sync-capable DMG must embed a non-expired production CloudKit/Push profile whose capabilities match the final signed app; the tag fails if signing, notarization, profile validation, artifact QA, or Sparkle signing is missing | `validate-macos-release-profile.sh`, `qa-release.sh`, and signed artifact checks |
| Direct-download sync entitlement | `SyncEnablement`, direct license activation, public release configuration | Sync requires Pro. A profile-backed public build remains local-only for a fresh Free install until a secure direct activation path exists or the product explicitly changes that entitlement policy | Sync enablement truth table, clean-install activation, and packaged-secret checks |
| Cross-device confidence | Sync tests and completed development-build hardware smoke | The source sync path has passed real-device smoke; repeat the full two-device matrix with a usable entitlement on the signed, profile-backed direct release candidate before promising sync | Tests plus the manual release checklist |

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
