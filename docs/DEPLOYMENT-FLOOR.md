# Deployment floor — lowering the minimum OS

Gancho currently ships `macOS 26 / iOS 26` (`Packages/GanchoKit/Package.swift`
and `project.yml`). That is the newest OS only — roughly half of active Macs
in a release's first year — while competitors (Clipso runs from macOS 13,
Paste covers older releases) reach the whole installed base. Lowering the floor
is the cheapest lever on the addressable market.

## What blocks a lower floor (measured)

`scripts/check-deployment-floor.sh` probes a candidate floor by temporarily
rewriting the manifest's `platforms:` and building **each package target
separately** (a plain `swift build` stops at the first broken module and hides
the rest). It only reports; it never edits source.

```
scripts/check-deployment-floor.sh                 # macOS 15 / iOS 18 (default)
scripts/check-deployment-floor.sh --macos 14 --ios 17
```

Inventory at the **macOS 15 / iOS 18** floor (July 2026):

| Target | Status | What blocks it |
| --- | --- | --- |
| ClipboardCore | ✗ | `NSPasteboard.accessBehavior` (macOS **15.4**) — trivially gated |
| GanchoKit | ✅ | Store, sync fields, FTS, semantic — **already floor-clean** |
| GanchoSync | ✅ | CKSyncEngine is macOS 14+ |
| GanchoTelemetry | ✅ | — |
| GanchoAI | ✗ | ~All errors are FoundationModels (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`) — macOS 26 |
| GanchoAppCore | ✗ | Only via its GanchoAI dependency |
| GanchoDesign | ✗ | `glassEffect(_:in:)` (Liquid Glass) — macOS 26 |

**The core (store/sync/search) already supports the low floor.** Only two real
boundaries stand between Gancho and macOS 15 / iOS 18:

1. **FoundationModels** (GanchoAI) — the on-device AI tier. The fallback
   already exists (`HeuristicAnnotator`, and every AI surface degrades). The
   fix is one `#if canImport(FoundationModels)` + `@available` boundary so the
   tier compiles out below OS 26 and the heuristic path takes over. Pitch: "AI
   is a bonus on OS 26, not a requirement."
2. **`glassEffect`** (GanchoDesign) — one Liquid Glass call. Wrap in an
   availability-gated view modifier with a material fallback below OS 26.

`accessBehavior` (macOS 15.4) is a one-line `if #available`.

## Recommended floor: macOS 15 / iOS 18

Modern SwiftUI is essentially complete at 15/18, it covers ~85%+ of the market,
and the two blockers above are bounded, well-understood work with fallbacks
that already exist. This is the COMP-01 decision the strategic analysis calls
the single cheapest market lever.

The app shells (`project.yml` `deploymentTarget`) need their own probe once the
package boundaries land; this script covers the package only.
