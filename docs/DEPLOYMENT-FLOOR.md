# Deployment floor — lowering the minimum OS

Gancho currently ships `macOS 26 / iOS 26` (`Packages/GanchoKit/Package.swift`
and `project.yml`). That limits compatibility to the newest OS generation;
lowering the floor would widen the addressable installed base.

## What blocks a lower floor (measured)

`scripts/check-deployment-floor.sh` probes a candidate floor by temporarily
rewriting the manifest's `platforms:` and building **each package target
separately** (a plain `swift build` stops at the first broken module and hides
the rest). It only reports; it never edits source.

```
scripts/check-deployment-floor.sh                 # macOS 15 (default)
scripts/check-deployment-floor.sh --macos 14
```

The command runs SwiftPM for the host macOS destination. It does not compile an
iOS destination, so iOS 18 remains a separate Xcode build probe before any
deployment decision.

### macOS 15 package inventory (July 2026)

| Target | Status | What blocks it |
| --- | --- | --- |
| ClipboardCore | ✗ | `NSPasteboard.accessBehavior` (macOS **15.4**) — trivially gated |
| GanchoKit | ✅ | Store, sync fields, FTS, semantic — **already floor-clean** |
| GanchoSync | ✅ | CKSyncEngine is macOS 14+ |
| GanchoTelemetry | ✅ | — |
| GanchoAI | ✗ | ~All errors are FoundationModels (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`) — macOS 26 |
| GanchoAppCore | ✗ | Only via its GanchoAI dependency |
| GanchoDesign | ✗ | `glassEffect(_:in:)` (Liquid Glass) — macOS 26 |

**The core (store/sync/search) already compiles at the measured macOS floor.**
Two substantial package boundaries and one ClipboardCore API block macOS 15:

1. **FoundationModels** (GanchoAI) — the on-device AI tier. The fallback
   already exists (`HeuristicAnnotator`, and every AI surface degrades). The
   fix is one `#if canImport(FoundationModels)` + `@available` boundary so the
   tier compiles out below OS 26 and the heuristic path takes over. Pitch: "AI
   is a bonus on OS 26, not a requirement."
2. **`glassEffect`** (GanchoDesign) — one Liquid Glass call. Wrap in an
   availability-gated view modifier with a material fallback below OS 26.

`accessBehavior` (macOS 15.4) is a one-line `if #available`.

## Candidate floor: macOS 15 / iOS 18

The macOS package blockers above are bounded and have existing fallback paths.
The iOS 18 half of this candidate is not established by the SwiftPM inventory
and must be validated with an iOS Xcode destination before changing either
manifest or project deployment targets.

The app shells (`project.yml` `deploymentTarget`) need their own probe once the
package boundaries land; this script covers the package only.
