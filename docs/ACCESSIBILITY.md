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
- Settings section buttons expose their selected state, and keyboard focus
  follows the selected section, so only one row ever shows a focus ring. Board-picker rows are
  native buttons while the search field retains arrow navigation.
- Compact icon actions share a labeled hit target, scaled with panel text on
  macOS and sized for touch on iOS. Opaque custom accent fills resolve a black
  or white foreground from their luminance instead of always forcing white;
  the brand green takes its dark ink.
- **Contrast**: accent and status text reach WCAG AA (4.5:1) on every surface
  it sits on in light and dark mode, whatever accent colour the system uses;
  `ContrastTokenTests` proves each pair, including hover and pressed fills.
- **Focus**: Gancho buttons, dock actions and filter chips draw a 2 pt ring in
  the accent ink outside the control, distinct from the selected fill.
- Image rows announce their size and format ("image, 1200 × 800 · PNG");
  masked rows still read only as a mask. The active board chip's label carries
  its clip count, and the first-run lesson reads each shortcut with its keys.
- Snippet-fill fields scroll independently from Insert and Cancel. Panel
  commands are inactive while a dialog owns the keyboard. The iOS curation
  suggestion reserves space above the history toolbar instead of covering it.

The required `Build macOS + iOS apps` job in `ci.yml` runs the interface
regressions with zero failures or skips, including Settings navigation, the
board picker, live Library curation, draft-preserving navigation, and a
twenty-field template with reachable actions at large text. The iOS reuse check
runs after each merge to `main` and on the weekly schedule, and checks that its
suggestion does not intersect the Paste control. Spanish/dark Settings, panel
captures and the remaining interactions run in the weekly UI workflow.

## Validation limits

Accessibility-tree assertions do not establish that every control is usable
with VoiceOver. Run the manual flow below on the identified release candidate.
Transitions honor Reduce Motion through `GanchoMotion`: settle animations
become instant, arrivals and departures a 100 ms fade, and pressed buttons stop
scaling; repeating progress symbols still animate. Include Reduce Motion,
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
