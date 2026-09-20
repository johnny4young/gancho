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
- **Display settings**: Reduce Transparency AND Increase Contrast both swap
  Liquid Glass for a solid surface (`GanchoSurface`). System text styles are
  used broadly, but fixed-size labels and the panel text-size override mean
  this is not a guarantee that every element follows system Dynamic Type.
- Accessibility identifiers are stable kebab-case and never localized.

## Validation limits

Accessibility-tree assertions do not establish that every control is usable
with VoiceOver. Run the manual flow below on the identified release candidate.
The panel currently uses animated transitions and repeating progress symbols;
there is no app-level Reduce Motion handling yet. Include Reduce Motion,
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
5. Toggle Reduce Transparency in System Settings → confirm the panel
   re-renders solid without restart.

Record date + macOS build of the last run in the release checklist.
