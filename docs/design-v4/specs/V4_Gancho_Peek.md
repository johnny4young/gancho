# V4_Gancho_Peek — spec

- **Board:** `V4_Gancho_Peek.dc.html` (page title `Gancho peek and images v4`)
- **Canvas:** 2290 × 900 pt, background `#ECEDF0`, radius 12, padding 24 × 28, column gap 14.
- **What it shows:** three macOS peek states at Standard size (864 × 540): an image clip with its recognised text plus the new dominant colours and eyedropper; a code clip with the single searchable Transform popover open; and a colour clip's stage with formats and a contrast check.
- **Related Current boards:** `GanchoPanelActions_Current` (05 code clip · More actions expanded, 06 link clip · URL actions), `GanchoPanelColorImage_Current` (07 colour clip · swatch hero, Convert color; 08 Images filter · image hero, Copy text in the dock).
- **Catalog items realised here:** `GC-16`, `GC-V4-14`. `GC-11` is drawn here (Transform popover) but its catalog board is `V4_Gancho_Novel2` (see Coverage and Feasibility). Legacy `GC-13`, `GC-14`, `GC-15` are shipped and kept.
- **Appearance drawn:** light only. The board CSS defines `.panel.dark` variants, but no artboard uses them; dark is not specified by this board (see `GC-04` on MenuBarDark).

Shared component metrics (from the board CSS, used by all three frames):

| Element | Metrics |
|---|---|
| Panel | 864 × 540, bg `#F5F5F7`, radius 14, border 1 `rgba(0,0,0,.08)`, shadow `0 1 2 rgba(0,0,0,.08)` + `0 22 48 rgba(0,0,0,.22)`; body 13 pt `#1D1D1F` |
| List column | 440 wide, right border 1 `rgba(0,0,0,.08)` |
| Peek column | flexible (≈ 422), padding 12 × 14, gap 10 (image frame overrides gap 8) |
| Search bar | 44 high, padding 0 × 14, gap 8, bottom border; input 15 pt, placeholder `#8A8A8F` |
| Search-mode group | capsule, padding 2, gap 1, bg `rgba(29,29,31,.07)`; buttons 20 high, padding 0 × 7, 10.5 pt / 700; pressed = bg `#fff`, text `#1D1D1F`; unpressed = text `#5B5B61` |
| Meaning button | 24 high, padding 0 × 9, radius 999, bg `rgba(29,29,31,.07)`, 10.5 pt / 700 `#5B5B61`, icon + label |
| Toolbar | padding 6 × 12, gap 4, bottom border; board rail fades out over the last 22 pt; divider 1 × 14 `rgba(0,0,0,.14)`, margin 0 × 4 |
| Chip | 22 high, padding 0 × 7, gap 5, radius 999, bg `rgba(29,29,31,.07)`, 11 pt / 600 `#5B5B61`; pressed bg `#34C759` text `#0B2A14` / 700; glyph-only chip 22 × 22. Board swatch 9 × 9 radius 3 |
| Section header | padding 6 10 2, 10 pt / 700, tracking .06em, uppercase, `#5B5B61`; label left, count right |
| Rows | gap 3, padding 2 × 6; row 50 high, padding 0 × 8, gap 10, radius 10; selected bg `rgba(52,199,89,.14)` + left bar 3 wide (inset 8 top/bottom) `#34C759` radius 2 |
| Tile | 36 × 36, radius 8 |
| Row title / preview | 13 pt / 600; 12 pt `#5B5B61`; both single line, truncating |
| Row meta | source 10.5 pt `#6E6E73`; ⌘N key 16 high, padding 0 × 4, radius 5, bg `rgba(29,29,31,.08)`, 10 pt / 600 mono `#5B5B61` |
| Kind pill | 20 high, padding 0 × 8, gap 4, radius 999, 11 pt / 700, icon + kind name |
| Insight chip (`bch`) | 20 high, padding 0 × 7, gap 4, radius 999, bg `rgba(29,29,31,.07)`, 11 pt / 600 `#3A3A3F` |
| Hero card | padding 12 × 14, radius 14, bg `#fff`, border 1 `rgba(0,0,0,.08)` |
| Dock | gap 4, padding 4, radius 14, bg `rgba(29,29,31,.06)`, border 1 `rgba(0,0,0,.06)`, pinned to bottom; button 58 high, padding 7 × 2, gap 3, radius 10, 11 pt / 700, icon over label over key; key 10 pt / 500 mono, opacity .75; primary = flex 2, bg `#34C759` text `#0B2A14`; focused = inset ring 1.5 currentColor + bg `rgba(52,199,89,.18)` (defined, not used here) |
| Footer | 30 high, padding 0 × 10, gap 12, 11 pt `#5B5B61`, top border; capture pill bg `rgba(52,199,89,.16)` text `#1F7A3A` with 7 × 7 dot `#34C759`; key caps 16 high, min width 17, padding 0 × 3, radius 4, bg `rgba(29,29,31,.08)`, 9 pt / 700; trailing help icon button `aria-label` `Keyboard shortcuts (⌘/)` |

Token mapping where obvious: `#34C759` = `GanchoTokens.Palette.brandGreen` (light); `#FF3B30` = `Palette.danger`; `#FF9F0A` = `Palette.warning` / image kind tint; `#5856D6` code tint; `#5AC8FA` colour tint; `#32ADE6` URL tint (`Palette.kindTint(for:)`, `Packages/GanchoKit/Sources/GanchoDesign/Components.swift:104`); `#1F7A3A` green ink (cf. `SY-V4-3`); radius 14 = `Radius.lg`, 10 = `Radius.md`, 8 = `Radius.card`.

---

## Header strip (top of canvas)

- ID tags, left to right: `GC-11` (green tag), `GC-13`, `GC-14`, `GC-15`, `GC-16` (dark tags). Tag: 22 high, padding 0 × 9, radius 7, 11 pt / 800 mono; green = bg `#34C759` text `#0B2A14`; dark = bg `#1D1D1F` text `#fff`.
- Title (22 pt / 800): `Peek · images with their words, one Transform, and the colour hero`
- Subtitle (13 pt `#5B5B61`, max 860): `Left: an image clip — regions, per-line actions and Translate are already in v0.10.2; v4 adds dominant colours and an eyedropper. Middle: the single searchable Transform popover that merges three surfaces. Right: the colour clip's stage with formats and a contrast check.`
- Right-aligned: `Gancho · macOS · v4 · 864 × 540`

Context only (board chrome, not UI).

---

## Frame 1 — `GC-13` Image clip · text in image

Label above the frame: tag `GC-13` (green) + `Image clip · text in image` + small `kept, incl. Translate · colours · eyedropper`.

Realises: `GC-16` (Dominant chip, `Pick colour · I`, footer `I eyedropper`); kept layout of `GC-13/14/15`; also draws cross-board items `GC-01`, `GC-V4-2`, `GC-V4-3`, `GC-V4-4`, `GC-V5-3`, `GC-V4-1` (context, owned elsewhere).

### List column (440)

1. Search bar: magnifier icon (15), input `aria-label` `Search your clipboard`, placeholder `Search`; search-mode group (`aria-label` `Search mode`): `Fuzzy` (pressed), `Exact`, `Regex`; button `Meaning` (sparkle icon, unpressed).
2. Toolbar, board rail: chip `Images · 4` (pressed, icon), Favorites glyph chip (star, `#FF9F0A`, `aria-label` `Favorites`), `Work` (swatch `#2E70D1`), `Brand` (swatch `#F08C08`), glyph chip `aria-label` `New board…` (+). Divider. Filter rail: `All` (pressed, icon), glyph chips `Links` (`#32ADE6`), `Code` (`#5856D6`), `Colors` (`#5AC8FA`), `Images` (`#FF9F0A`), `Secrets` (`#FF3B30`), `All apps`, `Save filter` (no background).
3. Section header: `Today` · `4 images`.
4. Rows (all sample; tile = 36 × 36 `#52BCCF` with an 18 × 18 `#F39B3A` circle as a thumbnail stand-in):

| # | Title | Preview | Source · time | Key | State |
|---|---|---|---|---|---|
| 1 | `OCR sample` | `PNG · 640 × 360 · 4 lines of text` | `Preview · 10 s` | `⌘1` | selected |
| 2 | `Synthetic landscape` | `PNG · 1200 × 800` | `Vitrine · now` | `⌘2` | — |
| 3 | `Terminal screenshot` | `PNG · 11 lines of text` | `Screen · 1 h` | `⌘3` | — |
| 4 | `Whiteboard photo` | `JPEG · from iPhone · 3 lines` | `iPhone · 2 h` | `⌘4` | — |

5. Bottom of list (margin auto 10 10 10, 11 pt `#5B5B61`, line-height 1.4): `Text is read only when you open the peek or press ⇧⌘C. It stays with the image on this Mac and never syncs.` — see BLOCKED Q4 (UI copy vs annotation).

### Peek column (gap 8)

1. **Header row** (gap 6, wraps): kind pill `image` (bg `rgba(255,159,10,.18)`, text `#7A4B00`, icon); chip `Preview`; chip clock icon + `10 s ago`; chip `640 × 360 · 48 KB`; spacer; chip `Clipboard unchanged` (bg `rgba(52,199,89,.14)`, text `#1F7A3A`). All values (sample).
2. **Title:** `OCR sample` (15 pt / 800). No pencil/edit button is drawn.
3. **Image stage:** 150 high, full width, radius 10, gradient 135° `#F7F7FA` → `#E9EAF0`, border 1 `rgba(0,0,0,.08)`. Four region boxes, each 18 high, radius 4, inset left 16, with a numbered badge (14 × 14 circle at −7, −7, white 9 pt / 800):

| Region | Top | Width | Border | Fill | Badge |
|---|---|---|---|---|---|
| `1` | 18 | 110 | 1.5 solid `#34C759` | `rgba(52,199,89,.14)` | `#34C759` |
| `2` | 48 | 170 | 1.5 solid `#8E8E93` | `rgba(0,0,0,.03)` | `#8E8E93` |
| `3` | 78 | 190 | 1.5 solid `#32ADE6` | `rgba(50,173,230,.12)` | `#32ADE6` |
| `4` | 108 | 210 | 1.5 **dashed** `#FF3B30` | `rgba(255,59,48,.08)` | `#FF3B30` |

   Reading: 1 = hovered/focused line (green), 2 = plain line (grey), 3 = link (URL tint), 4 = secret (danger, dashed).
   Toggles top-right (inset 8, gap 4), chip style with bg `#fff`: `Regions`, `Image only`, eyedropper icon + `Pick colour · I`. No pressed state is drawn for `Regions` / `Image only` (BLOCKED Q3).
4. **Text section header row** (gap 6, 11 pt): section label `Text · 4 lines` (11 pt / 700 uppercase tracking .06em `#5B5B61`); spacer; chip globe icon + `Translate to English ▾`; chip palette icon + `Dominant · ` followed by three 9 × 9 radius 2 swatches `#F39B3A`, `#2563EB`, `#1D1D1F` (sample).
5. **Lines** (gap 3). Each: padding 5 × 8, radius 8, bg `#fff`, 12 pt, gap 8; number key (`kn` style), mono text (single line, truncating), trailing icon buttons (`#5B5B61`).

| Line | Text (sample) | Extra | Buttons |
|---|---|---|---|
| `1` | `Hola Gancho` | — | copy icon `aria-label` `Copy line` |
| `2` | `Texto de una imagen` | — | `Copy line` |
| `3` | `https://gancho.app/docs` | chip `link` | `Copy line`, arrow icon `aria-label` `Open link` |
| `4` | `sk_live_••••••••••••••••` (text `#C8231B`, row bg `rgba(255,59,48,.06)`) | chip `contains a secret` | `Copy line`, text button `Reveal` (11 pt / 700 `#1F7A3A`) |

6. Caption under the lines (10.5 pt `#6E6E73`): `Line 4 is held back from Copy all and Save until you reveal it — the rule ManualOCRSession already enforces.` — annotation (names a code type), not UI. See BLOCKED Q2.
7. Spacer, then **Dock** (`role=group`, `aria-label` `Actions`):

| Pos | Label | Key | Notes |
|---|---|---|---|
| 1 (primary) | `Paste into Keynote` | `⏎` | target app is sample (`GC-V4-2`) |
| 2 | `Copy text` | `⇧⌘C` | shipped OCR action |
| 3 | `Save text` | (none) | new dock action |
| 4 | `Pin` | `⌘P` | |
| 5 | `Board` | `⌘B` | |

   `Plain ⌥⏎` is not drawn on the image dock (BLOCKED Q6).

### Footer

Capture pill `Capturing · Keynote in front` (sample, `GC-V4-4`); spacer; hints: `1–4` `focus line` · `⌘` `C` `copy focused` · `I` `eyedropper` · `esc` `hide`; help icon (`Keyboard shortcuts (⌘/)`).

### States drawn
Selected row 1; line 1 highlighted as the linked/hovered region; line 4 masked with Reveal; `Clipboard unchanged` status. Not drawn: recognising skeleton, no text, failed, translation running/done, eyedropper active, dominant chip with no accent, dark mode.

---

## Frame 2 — `GC-11` Code clip · Transform popover open

Label: tag `GC-11` (green) + `Code clip · Transform popover open` + small `recipes · text · code · smart paste · translate`.

Realises: the Transform popover drawn for `GC-11` (one Transform list). Cross-board context: `GC-V4-2` (`Paste into Xcode`), `GC-V4-3` (`All clips · 128`), `GC-V4-4` (footer), `GC-10` (Stack), `GC-09` (masked row).

### List column

Search bar and toolbar identical to Frame 1 except the scope chip reads `All clips · 128` (pressed). Section header `Today` · `5 clips`. Rows (sample):

| # | Tile | Title | Preview | Source · time | Markers / key | State |
|---|---|---|---|---|---|---|
| 1 | code glyph, bg `#5856D6` at 16 %, glyph `#5856D6` | `Example · Swift` | mono `let greeting = "Hello"` (`let` `#A33EA3`, string `#2E7D32`) | `Xcode · now` | `⌘1` | selected |
| 2 | solid `#008080`, inset ring 1 `rgba(0,0,0,.12)` | `Ocean` | mono `#008080` | `Figma · now` | `⌘2` | — |
| 3 | `E`, gradient 160° `#5BC4F0` → `#32ADE6`, text `#0A2B3A` | `Synthetic link` | `https://www.example.com:8443/a%2Fb?q=a%26b#…` | `Safari · 7 s` | `⌘3` | — |
| 4 | thumbnail stand-in | `Synthetic landscape` | `PNG · 1200 × 800` | `Vitrine · now` | icon (`#6E6E73`) + `⌘4` | — |
| 5 | lock glyph, bg `rgba(255,59,48,.16)`, glyph `#C8231B` | `Stripe key · masked` | `sk_live_•••••••••••• 4Q2v` | `Terminal · 2 min` | chip timer icon + `9:41` (bg `rgba(255,159,10,.18)`, text `#7A4B00`) + `⌘5` | — |

### Peek column

1. Header row: pill `code` (bg `rgba(88,86,214,.16)`, text `#3634A3`), chip `Xcode`, chip clock + `now`.
2. Title `Example · Swift` (15 pt / 800).
3. Hero (mono 12 pt, line-height 1.5): line 1 `let greeting = "Hello"`, line 2 `print(greeting)` (`let`, `print` `#A33EA3`; `"Hello"` `#2E7D32`).
4. **Transform button** (aligned leading, `aria-expanded="true"`): 28 high, padding 0 × 10, gap 6, radius 10, bg `#fff`, border 1 `rgba(0,0,0,.08)`, 12 pt / 600; open state = inset ring 1.5 `#1D1D1F`. Content: icon, `Transform`, key cap `⌘T` (16 high, 9.5 pt), chevron icon.
5. **Transform popover** (absolute, left 14, top 178 of the peek, z above content): 330 × 318, radius 14, bg `#fff`, border 1 `rgba(0,0,0,.1)`, shadow `0 18 40 rgba(0,0,0,.18)`.
   - Filter row: padding 8 × 10, gap 8, bottom border; magnifier icon; input `aria-label` `Filter actions`, placeholder `Filter actions… (⌘T)`, 12.5 pt; key cap `esc`.
   - Scrolling list (padding 2 × 4, bottom 22 pt fade = more items below). Group headers: 10 pt / 700 uppercase, padding 6 8 2. Items: padding 5 × 8, gap 8, radius 8, 12 pt, title 600, icon `#5B5B61` (Smart paste icons `#1F7A3A`), hint 10.5 pt `#6E6E73`. Highlighted item: bg `rgba(52,199,89,.14)` with trailing key cap `⏎`.

| Group | Item | Hint | State |
|---|---|---|---|
| `Recipes` | `Text recipes…` | `3 presets · yours` | |
| `Text` | `Trim whitespace` | | |
| | `UPPERCASE` | | |
| | `Title Case` | | |
| | `Strip formatting` | `⌥⏎ also pastes plain` | |
| `Code · Swift` | `Format code` | | highlighted, `⏎` |
| | `Minify` | | |
| | `Base64 encode` | | |
| | `Wrap in markdown fence` | | |
| `Smart paste · on-device` | `Summarize` | | |
| | `Fix grammar` | | |
| | `Change tone ▸` | | submenu |
| | `Key points` | | |
| | `Redact PII` | `works without a model` | |
| | `Translate to ▸` | `installed pairs` | submenu |

   - Popover footer: padding 7 × 10, top border, 10.5 pt `#5B5B61`, lock icon + `Runs on your Mac — nothing leaves the device.`
6. Spacer, **Dock**: `Paste into Xcode` `⏎` (primary) · `Plain` `⌥⏎` · `Pin` `⌘P` · `Board` `⌘B` · `Stack` `⌥⌘⏎`.
7. No `Smart paste` button and no `More actions` toggle are drawn: the popover replaces them.

### Footer
Pill `Capturing · Xcode in front`; hints `↑` `↓` `pick` · `⏎` `run → result box` · `⇧` `⏎` `run and paste`; help icon.

### States drawn
Popover open with `Format code` highlighted; Transform button in its open (ringed) state. Not drawn: filter text typed, no matches, submenu open, result box, thinking state, model unavailable.

---

## Frame 3 — `V4` Colour clip · stage only

Label: tag `V4` (green) + `Colour clip · stage only` + small `formats + contrast`.

Realises: `GC-V4-14`.

Container: a peek column alone, 410 × 540, bg `#F5F5F7`, radius 14, border, panel shadow; padding 12 × 14, gap 10.

1. Header row: pill `color` (bg `rgba(90,200,250,.22)`, text `#0B5C80`); chip with 10 × 10 radius 3 `#1D1D1F` app-icon stand-in + `Figma`; chip clock + `12 s ago`; chip with 8 × 8 radius 3 `#F08C08` swatch + `Brand` (board).
2. Title `Ocean` (15 pt / 800).
3. **Colour hero** (hero card, padding 0):
   - Swatch band 74 high, fill = the clip colour (`#008080`), content aligned bottom-leading, padding 8 × 10; label mono 13 pt / 700 white on `rgba(0,0,0,.3)`, padding 3 × 8, radius 6: `#008080`.
   - Body padding 8 12 10. Four format rows, 26 high, gap 8, 12 pt: label column 38 wide 10 pt / 700 `#5B5B61`; value mono, truncating; trailing copy icon (`#5B5B61`).

| Label | Value (sample) | Copy button `aria-label` |
|---|---|---|
| `HEX` | `#008080` | `Copy HEX` |
| `RGB` | `rgb(0, 128, 128)` | `Copy RGB` |
| `HSL` | `hsl(180, 100%, 25%)` | `Copy HSL` |
| `Swift` | `Color(red: 0, green: .5, blue: .5)` | `Copy Swift` |

   - Contrast pair: 2-column grid, gap 6, margin-top 6. Each card padding 6 × 8, gap 8, radius 8, 11 pt; sample tile 22 × 22 radius 6 fill clip colour with `Aa` white 11 pt / 800; two-line text; trailing tag (20 high, padding 0 × 8, 11 pt / 700).
     - Card 1: bg `#fff`, border 1 `rgba(0,0,0,.1)`: `on white` / **`4.6 : 1`**; tag `AA` (bg `#E3F5E8`, text `#1F7A3A`).
     - Card 2: bg `#1C1C1E`, text `#F2F2F7`: `on #1C1C1E` / **`3.1 : 1`**; tag `below AA` (bg `#FDECEC`, text `#C8231B`).
     - The ratios as drawn are wrong for `#008080`; see Feasibility GC-V4-14.
4. Caption (10.5 pt `#6E6E73`): `Formats come from the shipped Convert color action; the contrast pair is a local WCAG check against white and the dark panel surface.` — annotation (names a code action), not UI.
5. Spacer, **Dock**: `Paste #008080` `⏎` (primary) · `Plain` `⌥⏎` · `Convert` `⇧⏎` · `Board` `⌘B`. No `Pin` drawn (BLOCKED Q6).

No footer (stage only).

---

## Numbered pins (notes row, 5 columns)

Pin badges: 20 × 20 circles `#1D1D1F`, white 11 pt / 800. Note text 12 pt `#3A3A3F`, bold lead `#1D1D1F`.

### Implementation notes (not UI)

1. > **Already shipped and kept:** Vision regions over the thumbnail, hover-linked rows, per-line copy, secret hold-back, “Clipboard unchanged” and Translate of the recognised text with the installed pairs (`PeekImageTextRegions`, `PeekImageTextSection`, the `translation` state of `PeekImageText`, PR #140 / #150). v4 only tightens the layout: provenance in the header, the region toggles on the image.
2. > **New on the image peek (GC-16):** dominant colours from the thumbnail accent the app already computes for the ambient wash (`cachedAccent`) and Pick colour (I), an eyedropper over the thumbnail that saves a colour clip. Links and secrets are never translated, as today.
3. > **One Transform list** replaces Transform ⌄ + Smart paste ⌄ + More actions. Groups: Recipes, Text (`PasteTransform`), the kind's Dev Actions (`DevActions.actions(for:)`) and Smart paste (`SmartPasteAction` + Translate). The group matching the clip's kind comes first; typing filters across all.
4. > **Keyboard contract unchanged:** → enters the peek, ↑↓ walk dock then chips, ⏎ runs the focused action into the result box with Paste / Copy result; ⇧⏎ runs and pastes in one go. Secrets and private mode still hide every transform.
5. > **Colour clip hero (recovered from v2 and v3 GC-04):** the stage shows the formats `Convert color` already produces and a contrast pair against white and the dark surface, so a designer sees AA before pasting. Convert ⇧⏎ keeps opening the result box.

In-frame annotations (also not UI): Frame 1 caption `Line 4 is held back from Copy all and Save until you reveal it — the rule ManualOCRSession already enforces.`; Frame 3 caption `Formats come from the shipped Convert color action; the contrast pair is a local WCAG check against white and the dark panel surface.`; frame label smalls (`kept, incl. Translate · colours · eyedropper`, `recipes · text · code · smart paste · translate`, `formats + contrast`).

Note on pin 5: “v3 GC-04” is an old ID. Today's catalog `GC-04` is `Dark appearance contrast rules` (MenuBarDark). The colour hero is `GC-V4-14`.

---

## Coverage

| Board element | Covered by |
|---|---|
| Header strip (tags, title, subtitle, size) | context only |
| F1 label `GC-13 Image clip · text in image` | `GC-13/14/15` kept, no change + `GC-16` |
| F1 search bar + modes `Fuzzy/Exact/Regex` + `Meaning` | `GC-V4-1` (Novel2); context only here |
| F1 toolbar, scope chip `Images · 4` | `GC-V4-3` (Panel); context only |
| F1 rows with `PNG · 640 × 360 · …` | `GC-V5-3` / `B-GC-04` (Panel); context only |
| F1 list caption `Text is read only…never syncs.` | BLOCKED Q4 (UI copy or annotation); if UI, belongs with `GC-16`/`GC-13` layout |
| F1 header chips (`Preview`, `10 s ago`, `640 × 360 · 48 KB`) | `GC-01` (Panel) |
| F1 `Clipboard unchanged` chip in header | `GC-13` kept (moved from section status to header) |
| F1 regions 1–4 on the image | `GC-13` kept; per-type colours + number badges = layout tightening (pin 1) |
| F1 `Regions` / `Image only` toggles | pin 1 “region toggles on the image” — new, under `GC-16` (no catalog ID of its own) |
| F1 `Pick colour · I` | `GC-16` |
| F1 `Text · 4 lines` header | `GC-13` kept (renamed from `Text in image`) |
| F1 `Translate to English ▾` | `GC-15` kept (shipped Translate), restyled |
| F1 `Dominant ·` swatches | `GC-16` |
| F1 lines 1–4, `Copy line`, `Open link`, `link`, `contains a secret`, `Reveal` | `GC-14` kept (per-line copy, entities, secret hold-back) — per-line hold-back is BLOCKED Q2 |
| F1 caption on line 4 | annotation (pin-like) |
| F1 dock `Paste into Keynote` | `GC-V4-2` (Panel) |
| F1 dock `Copy text ⇧⌘C`, `Pin`, `Board` | kept, no change |
| F1 dock `Save text` | `GC-13` layout (new dock slot for shipped Save as clip) — BLOCKED Q6 |
| F1 footer pill | `GC-V4-4` (Panel) |
| F1 footer hints `1–4 focus line`, `⌘ C copy focused`, `esc hide` | `GC-13` layout (new keys) — no catalog ID; BLOCKED Q5 |
| F1 footer hint `I eyedropper` | `GC-16` |
| F2 label `GC-11 Code clip · Transform popover open` | `GC-11` (catalog board Novel2) |
| F2 list rows (code, colour, link, image, masked key with `9:41`) | context only (`GC-09`, `GC-V5-3` elsewhere) |
| F2 header chips | `GC-01` |
| F2 Transform button `Transform ⌘T` | `GC-11` |
| F2 Transform popover (filter, 4 groups, footer) | `GC-11` |
| F2 dock `Paste into Xcode` | `GC-V4-2` |
| F2 dock `Stack ⌥⌘⏎` | `GC-10` (Novel) — new dock slot for shipped shortcut; BLOCKED Q6 |
| F2 footer hints `↑ ↓ pick`, `⏎ run → result box`, `⇧ ⏎ run and paste` | `GC-11` |
| F3 label `V4 Colour clip · stage only` | `GC-V4-14` |
| F3 header (`color`, `Figma`, `12 s ago`, `Brand`) | `GC-01` |
| F3 swatch band + format rows + copy buttons | `GC-V4-14` |
| F3 contrast pair | `GC-V4-14` |
| F3 caption | annotation |
| F3 dock `Paste #008080`, `Plain`, `Convert ⇧⏎`, `Board` | `GC-V4-14` (`Convert ⇧⏎`); label vs `GC-V4-2` = BLOCKED Q7 |
| Pin 1 | `GC-13/14/15` kept |
| Pin 2 | `GC-16` |
| Pin 3 | `GC-11` |
| Pin 4 | `GC-11` (keyboard) |
| Pin 5 | `GC-V4-14` |

---

## Feasibility

### GC-16 — Dominant colours and eyedropper on images (UI + feature)

**What changes.** On an image clip's peek: (a) a `Dominant ·` chip with up to three swatches next to `Translate`; (b) a `Pick colour · I` toggle on the image stage, plus the key `I` while the peek owns the keyboard, that turns the pointer into an eyedropper over the thumbnail; a click saves the sampled colour as a new colour clip; (c) footer hint `I eyedropper`.

**Exists in code.**
- One **average** colour per thumbnail, not a palette: `ThumbnailAccent` and `ClipThumbnailStore.averageColor(of:)` draw the thumbnail into an 8 × 8 sRGB grid and take the alpha-weighted mean (`Packages/GanchoKit/Sources/GanchoDesign/ClipThumbnailStore.swift:29-37, 226-258`). It is exposed through `cachedAccent(for:)` (`:99`, `:110`) and is used only by the ambient wash (`Apps/GanchoMac/PanelView.swift:430-445`). Tests: `Packages/GanchoKit/Tests/GanchoDesignTests/ClipThumbnailAccentTests.swift`.
- Decoded thumbnail (`CGImage` capped at `maxPixel`, 480 px on macOS) is produced in `decodeThumbnail(from:maxPixel:)` (`:217-224`), off the main actor.
- Saving text as a clip: `AppModel.saveManualText(_:)` (`Apps/GanchoMac/AppModel+ManualOCR.swift:192-205`) ingests a `PasteboardCapture(text:)` through `ClipIngestionCoordinator`; `RuleClassifier` classifies `#RRGGBB` as `.color`. It already refuses while Private Mode is on.
- `Color(hexString:)` (`Packages/GanchoKit/Sources/GanchoDesign/Color+Hex.swift`).

**New work.**
- **Dominant colours:** nothing extracts more than one colour. “From the accent the app already computes” gives exactly one swatch; three swatches need a small quantiser (for example k-means or median cut over the same 8 × 8 grid, or a 16 × 16 grid) computed in the same detached decode and stored next to `accents` (e.g. `ThumbnailAccent` → `ThumbnailPalette { average, dominant: [sRGB] }`). Keep it pure and `nonisolated` for unit tests.
- Are the swatches clickable (copy hex, or save as colour clip)? Not drawn (BLOCKED Q1).
- **Eyedropper:** `NSColorSampler` is not used anywhere in the repo (no match for `NSColorSampler`, `eyedropper`, `Pick colour`). Two routes:
  1. Sample the decoded image at the cursor location (map the point through the `scaledToFit` frame to pixel coordinates; read one pixel or a 3 × 3 mean from the thumbnail `CGImage` or the full-resolution blob). Stays inside the image, works in the non-activating panel, is deterministic and unit-testable.
  2. `NSColorSampler().show { NSColor? in }` (AppKit, macOS 10.15+): the system loupe samples the whole screen, so it can pick colours outside the thumbnail and returns display-space colour of a downscaled render, not the source pixel; it also has to coexist with the panel's hide-on-resign-key behaviour.
  The board says “an eyedropper over the thumbnail”, which matches route 1. Decision needed (BLOCKED Q1).
- Key `I` in `ClipPeek`'s `onKeyPress` (only while `focus == .peek` and no inline editor; in the list the key types into search). Today the peek handles ↑ ↓ ← ⏎ ⌘P ⌘B esc (`Apps/GanchoMac/ClipPeek.swift:189-227`).
- The `Pick colour · I` toggle on the stage, `Regions` and `Image only` (pin 1 “region toggles on the image”) are new view state; the current stage has no toggles (`ClipPeek.swift:458-479`).
- Strings `Pick colour · I`, `Dominant`, `Regions`, `Image only`, `eyedropper`: String Catalog EN + ES (spelling: the board uses British “colour”; the app's strings use “color”, e.g. `Ambient color`, `Convert color` — BLOCKED Q8).
- a11y ids (proposal): `peek-pick-color`, `peek-dominant-colors`, `peek-dominant-color-<n>`, `peek-region-toggle`, `peek-image-only-toggle`.

**Privacy.** Sampling is on-device. Do not sample masked or sensitive images: `ClipPeek` already gates the thumbnail on `!item.isSensitive` (`ClipPeek.swift:459`) and the accent on `PanelAmbientTint.usesAccent(... isSensitive:, previewsHidden:)`. The new clip must go through ingestion (Private Mode honoured). Never log the sampled value.

**Deps.** `GC-V4-14` (the saved colour clip opens in the colour hero); `GC-13` layout (stage toggles); `GC-01` (header provenance); `GC-23` (ambient wash uses the same accent).

**Verify.** Unit (Swift Testing, `GanchoDesignTests`): palette of synthetic 2- and 3-colour bitmaps returns those colours in dominance order; transparent pixels ignored; point → pixel mapping for `scaledToFit` letterboxing. UI (XCTest, `Tests/GanchoUITests/ManualOCRUITests.swift` style, `-ui-test-paste-sink`): select seeded image, press `I`, click the stage, assert a new `.color` row appears. Snapshot vs Frame 1.

**BLOCKED:** Q1 (route, swatch behaviour), Q3 (toggle semantics), Q8 (spelling).

### GC-V4-14 — Colour hero with formats and a contrast check (UI + feature)

**What changes.** The colour clip's hero becomes: 74 pt swatch band with the hex label on a dark scrim; four format rows (HEX, RGB, HSL, Swift) with per-row copy; a contrast pair (on white, on `#1C1C1E`) with pass/fail tags; dock `Paste #… ⏎ · Plain ⌥⏎ · Convert ⇧⏎ · Board ⌘B`.

**Exists in code.**
- Colour hero today: 72 pt rounded swatch + mono hex text (`Apps/GanchoMac/ClipPeek.swift:495-506`), only when `!item.isSensitive` and `Color(hexString:)` parses.
- `DevActions.convertColor` (`Packages/GanchoKit/Sources/GanchoAI/DevActions.swift:238-249`) returns one string, three lines: `hex: #RRGGBB`, `rgb: rgb(r, g, b)`, `hsl: hsl(h, s%, l%)`. Parser `parseColor` accepts `#hex` (3/6/8), `rgb()/rgba()`, `hsl()/hsla()` (`:546-583`, private). `rgbToHSL` rounds to integers (`:609-630`): `#008080` → `hsl(180, 100%, 25%)` matches the board.
- `Convert color` is the only Dev Action for `.color` (`DevActions.swift:70-71`; test `DevActionsTests.swift:88`); today it sits behind `More actions` (Current board 07).
- Luminance code exists only as a black/white chooser: `ContrastingForeground` (`Packages/GanchoKit/Sources/GanchoDesign/ContrastingForeground.swift:10-19`) computes WCAG relative luminance from `linearRed/Green/Blue` and compares `(L+0.05)/0.05` vs `1.05/(L+0.05)`. There is no `contrastRatio` API.

**New work.**
- **Swift format** does not exist in `convertColor` (no `Swift`/`Color(red:` output). Add it, and expose a structured API (e.g. `ColorFormats { hex, rgb, hsl, swift }`, pure, `GanchoAI` or `GanchoKit`) so the hero does not parse the Dev Action's text. Decide decimal precision: 128/255 = 0.50196, drawn as `.5` (BLOCKED Q9).
- **Contrast check:** add a pure `WCAG.contrastRatio(_:_:)` (relative luminance with sRGB linearisation: c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4; L = 0.2126 R + 0.7152 G + 0.0722 B; ratio = (L1+0.05)/(L2+0.05), L1 ≥ L2), shared with `ContrastingForeground` and with `B-GC-02` / `GC-V5-2` (accent-ink token).
- **The board's numbers are wrong.** Computed for `#008080`: on white **4.77 : 1** (board `4.6 : 1`); on `#1C1C1E` **3.56 : 1** (board `3.1 : 1`). For reference: on `#2C2C2E` 2.92, on `#F5F5F7` 4.38, on black 4.40. The pass/fail outcome for normal text is unchanged (AA = 4.5), but 3.56 passes **AA Large** (≥ 3 : 1) and the 3 : 1 non-text threshold, so a bare `below AA` tag is ambiguous (BLOCKED Q10). Display rule (proposal): one decimal, truncated, never rounded up across a threshold.
- The `Aa` tile is white text on the clip colour in both cards; it does not depict the colour on the dark surface. Probably the sample should be the colour as text on each background (BLOCKED Q10).
- Per-row copy: writes the format string through the same revalidated path as other copies (`SystemPasteboardWriter`), with the `Copied` toast. a11y ids (proposal): `peek-color-hero`, `peek-color-format-hex|rgb|hsl|swift`, `peek-color-copy-<format>`, `peek-color-contrast-light|dark`.
- Dock: `Convert ⇧⏎` is a new dock slot; ⇧⏎ is not handled in the peek today (`ClipPeek.swift:202-210` treats any non-⌥ Return as “run focused”). Pin 5 says it “keeps opening the result box” (`resultBox`, `ClipPeek.swift:736-756`). Pin missing from this dock (BLOCKED Q6). `Paste #008080` vs `Paste into <app>` (BLOCKED Q7).
- Strings EN + ES: `on white`, `on %@`, `AA`, `below AA` (+ any AA Large wording), `HEX`, `RGB`, `HSL`, `Swift` (format labels may stay verbatim), `Copy %@`.

**Found while checking (not on the board, affects this hero).** The two hex parsers disagree on 8-digit hex: `Color(hexString:)` reads `#RRGGBBAA` (CSS order, `Color+Hex.swift:16-21`), while `DevActions.parseColor` drops the first two digits, i.e. reads `#AARRGGBB` (`DevActions.swift:551`). `#00808080` draws as teal at 50 % but converts to `rgb(128, 128, 128)`. The hero would show a swatch and formats that disagree. Fix with the shared `ColorFormats` parser.

**Deps.** `GC-01` (header chips), `GC-V4-2` (dock label), `GC-V5-2` / `SY-V4-3` (shared contrast math and green ink `#1F7A3A`), `GC-04` (dark surface `#1C1C1E`), `GC-16` (eyedropper output lands here).

**Verify.** Unit: `ColorFormats` for `#008080`, `#FF6B35`, 3-digit, 8-digit (CSS order), `rgb()`, `hsl()` round-trip; `contrastRatio(#008080, #FFFFFF) ≈ 4.77`, `(#008080, #1C1C1E) ≈ 3.56`, `(#000, #FFF) = 21`; extend `DevActionsTests` for the Swift line. UI: seeded colour clip (`-seed-…` like `-seed-peek-link`), assert four format rows and two contrast cards; copy button writes to the paste sink. Snapshot vs Frame 3.

**BLOCKED:** Q6, Q7, Q9, Q10.

### GC-11 — One Transform (drawn here; catalog board Novel2) (UI + feature)

**Overlap.** The catalog item (`V4_Gancho_Novel2`) is a step pipeline with Before / After, saved recipes and a global ⌃⌘V. This board draws only the entry surface: a single searchable `Transform ⌘T` popover that merges Transform ⌄, Smart paste ⌄ and More actions. The Novel2 spec owns the pipeline; this block specifies the popover. Whether the popover rows add a step to the Novel2 pipeline or run immediately into the result box is not reconciled between the two boards (BLOCKED Q11).

**What changes.** Replace `transformsMenu` (`Apps/GanchoMac/ClipPeek.swift:697-722`), `smartPasteMenu` (`Apps/GanchoMac/ClipPeek+SmartPaste.swift:38-83`) and the `More actions` toggle + Dev Action chips (`ClipPeek.swift:569-584, 769-843`) with one button `Transform ⌘T` that opens a 330 × 318 popover: filter field, groups Recipes · Text · <kind> · Smart paste · on-device, footer privacy line. ↑↓ pick, ⏎ runs into the result box, ⇧⏎ runs and pastes, esc closes.

**Exists vs new, per drawn row.**

| Row | Code today | Status |
|---|---|---|
| `Text recipes…` / `3 presets · yours` | `Text recipes…` opens `TextRecipeReview` sheet (`ClipPeek.swift:699-701`); 3 presets `Clean OCR`, `Clean list`, `Prepare redacted context` (`Packages/GanchoKit/Sources/GanchoKit/TextRecipeStore.swift:21-28`) | exists; hint text new |
| `Trim whitespace` | `PasteTransform.trimmed`, title `Trimmed` (`PasteTransform.swift:13, 29`) | exists, rename |
| `UPPERCASE`, `Title Case` | `PasteTransform.uppercase`, `.titleCase` | exists |
| `Strip formatting` / `⌥⏎ also pastes plain` | `PasteTransform.plainText` (`Plain text`), deliberately omitted from the menu (`ClipPeek.swift:704`) | exists, re-added + renamed |
| other `PasteTransform` cases (lowercase, Single line, Collapse spaces, Sort/Dedupe lines, URL-encode/decode, SHA-256) | exist | not drawn (list fades; assume below) |
| group `Code · Swift` | Dev Actions have no language sub-kind; `RuleClassifier` gives `.code` only | language label new |
| `Format code` | none (no formatter in repo) | **new** |
| `Minify` | only `jsonMinify` for `.json` (`DevActions.swift:61-64`) | **new** for code |
| `Base64 encode` | `base64Encode` in `.code` list | exists |
| `Wrap in markdown fence` | none | **new** |
| 15 code Dev Actions today (JSON-escape … MD5) | `DevActions.actions(for: .code)` (`DevActions.swift:82-90`) | not drawn; presumably below the fade |
| `Summarize`, `Fix grammar`, `Key points`, `Redact PII` | `SmartPasteAction` (`Packages/GanchoKit/Sources/GanchoAI/SmartPasteService.swift:16-44`); Redact PII shown without the model (`ClipPeek+SmartPaste.swift:41`) | exists; hint `works without a model` new |
| `Change tone ▸` | `.formal` (`Make formal`), `.friendly` (`Make friendly`) as two flat items | submenu new |
| `Translate to ▸` / `installed pairs` | `Translate to` submenu over `translationTargets` (`ClipPeek+SmartPaste.swift:50-65`) | exists |
| footer `Runs on your Mac — nothing leaves the device.` | same string (`ClipPeek+SmartPaste.swift:71`) | exists |
| filter field, ⌘T, ⇧⏎ | no ⌘T anywhere (panel shortcuts: ⌘V, ⌥⌘V, ⇧⌘C, ⌘G, ⌘Y, ⌘S); ⇧⏎ not distinguished in the peek | **new** |

**Keyboard (pin 4).** Today `navActions = dockActions + toggleActions + chipActions` (`ClipPeek.swift:765`) and Return runs `navActions[actionIndex]`; position 0 must stay Paste (`ClipPeek.swift:795-798`). With the popover, ↑↓ in the peek walk only the dock (and the Transform button); inside the open popover ↑↓ walk rows. Keep `canTransform` / `canSmartPaste` gates (`ClipPeek.swift:676-692`) so secrets and Private Mode hide every transform.

**Ordering conflict.** Pin 3 says the kind's group comes first; the drawing puts Recipes, Text, then `Code · Swift` for a code clip (BLOCKED Q12).

**Deps.** Novel2 `GC-11` pipeline and `GC-12` (prompt-to-transform), `TextRecipe` / `TextRecipeExecutor`, `GC-V5-6` (chip type size), `GC-10` (Stack in the dock).

**Verify.** Unit: a pure `TransformCatalog.groups(for kind:, modelAvailable:, isSensitive:)` returning ordered groups and filtering (“base” matches `Base64 encode` across groups); empty for sensitive/private. UI: update `Tests/GanchoUITests/PeekDockUITests.swift` (uses `peek-more-actions`), `TextRecipeUITests.swift` (`text-recipes-action`), `TranslationCapabilityUITests.swift` (`translation-destinations-menu`) and the `transform-menu` / `smart-paste-menu` ids; new ids (proposal) `transform-button`, `transform-popover`, `transform-filter`, `transform-row-<id>`. Snapshot vs Frame 2.

**BLOCKED:** Q11, Q12; `Format code` scope (which languages, which formatter, offline only?) Q13.

### GC-13 / GC-14 / GC-15 — legacy, shipped, kept

Confirmed in code (merged PR #140 `codex/manual-image-ocr`, PR #150 `feat/ocr-entity-chips`):
- Regions over the thumbnail with hover linking and click-to-copy: `PeekImageTextRegions` (`Apps/GanchoMac/PeekImageText.swift:49-110`).
- Per-line copy, `Line copied`, Copy all, Save as clip, Edit, Reveal/Hide, link and email chips: `PeekImageTextSection` (`:115-403`, entities `:413-455`).
- `Clipboard unchanged` status (`:241-249`); Translate with installed pairs and the `TranslationState` enum (`:136-156`, `:571-588`); never offered for secrets (`:414`, `:547`).
- OCR text cached locally with the image and never synced (`SyncLocalStore.swift:427-430`, `ManualImageTextService.swift:45`).
Status: **kept**. Layout changes the board asks for (header provenance, `Clipboard unchanged` moved to the header, numbered and type-coloured regions, `Text · 4 lines` label, `Translate to English ▾` dropdown instead of a single `Translate` chip, white line cards with number keys, `Save text` in the dock, `1–4` and `⌘C` keys) are new work and need owner confirmation per the “only propose what beats current” rule.

Gaps between the board and the shipped behaviour:
- **Per-line secret hold-back is not what `ManualOCRSession` enforces.** The session has one `isSensitive` flag for the whole result (`Packages/GanchoKit/Sources/GanchoAppCore/ManualOCRSession.swift:29, 85-86`); while masked, every line is masked (`PeekImageText.swift:272`) and Copy all / Save / Edit are replaced by `Reveal` (`:316-319`). The board shows lines 1–3 in clear and only line 4 held back (BLOCKED Q2).
- **OCR on peek open.** Today OCR runs only on explicit ⇧⌘C / `Copy text` (`PanelView.swift:163-166`, `ClipPeek.swift:799-805`) and, when not sensitive and the clipboard has not changed, **copies the text automatically** (`ManualOCRSession.swift:87-89`, state `.copied`). The list caption says text is read when you open the peek, and the header shows `Clipboard unchanged` (BLOCKED Q4).
- Region colours: today one tint for all regions (accent, or danger when masked; `PeekImageText.swift:20-22`), no number badges.

### Cross-board items drawn here (owned elsewhere)

`GC-01` header provenance, `GC-V4-2` `Paste into <app>`, `GC-V4-3` `Images · 4` / `All clips · 128`, `GC-V4-4` capture pill, `GC-V5-3` / `B-GC-04` image row metadata, `GC-V4-1` search modes, `GC-09` masked row, `GC-10` Stack. No B-GC bug or SY item is realised on this board; `SY-V4-3` (green ink `#1F7A3A`) and `B-GC-02` / `GC-V5-2` (contrast math) are dependencies.

---

## Open questions (BLOCKED)

1. **Q1 (GC-16)** Eyedropper route: sample the image pixel under the cursor inside the thumbnail (deterministic, matches “over the thumbnail”) or `NSColorSampler` (system loupe, whole screen)? Thumbnail (480 px) or full-resolution pixel? Are the `Dominant` swatches clickable, and what does a click do (copy hex vs save colour clip)? How many swatches minimum when the image is flat?
2. **Q2 (GC-14)** Per-line secret hold-back (lines 1–3 usable while line 4 is masked) needs per-line detection in `ManualOCRSession`; today one secret masks everything. Adopt per-line, or keep whole-result masking and redraw?
3. **Q3** `Regions` and `Image only`: are they a two-state segmented control (regions on/off) or independent toggles? Which is the default? No pressed state is drawn.
4. **Q4** Is `Text is read only when you open the peek or press ⇧⌘C. It stays with the image on this Mac and never syncs.` UI copy or an annotation? If UI and accurate, OCR must start on peek open and must **not** auto-copy (today ⇧⌘C copies), which changes the explicit-request contract of `ManualOCRSession`.
5. **Q5** New peek keys `1–4` (focus line) and `⌘C` (copy focused line): confirm, including lines beyond 9 and the conflict with ⌘C in an inline editor.
6. **Q6** Dock composition differs per kind and from today (Paste, Plain, [Copy text], Pin, Board): image drops `Plain` and adds `Save text`; code adds `Stack ⌥⌘⏎`; colour drops `Pin` and adds `Convert ⇧⏎`. Intentional per-kind docks, or drawing shortcuts?
7. **Q7** Colour dock primary reads `Paste #008080` while `GC-V4-2` says the primary names the target app (`Paste into Figma`). Which wins for colour clips?
8. **Q8** Spelling: board uses “colour” (`Pick colour · I`); shipped strings use US “color”. Keep US English in the String Catalog?
9. **Q9** Swift format precision: `Color(red: 0, green: .5, blue: .5)` rounds 0.502; two decimals (`0.50`) or three (`0.502`)? Include `opacity:` for 8-digit hex? Also `Color(red:green:blue:)` vs `Color(.sRGB, …)`.
10. **Q10** Contrast: correct values are 4.77 : 1 and 3.56 : 1 (board 4.6 and 3.1). Tag wording for 3–4.5 (`AA Large` vs `below AA`)? Should the `Aa` sample show the colour as text on each background? Is the dark reference `#1C1C1E` (GC-04 surface) or the hero card `#2C2C2E` (2.92 : 1)?
11. **Q11 (GC-11)** Does a popover row run immediately (result box, ⇧⏎ paste) or add a step to the Novel2 pipeline with Before / After? Same ⌘T for both?
12. **Q12 (GC-11)** Pin 3 says the kind's group comes first; the drawing shows Recipes → Text → Code · Swift. Which order?
13. **Q13 (GC-11)** `Format code`, `Minify` (non-JSON code) and `Wrap in markdown fence` are new transforms: which languages, offline only (no formatter exists in the repo), and does `Code · Swift` require language detection that `RuleClassifier` does not provide?

## Owner notes

- Pick notes: `GC-11` pick, `GC-16` pick, `GC-V4-14` pick — no note text on any of them.
- No owner comment thread targets this board. General owner rules that apply: compare every proposal with the current UI and only propose what beats it (2026-10-17); code wins over v2 boards; each piece of data appears once per screen (relevant: OCR status `Clipboard unchanged` moves to the header, provenance moves to the header and the insight strip goes away, per `GC-01`).
