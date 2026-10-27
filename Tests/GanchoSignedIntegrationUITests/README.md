# Hosted native handoff validation

The `GanchoSignedIntegration` scheme exercises the real accessory application,
its external menu-bar helper, and a separate AppKit paste receiver. Run it
through `.github/workflows/signed-handoff.yml` on disposable GitHub-hosted
machines. The test driver, permission preparation, and signing script reject
ordinary local execution.

The workflow runs both native architectures by default: `arm64` on `macos-26`
and `x86_64` on `macos-26-intel`, using Xcode 26.6. A manual dispatch can select
one architecture for diagnosis. Each architecture keeps its own artifacts.
Signing uses the existing repository certificate in a temporary hosted keychain.
Signed jobs run for this repository's branches; fork PRs retain the independent
ordinary build and startup checks without access to the signing certificate.

## Required cases

Each architecture must report exactly four passing cases, with zero failures,
skips, or expected failures:

- Double-click a real history row and receive exactly one paste in the other app.
- Press Return in the real panel and receive exactly one paste in the other app.
- Kill the exact owner process, observe its helper exit, then relaunch with new
  owner and helper PIDs and exercise the actual Quit command.
- Open and close the actual Settings window across two launches, keeping the
  owner and helper resident until the actual Quit command.

Paste receipts require the expected synthetic content and self-write marker,
one command-key down/up pair, foreground restoration, and no duplicate delivery
during the quiet period. Receipt metadata contains only counts and booleans.
Kept recordings show synthetic fixtures on disposable VMs, with no access to the
maintainer's desktop or clipboard.

## Isolation and native input

Every Gancho launch uses an ephemeral store, a fresh preferences suite, paused
capture with an empty reader, and disabled telemetry. The actual clipboard writer
and keyboard-event poster remain enabled on the disposable VM. The driver checks
the exact application path, PID, and actual isolation arguments before interacting
with its helper. It never launches the maintainer's installed application.

Only this dedicated UI-test driver disables App Sandbox. AppKit otherwise ignores
its `NSWorkspace` launch arguments. A signed-entitlement preflight must confirm
that setting before execution; product entitlements are unchanged. Gancho, its
helper, and the receiver must pass real Apple identity and hardened-runtime checks.

Native pointer events require real control geometry, and AppKit activation must
put the exact receiver PID in front with its editor focused. Application-control
queries inspect windows and their descendants, avoiding unrelated system-menu
inspection. An accessibility read failure cannot satisfy panel absence.

Paste fixtures wait for a DEBUG-only, content-free readiness marker in their
unique isolated preferences suite before exercising the helper. This keeps
background seeding out of the first panel-open interaction. The helper still
opens the real panel for the first time, and the driver still requires all
three rows and the original paste, focus, timing, and no-repeat assertions.

Before the suite, the workflow launches the signed app once and logs how long
its fixtures took. A new VM's first launch of a freshly signed app pays a
one-time system assessment that, on Intel runners, outlasted the 30 s wait and
failed whichever test ran first; the warm-up quits every Gancho process, so the
clean-host check still holds.

## Evidence and related checks

Artifacts retain the full result bundle, test summary, recordings, build/test logs,
and signature/driver metadata for 14 days. Certificate files, keychains, and app
binaries are not uploaded. Temporary signing material is removed on success or
failure. These are integration checks, not notarization or release publication.

The separate `stability-smoke.yml` workflow requires eleven startup, onboarding,
Settings, and migration regressions on each of macOS 15/Xcode 26.3 and
macOS 26/Xcode 26.6. Both workflows run on PRs and relevant `main` updates.
KeyboardShortcuts remains pinned to the unmodified 3.0.1 release.

Disk image packaging and
read-only inspection prefer the supported `diskutil image` commands when available,
with `hdiutil` compatibility on older systems; inspection volumes use `diskutil eject`.
