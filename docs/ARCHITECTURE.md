# Gancho — Architecture

The product source of truth (vision, market, pricing, backlog with acceptance
criteria) is the Notion page “Gancho — Smart Clipboard”. This document records
the engineering decisions the code must respect.

## The two worlds

| | History | Library |
| --- | --- | --- |
| Lifetime | Ephemeral (retention/expiry rules) | Permanent (never expires) |
| Entry | Automatic capture (macOS) / intent-based (iOS) | Promoted from a clip, or authored |
| Contents | Everything you copy | Snippets, templates, pins |

The bridge: *promote* a clip → snippet in one gesture (backlog E13.2).

## Layers

```
Apps (thin shells, @MainActor by default)
  └── GanchoDesign   tokens → components (no bare numbers in UI code)
  └── GanchoKit      ClipItem, ClipContentKind, ClipboardStore, SyncEngine
  └── ClipboardCore  MacPasteboardMonitor (poll changeCount) · iOS intent capture
  └── GanchoAI       RuleClassifier (tier 0) → Foundation Models (tier 1) → LanguageModel protocol (tier 2)
```

Engine-room packages are nonisolated + `Sendable`; isolation is opt-in per
type (e.g. `MacPasteboardMonitor` is `@MainActor` because it touches AppKit).

## Decisions (with rationale)

1. **Minimum macOS 26 / iOS 26.** No beta SDKs on work machines; SDK-27 APIs
   go behind `#available`. Betas run only on cloud CI, never locally.
2. **GRDB (SQLite) + FTS5 for storage, CKSyncEngine for sync.** SwiftData +
   CloudKit is rejected for v1 (production evidence 2025–2026: schema lock-in,
   silent sync failures). Encrypted fields (`encryptedValues`) for content.
   Validated by spikes S0.2/S0.3 before any schema is promoted.
3. **`SyncEngine` is a hard boundary.** The core never imports CloudKit.
   A future LAN-P2P or self-hosted backend is a new implementation, not a
   rewrite.
4. **Capture is privacy-first, before features.** Sensitive pasteboard types
   (`org.nspasteboard.*`) veto capture before any content is read. On iOS
   there are NO background pasteboard reads — share extension, UIPasteControl,
   and foreground prompts only. `NSPasteboard.accessBehavior` + detect APIs
   integrate after spike S0.1 documents the macOS privacy-flag matrix.
5. **Tier-0 intelligence is deterministic and universal.** `RuleClassifier`
   runs on every device with zero network. Foundation Models (tier 1) and the
   `LanguageModel` protocol (tier 2: on-device → PCC → external, opt-in per
   action) build on top; AI never gates core functionality.
6. **Dedupe by content hash.** SHA-256(content + kind) — re-copy moves the
   item to the top; sync uses the same key to avoid ping-pong duplicates.
7. **Tokens, not numbers.** UI code consumes `GanchoTokens`; Liquid Glass is
   the native design language (the opt-out dies with the SDK-27 generation).

## Inherited from vitrine

`project.yml` (XcodeGen + approachable concurrency), `Makefile`, `.swift-format`,
CI shape (toolchain recording, SPM cache, weekly drift canary), release
discipline to adopt later (version guard tag ↔ MARKETING_VERSION ↔ release
notes, notarized DMG + Sparkle + Homebrew cask behind a compile-time flag for
a future direct-download channel).

## Next steps (ordered)

Spikes S0.1–S0.5 (see Notion backlog) → MVP epics E1/E3/E5/E6 (Mac core) →
E2/E7 (iOS companion) → E4 (sync) → E8/E9/E10/E11 (monetization, privacy
center, growth). Library (E13) lands in v1.1 on top of the same store/sync.
