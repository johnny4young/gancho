# design-sync notes — gancho

## Shape

This repo is **outside the /design-sync converter's envelope**: it is Swift/SwiftUI,
with no `package.json`, no `dist/`, and no Storybook. There is nothing to esbuild
into `_ds_bundle.js`.

The Claude Design project (`a3149174-e33c-4d4c-82fa-0f7e03241e99`, "gancho Design
System") is instead a **hand-authored web mirror** of the SwiftUI design system,
built over several sessions. Syncing means *reading the Swift sources and updating
the mirror by hand* — the converter scripts are not used and should not be run here.

`_build-notes.md` **inside the Design project** is the running log; read it first.

## Where truth lives

| Concern | Swift source |
| --- | --- |
| Spacing / radius / stroke / font sizes | `Packages/GanchoKit/Sources/GanchoDesign/GanchoTokens.swift` |
| Accent, status, syntax + editor colors | `.../GanchoDesign/GanchoColors.swift` |
| Kind tints, ClipCard, SearchField, ActionButton, glass surface | `.../GanchoDesign/Components.swift` |
| Board palette + emoji vocabulary | `.../GanchoDesign/BoardColors.swift` |
| Board appearance editor | `.../GanchoDesign/BoardIdentityEditor.swift` |
| The 17 clip kinds | `.../GanchoKit/ClipContentKind.swift` |
| Filter buckets | `.../GanchoAppCore/ClipKindFilter.swift` |
| Retention windows | `.../GanchoKit/RetentionPolicy.swift` |
| Paywall copy + gatekeeper + activation results | `.../GanchoKit/PaywallGatekeeper.swift` |
| macOS surfaces | `Apps/GanchoMac/` |
| iOS surfaces | `Apps/GanchoiOS/` |

## Verification helpers

Two throwaway scripts were used in the 2026-08-27 sync and are worth recreating:

- **token check** — for every hex written into `tokens/colors.css`, grep the Swift for
  either `#RRGGBB` or the `0xRR, 0xGG, 0xBB` triple form. The neutral gray ramp and the
  glass values legitimately have no Swift match: the app uses OS materials
  (`.background.secondary`, `.quaternary`, `.separator`), not hard-coded grays.
- **bundle check** — every `<Icon name="…">` must exist in `Icon.jsx`; every `var(--token)`
  must be defined in the token files; every `*.card.html` and `ui_kits/**/*.html` must open
  with a well-formed `<!-- @dsCard group="…" viewport="WxH" name="…" -->` line.
  `SettingsWindow.jsx` is a module, not a card — exclude non-`.html` files from that rule.

## Gotchas paid for in real time

- Only **capitalized** exports land on `window.GanchoDesignSystem_a31491`. `resolveKind`,
  `maskedPreview` and `boardColorForSeed` are bundle-internal; a card that destructures
  them gets `undefined`.
- `_ds_bundle.js` recompiles at the **turn boundary**. A card referencing a
  brand-new component (e.g. `BoardMark`) renders blank until the project is next opened.
  Not a bug — don't "fix" it.
- `SyncStatus` takes `"upToDate"`, not `"synced"`. Check a component's `.d.ts` before
  using it; a wrong prop renders silently wrong.
- The CDN `<script>` tags in cards carry **integrity hashes** — copy them verbatim from an
  existing card rather than retyping a version.
- `DesignSync(finalize_plan)` requires `deletes`, even when empty.
- `get_file` is the only way to read remote content, and there is no download-to-disk —
  editing an existing remote file means reconstructing it locally. Prefer surgical,
  file-scoped changes over sweeping rewrites.

## The standing divergence to re-check every sync

The design system once gave all **17 clip kinds** their own hue. The app never adopted it:
`kindTint(for:)` returns **seven** buckets. The tokens now carry the shipped values and the
rich palette is kept as a clearly-marked proposal. This was confirmed intentional —
`ClipKindFilter` uses the very same buckets. **If `kindTint(for:)` ever changes, this is the
first thing to re-sync.**
