# Accessibility

In a clipboard manager, keyboard speed and screen-reader support are the
product, not extras. This file records the quality bar and the manual smoke
that complements the automated checks.

## Implemented behavior and automated coverage

- **Keyboard-only flow**: open panel (⇧⌘V) → type-to-search → ↑↓ → Enter
  pastes (⌥Enter plain, ⌘1–9 direct) → ⌘Y previews → Esc closes. Covered
  by `GanchoUITests` (`make test-ui`).
- **VoiceOver**: rows combine into one element reading "kind, preview";
  masked previews stay masked for VO too; the menu-bar icon announces the
  capture state; no element ships with a bare "button" label.
- **Display settings**: the panel is solid by default. With Settings ›
  General › Translucent background on, Reduce Transparency AND Increase
  Contrast both swap Liquid Glass for a solid surface (`GanchoSurface`).
  System text styles are used broadly, but fixed-size labels and the panel text-size override mean
  this is not a guarantee that every element follows system Dynamic Type.
- Accessibility identifiers are stable kebab-case and never localized.
- Settings section buttons expose their selected state. Board-picker rows are
  native buttons while the search field retains arrow navigation.
- Compact icon actions share a labeled hit target, scaled with panel text on
  macOS and sized for touch on iOS. Opaque custom accent fills resolve a black
  or white foreground from their luminance instead of always forcing white.
- Snippet-fill fields scroll independently from Insert and Cancel. Panel
  commands are inactive while a dialog owns the keyboard. The iOS curation
  suggestion reserves space above the history toolbar instead of covering it.

The `app-quality.yml` hosted gate requires fifteen interface regressions with
zero failures or skips, including English/light and Spanish/dark Settings,
large panel text, gallery/list previews, live Library curation, draft-preserving
navigation, and a twenty-field template with reachable actions. The iOS reuse
gate requires both reuse interactions to pass without skips and checks that
its suggestion does not intersect the Paste control.

## Validation limits

Accessibility-tree assertions do not establish that every control is usable
with VoiceOver. Run the manual flow below on the identified release candidate.
Panel transitions honor Reduce Motion through `GanchoMotion`
(`quick`/`smooth`/`replace(reduceMotion:)`); repeating progress symbols still
animate. Include Reduce Motion,
larger text, contrast, small windows, Library cards and saved filters in manual
acceptance. Space toggles a focused filter chip; in the search field it types a
space rather than opening a preview.

## Manual VoiceOver smoke (run per release, ~5 minutes)

1. Enable VoiceOver (⌘F5). Open the panel with ⇧⌘V.
2. VO-→ through: search field (announces prompt), first rows (announce
   "kind, preview" — confirm a masked secret reads bullets, not content).
3. Activate a row with VO-Space — confirm the paste lands and the panel
   closes.
4. Open the menu bar item — confirm the status announcement matches the
   actual state (capturing / paused / private mode).
5. Turn on Settings › General › Translucent background, then toggle Reduce
   Transparency in System Settings → confirm the panel re-renders solid
   without restart.

Record date + macOS build of the last run in the release checklist.
