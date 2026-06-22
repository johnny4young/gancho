# Localization

Gancho is bilingual (English source, Spanish) from the first real string.
The gate is automated: `LocalizationTests` fails the suite when a key lacks
a translated Spanish value, placeholders drift, or user-facing prose appears
outside a String Catalog.

## Adding a string

1. Write the view code with the English prose as the literal:
   `Text("Save clipboard")` or `String(localized: "Has \(detail) — not read yet")`.
2. Add the key — with a translated `es` value — to **every catalog whose
   bundle shows the string** (see [Which catalog](#which-catalog)).
   Interpolations become `%@`/`%d` placeholders — keep them identical in both
   languages (the gate checks).
3. Run `make test`. The hardcoded-prose sweep confirms the literal is in the
   catalog; the placeholder check confirms formats align.

Rules:
- Product names ("Gancho") and technical commands are NOT translated.
- Accessibility identifiers stay kebab-case and are never localized.
- Pluralization uses String Catalog variants — never hand-rolled `count == 1`
  branches.

## Which catalog

Each bundle resolves its strings from its OWN `Localizable.xcstrings`, so a
string shown in N bundles must be translated in all N. The gate enforces this
per bundle, keyed off the source file's directory under `Apps/`:

| Source under `Apps/`                   | Catalog(s) the key must land in    |
| -------------------------------------- | ---------------------------------- |
| `GanchoMac/`                           | `GanchoMac`                        |
| `GanchoiOS/`                           | `GanchoiOS`                        |
| `GanchoWidgets/`                       | `GanchoWidgets`                    |
| `GanchoKeyboard/`                      | `GanchoKeyboard`                   |
| `GanchoShared/`                        | **`GanchoiOS` AND `GanchoWidgets`** |
| `GanchoShare/`, `GanchoMenuBarHelper/` | any catalog (no dedicated bundle)  |

`GanchoShared` compiles into the iOS app, the widget AND the keyboard, but only
the app and widget vend its App Intents to users — so those two catalogs are
required, not the keyboard's. Translating a shared string in only one catalog is
the exact bug that shipped the Save Clipboard intent in English on iOS while the
widget already had it localized.

## Forcing a language (screenshots, smoke runs)

Launch with explicit AppleLanguages, no system change needed:

```bash
open Gancho.app --args -AppleLanguages '(es)'
xcrun simctl launch booted com.johnny4young.gancho.GanchoiOS -AppleLanguages '(es)'
```
