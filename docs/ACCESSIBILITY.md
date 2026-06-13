# Accessibility

In a clipboard manager, keyboard speed and screen-reader support are the
product, not extras. This file records the quality bar and the manual smoke
that complements the automated checks.

## Guarantees (enforced in code/tests)

- **Keyboard-only flow**: open panel (⇧⌘V) → type-to-search → ↑↓ → Enter
  pastes (⌥Enter plain, ⌘1–9 direct) → Space previews → Esc closes. Covered
  by `GanchoUITests` (`make test-ui`).
- **VoiceOver**: rows combine into one element reading "kind, preview";
  masked previews stay masked for VO too; the menu-bar icon announces the
  capture state; no element ships with a bare "button" label.
- **Display settings**: Reduce Transparency AND Increase Contrast both swap
  Liquid Glass for a solid surface (`GanchoSurface`); fonts are system text
  styles, so Dynamic Type scales everything; no motion-based reveals exist
  (nothing to gate behind Reduce Motion yet — re-check when animations land).
- Accessibility identifiers are stable kebab-case and never localized.

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
