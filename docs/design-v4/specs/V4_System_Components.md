# V4_System_Components — spec (Gancho column + shared rules)

- **Board:** `V4_System_Components.dc.html`, canvas **2880 × 1810** (dark board chrome `#0B0C11`, radius 12, padding 24 × 28, gap 14).
- **What it shows:** one component sheet per app (six columns: Portavoz, Lingua, Gancho, Vitrine, Puntovivo, Janusly) built from each codebase's own tokens, plus two footer rows of cross-app rules. **This spec covers only the Gancho column and the footer rules that bind every app**; the other five columns are out of scope.
- **Replaces:** `ComponentsV2` · `OverviewV2 rules` · `v1 Overview` (header tag).
- **Related Current boards (reference only):** `GanchoPanelActions_Current` (peek dock: Paste / Plain / … — Paste today draws dark ink via `ContrastingForeground`), `GanchoPanel_Current`, `GanchoSettings_Current`, `GanchoPrivacyCenter_Current`, `GanchoPhone_Current` (draws `✓ All clips` white on `#34C759`).
- **Catalog items realised:** SY-V4-3, SY-V4-6, SY-V4-7, SY-V4-8, SY-V4-9. Linked: GC-V5-2 (+ B-GC-02, B-GC-03), GC-04.

Units: the board is HTML px; 1 px = 1 pt.

---

## 1. Board header (context only)

- Title (24/800, `#F4F5FA`): `Components v4 · six apps, one method, grounded in each codebase`
- Subtitle (12.5, `#B9BCCB`), bold part in `#F4F5FA`:
  `Every colour below is read from the app’s own tokens (file named under each title); nothing is invented except the hover/pressed steps, which follow one rule: hover = fill −8 % L (light UI) / +8 % L (dark UI), pressed = −16 % / +16 %, disabled = 40 % opacity and no shadow, focus = 2 px gap + 2 px ring in the control’s own hue. Ratios are WCAG 2.x, computed at build time and printed; AA = 4.5:1 for text, 3:1 for large text and UI boundaries. Portavoz shows only its decided palette (violet + amber, Oct 17); option A is recorded in the Portavoz Archive. Puntovivo colours are sampled from screenshots where theme.css does not name them.`
- Tags (right, 20 high, r6, 11/700): `2880 × 1810` · `portavoz · PVDesign.swift` · `lingua · index.css` · `gancho · GanchoColors.swift` · `vitrine · BrandColors.swift` · `puntovivo · theme.css` · `janusly · foundations.css` · (warn) `replaces ComponentsV2 · OverviewV2 rules · v1 Overview`

The bold sentence is the normative state rule (SY-V4-6).

---

## 2. Gancho column — `Gancho · brand green` (SY-V4-3, SY-V4-6, SY-V4-7, SY-V4-8)

Column 3 of 6. Background `#F6F6F8` (window), text `#1D1D1F`, radius 16, padding 16, vertical gap 11. **Light appearance only is drawn**; no dark variant of this column exists on the board (dark green `#30D158` is only named in the source line).

### 2.1 Heading
- 12 × 12 swatch r4 `#34C759` + `Gancho · brand green` (16/800, `#1D1D1F`).
- Source line (10.5 mono, `#5C5C61`): `GanchoTokens.Palette.brandGreen #34C759 / dark #30D158 · warning #FF9F0A · danger #FF3B30 · Radius 6/8/10/14/20 · FontSize 11/13/15/22`
- Tags: (bad) `today: white on green = 2.2:1` · (ok) `fix: dark ink on green`

### 2.2 Palette (8 swatches, 26 high, r7, 1 px border `rgba(128,128,128,.25)`; hex 8.5 mono/600, name 8.5)
| # | Hex | Label as drawn |
|---|---|---|
| 1 | `#34C759` | `brand` |
| 2 | `#2FB350` | `hover` |
| 3 | `#2A9F47` | `pressed` |
| 4 | `#1C7A37` | `green text` |
| 5 | `#E3F5E8` | `tint` |
| 6 | `#FF9F0A` | `warning` |
| 7 | `#D70015` | `danger` |
| 8 | `#F6F6F8` | `window` |

### 2.3 Buttons — `Primary · Plain · Secondary · Tertiary · Destructive`
Five rows × five states (`rest`, `hover`, `pressed`, `disabled`, `focus`; state caption 8.5 mono, 55 %). Every button: height 30, padding 0 × 8, radius 10, 12/600, 1 px border, gap 6. Hover adds `translateY(-1px)`; pressed `translateY(0)`; disabled = `opacity .4` + no shadow; focus = `0 0 0 2px #F6F6F8, 0 0 0 4px <ring>` (2 px gap in window colour + 2 px ring).

Note: the label says five roles but the rows drawn are Primary, Plain (= secondary), Tertiary (`Transform`), Quiet/neutral tertiary (`Pin`), Destructive.

| Row | Label | rest | hover | pressed | disabled | focus ring |
|---|---|---|---|---|---|---|
| Primary | `Paste ⏎` | fill `#34C759`, ink `#062D12`, shadow `0 4px 12px rgba(52,199,89,.28)` | fill `#2FB350` | fill `#2A9F47` | rest @ 40 %, no shadow | `#1C7A37` |
| Plain (secondary) | `Plain ⌥⏎` | fill `#FFFFFF`, text `#1D1D1F`, border `rgba(29,29,31,.10)`, no shadow | fill `#F3F3F6` | fill `#EAEAEF` | rest @ 40 % | `#1C7A37` |
| Tertiary | `Transform` | transparent, text `#1C7A37` | fill `#E3F5E8` | fill `#CDEBD6` | rest @ 40 % | `#1C7A37` |
| Neutral tertiary | `Pin` | transparent, text `#1D1D1F` | fill `rgba(29,29,31,.05)` | fill `rgba(29,29,31,.09)` | rest @ 40 % | `#1C7A37` |
| Destructive | `Delete ⌫` | transparent, text `#D70015` | fill `#FDECEE` | fill `#F9D9DD` | rest @ 40 % | `#D70015` |

### 2.4 `Kind tiles · chips (site --kind-*)`
- Six tiles 26 × 26, r8, white letter 10/800, a11y label = kind: `c` code `#5856D6` · `u` url `#32ADE6` · `j` json `#5E5CE6` · `i` image `#FF9F0A` · `s` secret `#FF3B30` · `f` file `#007AFF`.
- Three chips (24 high, padding 0 × 9, capsule, 11.5/600): `Link` (`#E6EEFF` / `#1F4FC2`) · `Sensed, not read` (`#E3F5E8` / `#1C7A37`) · `All clips` (`#1D1D1F` / `#FFFFFF`).

### 2.5 `Segmented · toggle · check`
- Segmented: track `rgba(29,29,31,.06)`, padding 2, r9, gap 1; segments 24 high, padding 0 × 10, r7, 11.5/600. Selected `All clips` = `#FFFFFF` fill, `#1D1D1F`, shadow `0 1px 2px rgba(0,0,0,.18)`; unselected `★ Favorites` (10 pt star glyph, 4 pt gap) and `Boards` = `#5C5C61`, no fill. **Selected segment is white, not green.**
- Switch: 38 × 22, r11, on = `#34C759`, knob 18 × 18 white at x 18.
- Checkbox: 16 × 16, r4, 1.5 border, checked fill `#34C759`, check mark stroke `#062D12` 3.5 (10 × 10 glyph).

### 2.6 `Inputs · 44 px search`
Three fields, each 32 high as drawn (label says 44 px), padding 0 × 10, r9, 12 pt, bg `#FFFFFF`, border `rgba(29,29,31,.10)`, text `#1D1D1F`, placeholder at 55 %:
1. Rest — placeholder `Search, or type to filter  ⌘F` (two spaces before `⌘F`).
2. Focused — value `focused`, border `#1C7A37`, halo `0 0 0 3px #C6DECD`.
3. Error — value `invalid`, border `#D70015`, trailing `!` 10/700 `#D70015`.

### 2.7 `Elevation` (4 tiles, 54 high, r10)
| Token | Fill | Shadow | Border | Caption |
|---|---|---|---|---|
| `e0 flat` | `#F6F6F8` | none | 1 px `rgba(29,29,31,.10)` | `sidebar, rows` |
| `e1 card` | `#FFFFFF` | `0 1px 2px rgba(0,0,0,.05)` | 1 px `rgba(29,29,31,.10)` | `clip card r10` |
| `e2 raised` | `#FFFFFF` | `0 8px 20px rgba(0,0,0,.08)` | none | `selected row, lifts 2 px` |
| `e3 panel` | `#FFFFFF` | `0 18px 40px rgba(0,0,0,.16)` | none | `menu-bar panel r14` |

### 2.8 `Type · SF Pro (GanchoTokens.FontSize)`
| Spec | Sample as drawn | Colour |
|---|---|---|
| `22/800` (tracking −.02em) | `Gancho` | `#1D1D1F` |
| `15/600` | `Title` | `#1D1D1F` |
| `13/400` | `Body · row title` | `#1D1D1F` |
| `12/500` (drawn at 400) | `Subtitle · meta` | `#5C5C61` |
| `11/700` uppercase, +.06em | `Today · 5 clips` (sample) | `#6E6E73` |

### 2.9 `Contrast (WCAG)` (as printed)
| Pair | Board | Badge |
|---|---|---|
| `white on brand green (today)` | `2.2:1` | `FAIL` |
| `green ink on brand green (v4)` | `6.8:1` | `AA` |
| `green text on white` | `5.4:1` | `AA` |
| `green text on tint` | `4.8:1` | `AA` |
| `white on danger #FF3B30 (today)` | `3.5:1` | `3:1` |
| `white on danger D70015 (v4)` | `5.4:1` | `AA` |
| `ink on warning amber` | `8.5:1` | `AA` |
| `body on window` | `15.6:1` | `AA` |
| `secondary on white` | `6.6:1` | `AA` |
| `tertiary on white` | `5.1:1` | `AA` |

### 2.10 `Motion (GanchoMotion.swift)`
- `Select` — `row lifts 2 px + green shadow, 150 ms`
- `Panel` — `180 ms scale .96→1 from the status item`
- `Paste` — `press .92 then hide; Reduce Motion → fill only`

### 2.11 Column footnote (10.5, `#5C5C61`)
`What changed vs v2: the Paste button keeps the brand fill but takes dark ink (6.8:1, like Lingua’s on-accent); green text uses #1C7A37 (5.4:1) never #34C759 (2.2:1); Delete moves to #D70015. Kind tiles keep the site’s --kind-* hues.`

#### Implementation notes (not UI)
- Tags `today: white on green = 2.2:1` / `fix: dark ink on green`, the source line, the contrast table and the footnote are annotations, not app UI.
- The button strings (`Paste ⏎`, `Plain ⌥⏎`, `Transform`, `Pin`, `Delete ⌫`), chips and field values are **component samples**; they do not redefine any screen's copy.

---

## 3. Footer row 1 — shared rules (four cards, bg `#171822`, border `rgba(255,255,255,.1)`, r14, padding 12 × 14, 11.5)

1. **Portavoz · decided (Oct 17).** — out of scope (Portavoz).
2. **Shared rules.** (SY-V4-8) `One saturated control per surface (primary or CTA); secondary = surface + hairline; tertiary = text in the accent hue with a tint on hover; destructive = red text at rest, red fill only inside a confirmation. Ink on a saturated fill is chosen by contrast, not by habit: Lingua, Gancho and Vitrine-dark take dark ink; Portavoz, Vitrine-light, Puntovivo and Janusly take white.`
3. **Elevation scale.** (SY-V4-7) `e0 flat (window / sidebar, hairline only) → e1 card (1–2 px, 5–6 %) → e2 raised (8 px blur, 8–12 %, used for hover and selection) → e3 overlay (18–40 px, 16–35 %, menus / capsule / panel). Dark apps add a 1 px inset highlight on top (Lingua’s --shadow-* already does). Radius per app comes from its tokens; nothing new.`
4. **Fixes found while computing.** (SY-V4-3, Gancho part) `Gancho: white on #34C759 is 2.2:1 and white on #FF3B30 is 3.5:1 — both fail today.` (remaining sentences concern other apps: Portavoz `#E8342B`, Vitrine `#4F6BFF`, Lingua lime/Manrope, Puntovivo ember, Janusly cyan) `All six columns above follow this.`

## 4. Footer row 2 — cross-app vocabulary (SY-V4-9; five cards)

1. **One line per app (v1 Overview).** `The thesis each product’s chrome serves; a control that does not serve it is chrome.` Pills (26 high, capsule, 11.5/700 + italic 500): Gancho pill = bg `#E3F5E8`, text `#1C7A37`, dot `#34C759`: `Gancho · the hook you never look at`. (Also `Portavoz · the colour is the voice`, `Lingua · signal, not chrome`, `Vitrine · the work is the only colour`.)
2. **Keys drawn on controls (v2 OverviewV2 / ComponentsV2).** `The primary action carries its shortcut as a keycap inside the button (10 px, 85 % ink); menus print keys right-aligned; destructive actions never show a key.` Gancho sample: `Paste` + keycap `⏎` on `#34C759`, ink `#062D12`; keycap 16 high, padding 0 × 5, r4, bg `rgba(255,255,255,.1)`, border `rgba(255,255,255,.14)`, 10/700 mono, opacity .85, 6 pt left margin. (Others: `Generate ⌘⏎`, `▶ Run ⌘⏎`, `Copy image ⇧⌘C`, `Export ⌄`.)
3. **Hit targets and focus (v1 Overview).** `44 px on iOS and for the menu-bar CTA; 28–30 px toolbar icons and 24 px rows on macOS at 13 px type; focus = 2 px gap + 2 px ring in the control’s hue; tab order follows reading order.` Samples: `44` (44 × 44, r12, `#34C759` / `#062D12`), `30` (r9), `28` (r8), `24 row` (64 × 24, r7), `focus` (30 × 30, ring `#7C8CFF`).
4. **One command surface per app (v2).** `One text field per window that takes search and commands; results carry a group label so Theme and Background never collide.` Gancho field (28 high, 11.5, white, border `rgba(29,29,31,.10)`): glyph `⌕`, placeholder `Search, or type to filter`, trailing `⌘F`; a11y label `Gancho command surface`.
5. **Type and radius from the tokens (v2).** `Four steps plus a label; nothing invented.` Gancho row: `22 / 15 / 13 / 12 / 11` · `r 6 · 8 · 10 · 14 · 20`.

#### Implementation notes (not UI)
- All footer cards are rules/annotations. The thesis pills are not app UI.

---

## 5. Token map — Gancho column vs `Packages/GanchoKit/Sources/GanchoDesign`

Legend: **same** = exists with the same value · **diff** = exists with a different value (code → board) · **new** = no token today.

### 5.1 Palette
| Board token | Board value | Code | Status |
|---|---|---|---|
| brand | `#34C759` / dark `#30D158` | `GanchoTokens.Palette.brandGreen` `GanchoColors.swift:21-22` (also `success`, `:34`; `accent` fallback `:68-79`) | **same** |
| hover | `#2FB350` | — | **new** (see 5.2: drawn value is RGB × 0.90, not −8 % L) |
| pressed | `#2A9F47` | — | **new** (RGB × 0.80) |
| green text | `#1C7A37` | — (`accent`/`success` used as ink, e.g. `GanchoColors.swift:72`, `PasteboardStatusRow.swift:114`) | **new** — overlaps the accent-ink token of GC-V5-2 |
| on-green ink | `#062D12` | `ContrastingForeground` (`ContrastingForeground.swift:5-20`) returns pure `#000000` on green | **diff** (`#000000` → `#062D12`) |
| tint | `#E3F5E8` | — (code uses `accent.opacity(0.12–0.18)` washes, e.g. `Components.swift:330`, `PeekActionButton.swift:82`) | **new** |
| warning | `#FF9F0A` | `Palette.warning` `GanchoColors.swift:37-38` | **same** |
| danger | `#D70015` | `Palette.danger` `GanchoColors.swift:41-42` = `#FF3B30` light & dark | **diff** (`#FF3B30` → `#D70015` light; dark not drawn) |
| window | `#F6F6F8` | — (surfaces are glass / `.background.secondary`, `Components.swift:20-26`) | **new** (or map to system window background) |
| body text | `#1D1D1F` | system `.primary` | **new** as hex; code relies on system label |
| secondary text | `#5C5C61` | system `.secondary` (≈ `#808080` on white, ≈3.9:1 — approx, verify) | **diff** |
| tertiary text | `#6E6E73` | system `.tertiary` (≈ `#BDBDBD`, ≈1.9:1 — approx, verify), e.g. `Components.swift:396` | **diff** |
| kind tiles | c `#5856D6`, u `#32ADE6`, j `#5E5CE6`, i `#FF9F0A`, s `#FF3B30`, f `#007AFF` | `Palette.kindTint` `Components.swift:104-114` | **same** for c/u/i/s/f; **diff** for json (`#5856D6` → `#5E5CE6`) |
| Link chip | `#E6EEFF` / `#1F4FC2` | `TypeBadge(.pill)` = kind tint on 14 % wash (`Components.swift:68-76`) | **diff** (tint-on-wash ≈2.3:1 for url) |

### 5.2 Button states
| State | Board | Code today | Status |
|---|---|---|---|
| Primary rest | `#34C759` fill + `#062D12` ink + shadow `0 4 12 .28 green` | Dock Paste: `accent` fill + `ContrastingForeground` (black), no shadow (`PeekActionButton.swift:78-91`); `.borderedProminent` / `.defaultAction` buttons: system white label on accent (`ClipTextEditor.swift:104`, `SnippetFillSheet.swift:86`, `MigrationImportView.swift:100,108`, iOS `ClipTextEditor.swift:69`, `ClipTitleEditor.swift:36`, 8 `.defaultAction` sites) | **diff** (black → `#062D12`; white → `#062D12` on prominent buttons) |
| Primary hover | `#2FB350` | none (primary has no hover change) | **new** |
| Primary pressed | `#2A9F47` | `.plain` style, no pressed state | **new** |
| Disabled | 40 % opacity, no shadow | SwiftUI default dimming | **new** as a rule |
| Focus | 2 px gap + 2 px ring, hue `#1C7A37` (red `#D70015` on destructive) | 1.5 pt `.primary` stroke, no gap (`GanchoTokens.Stroke.focus = 1.5`, `GanchoTokens.swift:27`; `PeekActionButton.swift:92-96`; `PanelView.swift:950-954`) | **diff** (1.5 → 2 pt, add 2 pt gap, primary → control hue) |
| Secondary (Plain) | white + hairline `rgba(29,29,31,.10)`; hover `#F3F3F6`, pressed `#EAEAEF` | dock non-primary: clear; hover `.quaternary.opacity(0.7)`; focus `accent.opacity(0.18)` | **diff** |
| Tertiary (Transform) | `#1C7A37` text; hover `#E3F5E8`; pressed `#CDEBD6` | dev-action chips: `.quaternary` capsule, hover `.tertiary.opacity(0.5)` (`PeekActionButton.swift:100-120`) | **new** style |
| Neutral (Pin) | hover 5 %, pressed 9 % of `#1D1D1F` | dock hover `.quaternary.opacity(0.7)` | **diff** |
| Destructive | text `#D70015`; hover `#FDECEE`; pressed `#F9D9DD`; fill only in confirmation | `role: .destructive` (29 sites, system red); `Palette.danger` text | **diff** (value) / **new** (tint steps) |

### 5.3 Chips, segmented, switch, checkbox, fields
| Element | Board | Code | Status |
|---|---|---|---|
| Chip | 24 h, capsule, pad 9, 11.5/600 | rail chip: pad 8 (or 6), vert 4, caption (`PanelView.swift:930-946`); iOS status chip pad 9 × 4, caption2 semibold (`PasteboardStatusRow.swift:104-129`) | **diff** (sizes) |
| `Sensed, not read` | `#1C7A37` on `#E3F5E8` (4.76:1) | `success` text on `success.opacity(0.14)` (≈2.0:1) | **diff** |
| Active board/filter | segmented, selected = white pill + shadow | rail chip active = `accent` fill + `ContrastingForeground` (`PanelView.swift:930-939`) | **diff** — see SY-V4-8 question |
| Switch | on `#34C759`, 38 × 22 | system `Toggle` tinted by `.ganchoTinted()` | **same** colour (system geometry) |
| Checkbox | fill `#34C759`, mark `#062D12` | system checkbox (white mark) | **diff** (mark colour not settable on the system style without a custom `ToggleStyle`) |
| Field | 32 h (label: 44 search), r9, hairline, focus border `#1C7A37` + 3 px `#C6DECD` halo, error border `#D70015` | `SearchField` `.bare` (title3, pad 16 × 12) / `.card` on glass, r10 (`Components.swift:500-561`); prompt `Search your clipboard` (`PanelView.swift:556`) | **diff**; error state **new** |
| Radii | 6 / 8 / 10 / 14 / 20 | `Radius.sm 6, card 8, md 10, lg 14, xl 20` (`GanchoTokens.swift:17-23`) | **same** |

### 5.4 Elevation
| Board | Code | Status |
|---|---|---|
| e0 flat (hairline) | `Stroke.hairline = 1` (`GanchoTokens.swift:26`) | **same** (stroke only) |
| e1 card `0 1 2 .05`, r10 | `ganchoSurface` = glass, no shadow, default r8 (`Components.swift:37`) | **new** |
| e2 raised `0 8 20 .08`, selected row lifts 2 px | selected row = 12 % accent wash + 3 pt bar, no lift/shadow (`Components.swift:326-340`) | **new** (and conflicts with the shipped selection style — see BLOCKED) |
| e3 panel `0 18 40 .16`, r14 | panel `Radius.lg` 14 (`PanelView.swift:293-294`), `NSPanel.hasShadow = !translucent` (`PanelController.swift:405`); ad-hoc `.shadow(radius: 18, y: 8)` (`PanelView.swift:543`), `(radius: 20, y: 8)` (`PanelShortcutsOverlay.swift:63`) | radius **same**; shadow **new** as a token |

### 5.5 Type
| Board | Code | Status |
|---|---|---|
| 22/800 | `FontSize.largeTitle = 22` | size **same**; weight not tokenised |
| 15/600 | `FontSize.title = 15` | **same** size |
| 13/400 | `FontSize.body = 13` | **same** |
| 12/500 | — | **new** (macOS `.callout` is 12 via `PanelTextStyle`) |
| 11/700 | `FontSize.caption = 11` | **same** size |

`GanchoTokens.FontSize` is defined but **unused** anywhere in `Apps/` or `Packages/GanchoKit/Sources`; panel type goes through `PanelTextStyle` + `panelTypeScale` (`PanelTypography.swift`). Any type token work must go through `panelFont`, never `.dynamicTypeSize` on macOS.

### 5.6 Motion (board vs `GanchoMotion.swift`)
| Board | Code | Status |
|---|---|---|
| Select 150 ms, lift 2 px + green shadow | `GanchoMotion.quick` = `.snappy(duration: 0.18)`; no lift/shadow | **diff** |
| Panel 180 ms scale .96→1 | only the telemetry prompt uses `.scale(0.96)` (`PanelView.swift:546`) | **diff/new** |
| Paste press .92 then hide | none | **new** |

Motion is owned by `V4_Gancho_Motion`; recorded here only as a discrepancy.

---

## 6. Contrast — recomputed (WCAG 2.x, sRGB, computed for this spec)

| Pair | Ratio | Result |
|---|---|---|
| white on `#34C759` (prominent buttons, iPhone rail chip today) | 2.22 | FAIL |
| white on `#30D158` (dark) | 2.02 | FAIL |
| `#000000` on `#34C759` (`ContrastingForeground` today) | 9.46 | AA |
| `#000000` on `#30D158` | 10.39 | AA |
| **`#062D12` on `#34C759` (rest)** | **6.80** | AA (board 6.8 ✓) |
| **`#062D12` on `#2FB350` (hover)** | **5.52** | AA |
| **`#062D12` on `#2A9F47` (pressed)** | **4.42** | **FAIL (< 4.5)** |
| **`#062D12` on `#30D158` (dark rest)** | **7.46** | AA |
| `#062D12` on dark hover/pressed (+8 / +16 % L → `#51D873` / `#73E08E`) | 8.20 / 9.18 | AA |
| `#0B2A14` (ink on other Gancho v4 boards) on `#34C759` / `#2A9F47` | 6.98 / 4.54 | AA / AA (barely) |
| `#04210D` (dark ink on other boards) on `#30D158` | 8.45 | AA |
| `#000000` on `#2A9F47` | 6.15 | AA |
| `#1C7A37` on white / window `#F6F6F8` / tint `#E3F5E8` / pressed tint `#CDEBD6` | 5.40 / 5.00 / 4.76 / **4.23** | AA / AA / AA / **FAIL** |
| `#1C7A37` on dark `#1C1C1E` | 3.15 | FAIL (needs a dark value; `#30D158` text = 8.42) |
| `#34C759` as text on white | 2.22 | FAIL |
| `#34C759` on its 14 % wash (`Sensed, not read` today) | 1.98 | FAIL |
| white on `#FF3B30` / `#D70015` | 3.55 / 5.38 | large-only / AA |
| `#D70015` text on white / window / hover tint / pressed tint | 5.38 / 4.99 / 4.72 / **4.10** | AA / AA / AA / **FAIL** |
| `#D70015` on dark `#1C1C1E` | 3.16 | FAIL (keep `#FF3B30` = 4.80 or `#FF453A` = 4.99 in dark) |
| `#FF3B30` text on white (today's danger captions) | 3.55 | FAIL |
| `#1D1D1F` on `#FF9F0A` | 8.19 | AA (board 8.5 — ink unspecified; black = 10.22) |
| `#1D1D1F` on `#F6F6F8` | 15.59 | AA |
| `#5C5C61` on white / window | 6.65 / 6.16 | AA |
| `#6E6E73` on white / window | 5.07 / 4.70 | AA |
| placeholder `#1D1D1F` @ 55 % on white | 3.79 | FAIL for text |
| switch `#34C759` vs window (UI 3:1) | 2.06 | FAIL as boundary (system switch; knob carries state) |
| focus ring `#1C7A37` / `#D70015` vs window | 5.00 / 4.99 | ≥3:1 ✓ |
| white kind letters on `#32ADE6` / `#FF9F0A` / `#FF3B30` / `#007AFF` | 2.54 / 2.06 / 3.55 / 4.02 | FAIL (code already uses `ContrastingForeground` for the url monogram) |
| disabled Paste (40 % over window) | 1.74 | exempt (WCAG 1.4.3 inactive) |

**State-step derivation:** drawn hover `#2FB350` / pressed `#2A9F47` are the brand RGB × 0.90 / × 0.80 (HSL L 49.2 % → 44.3 % / 39.4 %). A literal −8 % / −16 % L gives `#2CA74B` / `#23863C` (absolute) or `#30B752` / `#2CA74B` (relative). The drawn steps do not follow the printed rule exactly.

---

## 7. Coverage

| Board element | Covered by |
|---|---|
| Header title, subtitle (state rule), tags | SY-V4-6 (rule); rest context only |
| Gancho heading, source line, tags | SY-V4-3 (context/annotation) |
| Palette swatches | SY-V4-3 (green text, ink, danger), SY-V4-6 (hover/pressed); warning/brand/window kept |
| Primary `Paste ⏎` row | SY-V4-3, SY-V4-6, SY-V4-8, SY-V4-9 (keycap) |
| Plain `Plain ⌥⏎` row | SY-V4-6, SY-V4-8 (secondary = surface + hairline) |
| Tertiary `Transform` row | SY-V4-3 (green text), SY-V4-6, SY-V4-8 |
| Neutral `Pin` row | SY-V4-6 |
| Destructive `Delete ⌫` row | SY-V4-3 (`#D70015`), SY-V4-6, SY-V4-8 |
| Kind tiles | kept, no change (code `kindTint`; json hue diff noted) |
| Chips `Link` / `Sensed, not read` / `All clips` | SY-V4-3 (green text on tint); GC-V5-2 |
| Segmented · switch · checkbox | SY-V4-8 (selected segment not saturated), SY-V4-3 (check ink) |
| Inputs | SY-V4-6 (focus), SY-V4-9 (command surface) |
| Elevation tiles | SY-V4-7 |
| Type samples | SY-V4-9 (type table); context only otherwise |
| Contrast table | SY-V4-3 |
| Motion strip | context only (owned by V4_Gancho_Motion) |
| Column footnote | SY-V4-3 |
| Footer: Portavoz decided | out of scope (Portavoz) |
| Footer: Shared rules | SY-V4-8 |
| Footer: Elevation scale | SY-V4-7 |
| Footer: Fixes found | SY-V4-3 (Gancho sentence); other apps out of scope |
| Footer 2: One line per app | SY-V4-9 |
| Footer 2: Keys drawn on controls | SY-V4-9 |
| Footer 2: Hit targets and focus | SY-V4-9, SY-V4-6 |
| Footer 2: One command surface | SY-V4-9 |
| Footer 2: Type and radius table | SY-V4-9 |
| Other five app columns | out of scope (other app specs) |

No numbered pins on this board.

---

## 8. Feasibility

### SY-V4-3 — Gancho contrast fix: dark ink on brand green
- **Changes:** (a) on-green ink `#062D12` (light) for every text/glyph on a brand-green fill; (b) a `green text` token `#1C7A37` for green used as text/icon on light surfaces; (c) `danger` light `#FF3B30` → `#D70015`; (d) tint `#E3F5E8` for green-text chips.
- **Files:** `Packages/GanchoKit/Sources/GanchoDesign/GanchoColors.swift:21-42` (add `onAccentInk`, `accentText`/`greenText`, `accentTint`; make `danger` dynamic light `#D70015` / dark `#FF3B30`), `ContrastingForeground.swift:19` (return the ink token instead of `.black` when the fill is the brand green), call sites `PeekActionButton.swift:89`, `PanelView.swift:937`, `SettingsView.swift:140`, iOS `ClipDetailView.swift:182`, `CaptureView.swift:306`, `ReuseSuggestionBanner.swift:36`; prominent buttons `ClipTextEditor.swift:104` (Mac), `SnippetFillSheet.swift:86`, `MigrationImportView.swift:100,108`, iOS `ClipTextEditor.swift:69`, `ClipTitleEditor.swift:36`, and the 8 `.keyboardShortcut(.defaultAction)` sites; green-as-text sites (`PasteboardStatusRow.swift:114`, `IntelligenceView.swift`, `MCPAccessView.swift`, `PeekImageText.swift`, `PaywallView.swift:190`, …); white-on-green `PrivacyCenterView.swift:382-388` and `PanelResultsView.swift:228-232`.
- **Exists:** brand green, warning, `ContrastingForeground` (already keeps the dock Paste and rail chips legible with black — the board's "today 2.2:1" is true for system prominent buttons, `.foregroundStyle(.white)` on green, and iPhone, not for the dock Paste). **New:** ink, green-text, tint tokens; danger value; a custom prominent `ButtonStyle` (system `.borderedProminent` label colour is white on macOS).
- **Deps:** GC-V5-2 (accent-ink token for the system-accent case; same token family — implement once), B-GC-02, B-GC-03, GC-04 (dark ink/surfaces), SY-V4-6 (pressed fill).
- **Verify:** extend `Packages/GanchoKit/Tests/GanchoDesignTests/ContrastingForegroundTests.swift` with ≥4.5:1 for ink on rest/hover/pressed light+dark, green-text on white/window/tint, danger on white and on dark; snapshot the peek dock and a `.borderedProminent` sheet vs §2.3.
- **BLOCKED:** (1) Ink value conflict: this board `#062D12` / green text `#1C7A37`; every other Gancho v4 board draws `#0B2A14` on `#34C759` (113×), `#04210D` on `#30D158` (29×) and green text `#1F7A3A`. Which pair is canonical? (2) `#062D12` on the drawn pressed `#2A9F47` is 4.42:1 (fails); pick a darker ink, a lighter pressed step, or exempt pressed? (3) Dark values for green text and danger are not drawn (`#1C7A37` = 3.15:1 and `#D70015` = 3.16:1 on `#1C1C1E`); confirm dark = `#30D158` text and `#FF3B30`/`#FF453A` danger. (4) When the user picks a non-green system accent, ink comes from GC-V5-2 / `ContrastingForeground` (e.g. black on Blue 5.23:1) — confirm SY-V4-3 applies only to the brand-green path.

### SY-V4-6 — Shared hover/pressed/disabled/focus rule
- **Changes:** hover = fill −8 % L (light) / +8 % L (dark); pressed −16 % / +16 %; disabled 40 % opacity, no shadow; focus = 2 pt gap + 2 pt ring in the control's hue.
- **Files:** new `ButtonStyle`(s) in `Packages/GanchoKit/Sources/GanchoDesign/` (e.g. alongside `Components.swift`); `GanchoTokens.Stroke.focus` 1.5 → 2 (`GanchoTokens.swift:27`); consumers `PeekActionButton.swift:59-120`, rail chips `PanelView.swift:930-954`, `IconActionButton.swift`, `ActionButton` (`Components.swift:468-496`).
- **Exists:** hover washes and a 1.5 pt `.primary` focus stroke; `GanchoMotion.quick` for state transitions. **New:** derived hover/pressed colours, pressed state on `.plain` buttons (needs `configuration.isPressed`), gap ring, disabled rule.
- **Deps:** SY-V4-3 (fill values), B-GC-05 (ring only with keyboard focus).
- **Verify:** pure unit test of the L-step function (Swift Testing) incl. the brand inputs; UI test that a focused dock button exposes the ring only under keyboard focus; snapshot vs §2.3.
- **BLOCKED:** the drawn steps (`#2FB350`, `#2A9F47`) are RGB × 0.90 / × 0.80, not −8 / −16 % L (`#2CA74B` / `#23863C` absolute). Implement the printed rule or the drawn hexes?

### SY-V4-7 — Shared four-step elevation scale
- **Changes:** tokens e0 (hairline only), e1 `0 1 2 rgba(0,0,0,.05)` + hairline, e2 `0 8 20 rgba(0,0,0,.08)`, e3 `0 18 40 rgba(0,0,0,.16)`; dark adds 1 pt inset top highlight.
- **Files:** new `GanchoTokens.Elevation` + `View.ganchoElevation(_:)` in `GanchoDesign`; replace ad-hoc shadows `PanelView.swift:543`, `PanelShortcutsOverlay.swift:63`, iOS `ReuseSuggestionBanner.swift:55`; panel window shadow `PanelController.swift:405`.
- **Exists:** radii (6/8/10/14/20), hairline stroke, glass surfaces. **New:** shadow tokens, inset highlight.
- **Deps:** GC-04 (dark surfaces), glass (`GanchoSurface`, macOS 26 `#available`): shadows on glass must not double the system glass shadow.
- **Verify:** snapshot of card/raised/overlay on light and dark; check that Reduce Transparency branch still reads.
- **BLOCKED:** e2 says "selected row, lifts 2 px" with shadow; the shipped selection is a 12 % accent wash + 3 pt leading bar in a glass panel (owner-approved panel redesign). Does e2 replace the row selection style, or apply only to hover/cards?

### SY-V4-8 — One saturated control per surface
- **Changes:** per surface only one accent-filled control; secondary = surface + hairline; tertiary = accent-hue text + tint on hover; destructive = red text, red fill only inside a confirmation; ink chosen by contrast.
- **Files:** audit `PanelView.swift:930-939` (active board/filter chip filled with accent while the peek's Paste is also filled), `SettingsView.swift:137-145` (active sidebar row filled), `PrivacyCenterView.swift:83,178` (`.tint(danger)` destructive buttons), `PeekActionButton.swift`.
- **Exists:** `ContrastingForeground` already picks ink by contrast. **New:** secondary/tertiary/destructive button styles; possibly un-filling the rail's active chip (board's segmented shows a white selected pill).
- **Deps:** SY-V4-3, SY-V4-6, panel/rail specs (V4_Gancho_Panel).
- **Verify:** design audit per surface (panel, peek, Settings, Privacy Center, iOS capture); snapshot.
- **BLOCKED:** should the panel's active board/filter chip lose its accent fill (white segmented pill as drawn here) so Paste is the only saturated control? Panel boards are the owner of that UI.

### SY-V4-9 — Cross-app vocabulary
- **Changes (Gancho):** primary carries keycap inside the button (10 pt, 85 % ink); menus print keys right-aligned; destructive never shows a key; 44 pt iOS / menu-bar CTA, 28–30 pt toolbar icons, 24 pt rows; one command field per window (`⌕ … ⌘F`); type/radius table `22 / 15 / 13 / 12 / 11`, `r 6 · 8 · 10 · 14 · 20`.
- **Files:** `PeekActionButton.swift:72-74` (shortcut under the title today, 70 % opacity — board puts it as a keycap inside), `SearchField` `Components.swift:500-561` + `PanelView.swift:556` (prompt `Search your clipboard` vs board `Search, or type to filter`), `GanchoTokens.FontSize` (`GanchoTokens.swift:30-35`, unused; add a 12 step or retire in favour of `PanelTextStyle`).
- **Exists:** radii exactly; shortcut hints on dock; single search field. **New:** keycap chip; 12 pt step; a `⌘F` hint in the field.
- **Deps:** B-GC-01 (menu shortcut glyph), panel/peek specs for copy.
- **Verify:** UI test reading `peek-dock` shortcut text; snapshot.
- **BLOCKED:** (1) The Gancho column draws `Delete ⌫` with a key while the shared rule says destructive actions never show a key — which wins? (2) Search placeholder: adopt `Search, or type to filter` (needs EN+ES String Catalog entries) or keep the shipped `Search your clipboard`? (3) `Inputs · 44 px search` vs the 32 pt field drawn — target height?

### GC-V5-2 / B-GC-02 / B-GC-03 (linked, realised on V4_Gancho_Settings)
Shares the token work above: B-GC-02 (`GanchoColors.swift:72`, system accent used as ink ≈2.6:1) needs the accent-ink token that SY-V4-3's `#1C7A37` is the brand-green instance of; B-GC-03 (`PrivacyCenterView.swift:382`, white on `success.gradient`) is fixed by dark ink or a darker hero. Implement in one PR with SY-V4-3.

---

## 9. Owner notes
- Picks: SY-V4-3, SY-V4-6, SY-V4-7, SY-V4-8, SY-V4-9 all `pick`, no pick note.
- No owner comment thread on this board. Applicable general rules: compare every proposal with the current UI and only propose what beats it (code wins over v2 boards); each piece of data once per screen; annotations are not UI.
- Other IDs named on the board (not Gancho catalog items): `PT-36` (Puntovivo dark nav/primary fixes, Shell board), `JN-V4 #4` (Janusly fonts not self-hosted).
