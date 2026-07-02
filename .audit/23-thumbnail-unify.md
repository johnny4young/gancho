# 23 — ClipThumbnailStore unification (PR-J, partial; A3-1.15/A3-2.7/F-1.3)

Date: 2026-07-02 · Branch: `claude/gancho-engineering-audit-byfy24`

## What was unified

The two near-duplicate per-app thumbnail caches (`Apps/GanchoMac/ClipThumbnailStore.swift`,
`Apps/GanchoiOS/ClipThumbnailStore.swift` — ~60 lines each, same `[UUID: Image]` cache,
same FIFO-64 cap, same ImageIO downsample incantation) are now ONE implementation:

- **New:** `Packages/GanchoKit/Sources/GanchoDesign/ClipThumbnailStore.swift` —
  `@Observable @MainActor public final class ClipThumbnailStore`: id-keyed
  `SwiftUI.Image` cache, in-flight dedupe, FIFO cap, and the single ImageIO
  downsample (`thumbnailPNGData(from:maxPixel:)`).
- **Shrunk:** both app `ClipThumbnailStore.swift` files are now a `typealias` to the
  shared type plus one `convenience init` that bakes in that platform's historical
  policy (see below). ~30 lines each, zero logic.
- **New test:** `Packages/GanchoKit/Tests/GanchoDesignTests/ClipThumbnailStoreTests.swift`
  — load gating (non-image / sensitive), idempotence, FIFO eviction, both sensitive
  policies, and the downsampler (valid PNG in → data out; junk → nil).

## Where the shared type lives, and why (project.yml reasoning)

`GanchoDesign` (in the GanchoKit package), exactly as PR-J prescribed:

- `project.yml` shows **both** app targets depend on the `GanchoDesign` product
  (Gancho: lines ~94-101; GanchoiOS: ~252-260), as does the keyboard extension —
  the future consumer of the same cache.
- `GanchoDesign` already depends on `GanchoKit` (`Package.swift:73`), so the shared
  type can take `ClipItem` directly, matching the existing view-facing surface.
- `Apps/GanchoShared` was rejected: per project.yml it compiles into the iOS app,
  widgets, and keyboard only — **not** the macOS app.
- **project.yml impact: none.** The new file lands inside an existing SwiftPM target
  (globbed by the package, not the project spec); the two app files keep their paths
  inside already-globbed source directories; the test lands in the existing
  `GanchoDesignTests` target. No `make project` spec change needed.

## Call-site preservation (all four verified by grep; zero edits outside the 2 files)

| Call site | Surface | How it's preserved |
| --- | --- | --- |
| `AppModel.swift:172` (macOS) | `ClipThumbnailStore(imageData: { id in … })` | mac wrapper adds `convenience init(imageData: @escaping @MainActor (UUID) async -> Data?)` |
| `GanchoiOSApp.swift:276` | `ClipThumbnailStore(store: store)` (`any ClipboardStore`) | iOS wrapper adds `convenience init(store: any ClipboardStore)` holding the identical `.binary` fetch closure |
| `PanelView.swift:670/1003/1369/1457` | `.ensureLoaded(item)` / `.cached(for: id)` | same names, now `public` on the shared type |
| `GanchoiOSApp.swift:1276/1279/1344/2099/2115` | same | same |

Name resolution: each app declares `typealias ClipThumbnailStore =
GanchoDesign.ClipThumbnailStore`; a module-local typealias shadows the imported name,
so unqualified references (including in `AppModel.swift`, which does not import
GanchoDesign) resolve unchanged. Member calls occur only in `PanelView.swift` and
`GanchoiOSApp.swift`, both of which already import GanchoDesign.

## Behavior preservation — platform policy stays at the edge

The two stores were NOT identical; every divergence is a designated-init parameter
(no defaults, so each platform's choice is explicit in its wrapper):

| Knob | macOS (unchanged) | iOS (unchanged) |
| --- | --- | --- |
| `maxCached` | 64 (FIFO, keyboard-proven pattern) | 64 |
| `maxPixel` | 480 | 480 |
| `skipsSensitiveClips` | **false** — macOS decodes sensitive images; the peek masks at display (`PanelView` `peekBody`) | **true** — sensitive clips never decoded |
| `decodePriority` | `.utility` | nil (runtime default) |
| data fetch | AppModel's full-blob `content(for:)` closure, verbatim | full-blob `content(for:)` via `.binary`, verbatim |

## Cross-platform Image decode

The detached decode task returns Sendable PNG `Data` (never a platform image —
the exact strict-concurrency rationale the old macOS file documented), produced by
one platform-free ImageIO path: `CGImageSourceCreateThumbnailAtIndex` (thumbnail-only
decode, EXIF transform, `maxPixel` cap, `kCGImageSourceShouldCache: false`) then PNG
via `CGImageDestinationCreateWithData` + `UTType.png`. Back on the main actor the
bytes are bridged: `#if canImport(AppKit)` → `NSImage(data:)`/`Image(nsImage:)`,
else `UIImage(data:)`/`Image(uiImage:)`.

Non-visible micro-deltas (pixel-identical output, accepted deliberately):

- macOS PNG encode moved from `NSBitmapImageRep` to `CGImageDestination` (platform-free),
  and its image source now passes `kCGImageSourceShouldCache: false` (iOS already did).
- iOS now round-trips the downsampled CGImage through PNG `Data` + `UIImage(data:)`
  instead of wrapping `UIImage(cgImage:)` directly — a few extra ms per thumbnail,
  off the main actor, bounded at 64 entries; buys the shared Sendable-`Data` handoff.
- The `imageData` closure type is `@MainActor`-isolated (its bodies immediately await
  the store, so no main-actor work of substance). Chosen because GanchoDesign compiles
  WITHOUT the apps' `SWIFT_APPROACHABLE_CONCURRENCY` setting; a same-actor call is
  unambiguously legal under plain Swift 6 strict concurrency, where a stored
  nonisolated async closure invoked from a `@MainActor` method is not.

## Deferred (needs edits outside this change's file allowlist)

1. **macOS should fetch `store.thumbnailData(for:)` instead of the full blob**
   (PR-J item 3, A3-2.7) — a real behavior/perf fix, but it edits `AppModel.swift:172`
   and changes which bytes are read; explicitly out of scope for this
   behavior-identical move.
2. **`ImageDownsampler` in GanchoKit** consolidating `BlobStore.makeThumbnailData`
   and `KeyboardModel`'s decode (PR-J item 1) — `thumbnailPNGData` on the shared type
   is the seed; hoisting it into GanchoKit and delegating BlobStore/keyboard to it
   touches `BlobStore.swift`/`KeyboardModel.swift`.
3. **Keyboard adoption** of the shared cache with `maxCached: 24` (PR-J item 2).
4. **Sensitive-policy convergence:** macOS passing `skipsSensitiveClips: true` would
   stop decoding sensitive thumbnails it only ever shows masked — a (good) behavior
   change to take deliberately, with the row/peek masking audit alongside.
