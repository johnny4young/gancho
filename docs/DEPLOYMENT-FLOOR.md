# Deployment floor — minimum OS

Gancho's source floor is `macOS 15.4 / iOS 26` (`Packages/GanchoKit/Package.swift`
and `project.yml`). The macOS floor dropped from 26 to 15.4 in August 2026
after a measured probe showed the entire package stack and every macOS app
shell compile at 15.4 with a small set of availability gates. The published
direct download still requires macOS 26 until the first Sequoia-validated
release ships — the website advertises that released floor, not this one.

## How the floor is enforced

The deployment target itself is the gate: with `macOS: "15.4"` in the build
settings, any use of a newer API without an availability guard is a compile
error in every regular build — CI cannot miss a floor regression. There is no
separate floor job to keep green.

## What macOS 26 still gates (by design)

| Capability | Below macOS 26 | Gate |
| --- | --- | --- |
| `FoundationModels` tier — smarter titles, Smart Paste rewrites and Translate, Ask your clipboard | Deterministic fallbacks (heuristic titles; PII redaction stays; Ask hidden) | `@available` on `FoundationModelAnnotator`; `guard #available` inside `SmartPasteService` / `ClipboardQAService`; `IntelligenceCapability` |
| Liquid Glass (`glassEffect`) | The same opaque-material branch accessibility already uses | availability branch in `GanchoSurface` |

`IntelligenceCapability` (GanchoAI) is the one shared interpretation of "can
the model tier run here": `available` / `requiresMacOS26` /
`modelUnavailable`. The Intelligence screen shows the honest reason, and the
`-simulate-sequoia-capabilities` launch argument forces the pre-26 answer so
`IntelligenceCapabilityUITests` covers the floor on any host.

`NSPasteboard.accessBehavior` (macOS 15.4) is why the floor is 15.4 rather
than 15.0.

## Probing a lower floor

`scripts/check-deployment-floor.sh` probes a candidate floor by temporarily
rewriting the package manifest's `platforms:` and building **each package
target separately** (a plain `swift build` stops at the first broken module
and hides the rest). It only reports; it never edits source.

```
scripts/check-deployment-floor.sh --macos 15    # 15.0: accessBehavior is the only blocker
scripts/check-deployment-floor.sh --macos 14
```

The command runs SwiftPM for the host macOS destination only. App shells and
iOS destinations need their own Xcode build probe before any further
deployment decision; the iOS floor (26) has not been probed below 26.

## Runtime evidence

Compiling at the floor is necessary, not sufficient. Before a release claims a
floor, the release checklist requires capture, paste-back, storage, the
menu-bar agent, panel rendering without glass, licensing, and update smoke on
real hardware running the oldest supported macOS.
