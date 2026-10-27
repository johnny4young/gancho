# Deployment floor — minimum OS

Gancho's source floor is `macOS 26 / iOS 26`, and the Mac app builds for Apple
Silicon only (`ARCHS[sdk=macosx*]: arm64` in `project.yml`; platforms in
`Packages/GanchoKit/Package.swift`). The published v0.10.2 DMG predates this:
it is universal and requires macOS 15.4. Macs on Intel or macOS 15 keep
v0.10.2 and are not offered later updates.

## How the floor is enforced

- The deployment target itself is the gate: any newer API used without an
  availability guard is a compile error in every regular build.
- The app's `LSMinimumSystemVersion` and its single arm64 slice stop it from
  launching anywhere else.
- Sparkle's `generate_appcast` reads both from the bundle and writes
  `sparkle:minimumSystemVersion` and `sparkle:hardwareRequirements` into the
  new item. `scripts/generate-appcast.sh` fails the release if either is
  missing, so an older Mac is never offered an update it cannot open.
- The Homebrew cask describes the published DMG. Once the published release
  notes state a macOS 26 floor, `ReleaseMetadataTests` and
  `scripts/check-product-truth.sh` require `depends_on macos: :tahoe` and
  `depends_on arch: :arm64`, so the first release at this floor cannot ship the
  old requirements.

## Apple Intelligence

The FoundationModels tier and Liquid Glass need no availability guards at this
floor. `IntelligenceCapability` (GanchoAI) reports only whether Apple
Intelligence is ready (`available` / `modelUnavailable`); the
`-simulate-model-unavailable` launch argument forces the second answer so UI
tests and snapshots do not depend on the host.
