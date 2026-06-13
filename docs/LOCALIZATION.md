# Localization

Gancho is bilingual (English source, Spanish) from the first real string.
The gate is automated: `LocalizationTests` fails the suite when a key lacks
a translated Spanish value, placeholders drift, or user-facing prose appears
outside a String Catalog.

## Adding a string

1. Write the view code with the English prose as the literal:
   `Text("Save clipboard")` or `String(localized: "Has \(detail) — not read yet")`.
2. Add the key to the app's `Localizable.xcstrings` with a translated `es`
   value. Interpolations become `%@`/`%d` placeholders — keep them identical
   in both languages (the gate checks).
3. Run `make test`. The hardcoded-prose sweep confirms the literal is in the
   catalog; the placeholder check confirms formats align.

Rules:
- Product names ("Gancho") and technical commands are NOT translated.
- Accessibility identifiers stay kebab-case and are never localized.
- Pluralization uses String Catalog variants — never hand-rolled `count == 1`
  branches.

## Forcing a language (screenshots, smoke runs)

Launch with explicit AppleLanguages, no system change needed:

```bash
open Gancho.app --args -AppleLanguages '(es)'
xcrun simctl launch booted com.johnny4young.gancho.GanchoiOS -AppleLanguages '(es)'
```
