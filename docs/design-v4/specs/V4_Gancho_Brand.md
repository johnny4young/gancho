# V4_Gancho_Brand — spec

- **Board:** `V4_Gancho_Brand.dc.html`, canvas 1600 × 1820 (background `#ECEDF0`, radius 12, padding 26 × 28, row gap 16).
- **Shows:** documentation of the brand mark the app ships today (the hook in `Resources/Brand`), the tiles built from it, the 18 pt menu-bar template, colour tokens, clear space, do/don't, and a 13-row "Apply to the app" checklist with repo paths. Not a redesign.
- **Realises:** GC-V7-1 (+ owner decisions 1 and 2).
- **Related Current boards:** `GanchoMenuBar_Current` (status item + menu as shipped), `GanchoWelcome_Current` (OnboardingView steps 1–3; step 1 header is the SF `paperclip`).
- **Verified against:** branch `design-v4/fase-0-plan` @ `a251a65` (same commit the board cites, "main @ a251a658").

Board pixels are treated as pt. This board is reference documentation: its cards, tables and code blocks are NOT app UI. The only app UI it specifies is the mark itself, its tiles, the menu-bar template, and the three "To apply" swaps.

---

## 0 · Header strip (top, full width)

Left to right, one row, gap 12, vertically centred:
1. ID pill `GC-V7-1` — 22 h, padding 0 9, radius 7, bg `#34C759`, ink `#0B2A14`, 11 pt heavy (800), mono, tracking .04em.
2. Title `Gancho brand mark · source of truth` — 24 pt, weight 800, tracking −.02em.
3. Tag `Shipped today · source of truth` — 22 h, capsule, bg `#E3F5E8`, ink `#1F7A3A`, 11.5 pt bold.
4. Spacer, then right-aligned `Gancho · v4 · checked against main @ a251a658, Oct 19` — 13 pt `#5B5B61`.

Intro row (two paragraphs, gap 28, 13 pt `#5B5B61`, line-height 1.45):
- Left (max 900 wide): `The hook below is the icon the app ships today, copied from the repo vectors, not retraced. The owner keeps it (Oct 19), so this board only documents it: one mark, the tiles built from it, the menu bar template, tokens and where each asset lives, so a later session can apply it everywhere without redrawing.`
- Right (3 pt left rule `#C7C7CC`, padding-left 10): **`Not adopted:`** (bold, `#1D1D1F`) ` the 24-grid hook with a separate barb stroke drawn earlier on the v4 Onboarding, Menu bar and iPhone surfaces boards (owner keeps the current icon, Oct 19). Those boards now use this mark.`

### Implementation notes (not UI)
> "checked against main @ a251a658, Oct 19"
> "Not adopted: the 24-grid hook with a separate barb stroke drawn earlier on the v4 Onboarding, Menu bar and iPhone surfaces boards … Those boards now use this mark."

Consequence for other specs: any 24-grid hook glyph on V4_Gancho_Onboarding, V4_Gancho_MenuBarDark or V4_Gancho_iPhoneSurfaces is superseded by the mark below.

---

## Card style (all seven sections)
bg `#F7F7F9`, border 1 px `rgba(0,0,0,.07)`, radius 16, padding 16 × 18, internal gap 12. Section title: 12 pt, weight 800, tracking .06em, uppercase, `#3A3A3F`. Key/value rows: key column 96 wide, 12 pt semibold `#5B5B61`; value 12 pt `#1D1D1F`, line-height 1.35. Code blocks: bg `#1C1C1E`, ink `#E5E5EA`, 10.5 pt mono, radius 10, padding 10 × 12. Notes: 11.5 pt `#5B5B61`.

Row 1 grid: columns 500 / 504 (1fr) / 500, gap 20. Row 2 grid: 614 (1fr) / 450 / 440, gap 20. Row 3: section 7 full width (1544).

---

## 1 · The mark, single source (row 1, left, 500 wide)

Title as drawn: `1 · The mark, single source`. Realises GC-V7-1 (source of truth).

Structure:
1. Figure + spec rows side by side (gap 18):
   - Figure: 170 × 170 white box, radius 14, border 1 px `rgba(0,0,0,.08)`; mark drawn at 150 × 150, stroke `#34C759`, no fill, round caps and joins.
   - Key/value rows (gap 6):
     - `Canvas` — `viewBox 0 0 96 96`
     - `Eye` — `circle (50, 24) r 8, stroke 7`
     - `Hook` — `stem 50,32 to 50,57, arc r 15 to 35,57, barb to 31.5,47.5, stroke 11`
     - `Ends` — `round caps and joins`
     - `Bounds` — `about x 22 to 63, y 12 to 91: not centred; tiles re-centre it`
2. Code block (verbatim):
   ```
   <!-- Gancho mark · bare, single colour
        source: Resources/Brand/gancho-mark-green.svg -->
   <svg viewBox="0 0 96 96" fill="none"
        stroke="currentColor" stroke-linecap="round"
        stroke-linejoin="round">
     <circle cx="50" cy="24" r="8" stroke-width="7"/>
     <path d="M50 32 L50 57 A15 15 0 1 1 35 57 L31.5 47.5"
           stroke-width="11"/>
   </svg>
   ```
3. Label `Extract from these files, not from this board`, then rows (paths in mono `#3634A3`, 11 pt):
   - `Bare mark` — `Resources/Brand/gancho-mark-green.svg` `96 × 96, #34C759`
   - `macOS tile` — `Resources/Brand/gancho-mark.svg` `tile 80 / 96, rx 20`
   - `iOS master` — `Resources/Brand/gancho-appicon.svg` `1024, full bleed`
   - `Template` — `GanchoMenuBarCommand.hookImage` `18 pt, 9 / 13`

Bounds check (computed): eye outer radius 8 + 3.5 → y 12.5; arc centre (42.5, 69.99) r 15 + 5.5 → x 22, y 90.5; stem right edge 55.5, arc right 63. Matches `x 22 to 63, y 12 to 91`.

### Implementation notes (not UI)
> "Extract from these files, not from this board"

---

## 2 · App icon tiles (row 1, centre, 504 wide)

Title as drawn: `2 · App icon tiles`. Realises GC-V7-1.

Structure:
1. Three figures, bottom-aligned, gap 16. Each: checkerboard box (white + `#E9E9EE` 12 pt checks), padding 8, radius 12, border 1 px `rgba(0,0,0,.08)`; tile drawn 124 × 124; caption 10.5 pt `#5B5B61` centred, gap 6:
   - `macOS · gancho-mark.svg` — rect x 8 y 8 80 × 80 rx 20, gradient y 8→88; mark `translate(48,48) scale(0.8) translate(-41,-45)`, white strokes 7 / 11.
   - `iOS master · full bleed` — rect 0 0 96 96, no radius, gradient y 0→96; mark scale 0.92.
   - `iOS as shown by the system` — same as iOS master, clipped to rx 21.5 / 96 (illustrates the system mask; not an asset).
2. Key/value rows (gap 6), swatches 14 × 14 radius 4:
   - `Background` — swatch gradient — `linear gradient, top to bottom, #43D267 to #2BB14E`
   - `macOS tile` — `80 of 96: 854 px on a 1024 canvas, 85 px transparent margin`
   - `macOS corner` — `rx 20 of 96: 213 px at 1024 (25 % of the tile), no baked shadow`
   - `macOS mark` — `scale 0.8, centred: hook about 65 % of canvas height`
   - `iOS` — `full bleed 1024 px, no radius (system mask), mark scale 0.92, about 75 %`
   - `Mark ink` — white swatch — `white #FFFFFF, strokes 7 / 11`
3. Note: `Observation: Apple's macOS grid uses an 824 px tile with 100 px margins; the shipped tile is 854 px. Kept as shipped.`
4. Code block (verbatim):
   ```
   <!-- macOS tile · Resources/Brand/gancho-mark.svg -->
   <linearGradient id="g" x1="48" y1="8" x2="48" y2="88"
     gradientUnits="userSpaceOnUse">
     <stop offset="0" stop-color="#43D267"/>
     <stop offset="1" stop-color="#2BB14E"/>
   </linearGradient>
   <rect x="8" y="8" width="80" height="80" rx="20"
         fill="url(#g)"/>
   <g transform="translate(48,48) scale(0.8)
                 translate(-41,-45)" stroke="#FFFFFF">
     <!-- same circle + path, strokes 7 / 11 -->
   </g>
   <!-- iOS · gancho-appicon.svg: full-bleed rect 0 0 96 96,
        gradient y 0 to 96, scale(0.92), no corner radius -->
   ```

Numbers check: 80/96 × 1024 = 853.3 (854), margin 85.3, rx 213.3; hook height 79 × 0.8 = 63.2 / 96 ≈ 66 %, × 0.92 ≈ 76 %. Consistent.

### Implementation notes (not UI)
> "Observation: Apple's macOS grid uses an 824 px tile with 100 px margins; the shipped tile is 854 px. Kept as shipped."

---

## 3 · Menu bar template and small sizes (row 1, right, 500 wide)

Title as drawn: `3 · Menu bar template and small sizes`. Realises GC-V7-1 (template + small sizes, widget header swap).

Structure:
1. Top row (gap 16):
   - Template figure: 120 × 120 white box, radius 10, border 1 px `rgba(0,0,0,.12)`, overlaid 18 × 18 grid (cell 6.667, lines `rgba(0,0,0,.07)`); mark 108 × 108 in `#1D1D1F`, **strokes eye 9 / hook 13**.
   - Two menu-bar mocks (gap 8), each 26 h, radius 7, padding 0 10, gap 14, 12 pt medium:
     - Light: bg `rgba(246,246,248,.96)`, border 1 px `rgba(0,0,0,.08)`, ink `#1D1D1F`. Items: icon slot (26 × 22, radius 5, bg `rgba(127,127,127,.18)`, mark 18 × 18 strokes 9 / 13) · `Wi-Fi` · `Mon 9:41` (sample).
     - Dark: bg `#26262A`, mark ink `#F2F2F7`, labels `#C7C7CC`. Same items.
     - The highlighted slot shows the status item in its pressed/open state.
   - Note: `18 pt template, one colour, no gradient, no tile. Strokes eye 9 / hook 13 (bolder than the 7 / 11 master) so it holds at 18 pt. The system tints it.`
2. Status-states strip (white, radius 10, padding 10 × 12, gap 22). Label `Status states` (90 wide). Four 16 × 16 icons with 10.5 pt captions:
   - mark (strokes 9 / 13) — `capturing`
   - circle with two bars — `paused`
   - circle with rounded square — `stopped`
   - outline triangle with `!` — `denied`
3. Live Activity panel (bg `#000`, radius 12, padding 12, gap 8): title `Live Activity and Dynamic Island · GanchoMark tile` (11 pt bold `#F2F2F7`); four macOS-style tiles (strokes 7 / 11) with captions (10.5 pt `#C7C7CC`): `19 pt`, `20 pt`, `24 pt`, `38 pt`.
4. Widget-header strip (white, radius 10, padding 10 × 12, gap 12): mark 12 × 12 (strokes 9 / 13, ink `#1D1D1F`) + `Recent clips` (12 pt bold `#1D1D1F`, gap 5); note `Widget header, 12 pt template. Today it shows SF "paperclip"; see checklist.`

States: capturing = mark; paused / stopped / denied = SF Symbols (see code below). Accessibility: none drawn.

### Implementation notes (not UI)
> "18 pt template, one colour, no gradient, no tile. Strokes eye 9 / hook 13 (bolder than the 7 / 11 master) so it holds at 18 pt. The system tints it."
> "Widget header, 12 pt template. Today it shows SF "paperclip"; see checklist."

Code reality (verified): status icons are `MenuBarStatusIcon.templateImage()` in `Apps/GanchoMac/GanchoMenuBarCommand.swift:196-203` — `.active` → `hookImage`, `.paused` → `pause.circle`, `.stopped` → `stop.circle`, `.denied` → `exclamationmark.triangle.fill` (filled, the board draws an outline triangle — board illustration only, code wins).

---

## 4 · Colour tokens (row 2, left, 614 wide)

Title as drawn: `4 · Colour tokens`. Table, header 10.5 pt uppercase bold `#5B5B61`; rows 12 pt; swatches 14 × 14.

| Token | Light | Dark | Source |
|---|---|---|---|
| `Brand green` | `#34C759` | `#30D158` | `GanchoColors.brandGreen (Packages/GanchoKit/Sources/GanchoDesign/GanchoColors.swift:21)` |
| `Tile gradient, top` | `#43D267` | `#43D267` | `Resources/Brand/*.svg · same in both appearances` |
| `Tile gradient, bottom` | `#2BB14E` | `#2BB14E` | `Resources/Brand/*.svg` |
| `Mark on tile` | `#FFFFFF` | `#FFFFFF` | `Resources/Brand/gancho-mark.svg` |
| `Template ink` | `#000000` | `#FFFFFF` | `isTemplate = true; the system picks the ink` |

Note: `Green is a fill, never a text colour: #34C759 on white is about 2.2 : 1.`

Verified: `GanchoColors.swift:21` is `public static let brandGreen = dynamic(light: (0x34, 0xC7, 0x59), dark: (0x30, 0xD1, 0x58))`. Gradient hexes match all three `Resources/Brand` SVGs. `hookImage` draws `NSColor.black` with `isTemplate = true`.

### Implementation notes (not UI)
> "Green is a fill, never a text colour: #34C759 on white is about 2.2 : 1." (aligns with SY-V4-3 / B-GC-02; not realised here.)

---

## 5 · Clear space and minimum size (row 2, centre, 450 wide)

Title as drawn: `5 · Clear space and minimum size`.

Structure: figure (106 × 150, dashed 1.5 pt `#8E8E93` border, radius 6, fill `rgba(52,199,89,.10)`; white 49 × 93 box at 27, 27 holding the bare mark cropped to viewBox `16.5 6.5 52 90`; two `x` labels 10 pt bold `#1F7A3A`) + rows:
- `Clear space` — `x = eye ring diameter (23 of 96 units) on every side of the mark bounds`
- `Tile` — `keep the 8 / 96 margin of the master`
- `Min, bare` — `12 pt, template strokes 9 / 13`
- `Min, tile` — `16 px (icon_16.png); 19 pt on the Lock Screen`

Note: `Clear space and minimums are guidance derived from the shipped sizes, not rules found in the repo.`

### Implementation notes (not UI)
> "Clear space and minimums are guidance derived from the shipped sizes, not rules found in the repo."

---

## 6 · Do and don't (row 2, right, 440 wide)

Title as drawn: `6 · Do and don't`. List, gap 9, 12 pt; status pill 52 wide (Do: bg `#E3F5E8` ink `#1F7A3A`; Don't: bg `#FDECEC` ink `#B3261E`):
1. `Do` — `Copy the paths from Resources/Brand; never retrace or re-grid the hook.`
2. `Do` — `Below 24 pt use the template strokes 9 / 13, one colour.`
3. `Don't` — `Swap in SF Symbols "paperclip" or "link" where the brand should appear.`
4. `Don't` — `Add colour, a gradient or a tile to the menu bar template, or recolour the hook on the tile.`

---

## 7 · Apply to the app (row 3, full width)

Title as drawn: `7 · Apply to the app`, subtitle `every target that shows the mark, with its real path in the repo` (13 pt `#5B5B61`). Table columns: `Status` (92) · `Surface` (190) · `Asset` (250) · `Target in the repo` (flex, mono 11 pt `#3634A3`) · `Spec` (330). Status pills: Shipped (`#E3F5E8`/`#1F7A3A`), To apply (`#FFF1D6`/`#8A5300`), Optional (`#E8E7FF`/`#3634A3`), None (`#E5E5EA`/`#3A3A3F`).

The 13 rows, verbatim, with path verification (✅ exists and line content matches; ⚠️ note):

| # | Status | Surface | Asset | Target in the repo | Spec | Verified |
|---|---|---|---|---|---|---|
| 1 | `Shipped` | `Master vectors` | `gancho-mark.svg (tile), gancho-mark-green.svg (bare), gancho-appicon.svg (full bleed)` | `Resources/Brand/` | `viewBox 0 0 96 96 · the only source` | ✅ all three files present |
| 2 | `Shipped` | `macOS app icon` | `render gancho-mark.svg` | `Apps/GanchoMac/Assets.xcassets/AppIcon.appiconset/icon_16 · 32 · 64 · 128 · 256 · 512 · 1024.png` | `10 slots, 16 to 512 pt @1x/@2x, RGBA, transparent margin` | ✅ 7 PNGs, `Contents.json` has 10 mac slots; `icon_1024.png` 1024 px with alpha; render visually matches the tile |
| 3 | `Shipped` | `iOS / iPadOS app icon` | `render gancho-appicon.svg` | `Apps/GanchoiOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | `single universal 1024 px, full bleed, system mask` | ✅ single `universal`/`ios` 1024 entry; render visually matches; ⚠️ `sips` reports `hasAlpha: yes` (see doubts) |
| 4 | `Optional` | `iOS dark and tinted icon` | `bare mark on dark, mark-only for tinted` | `same AppIcon.appiconset (add appearances to Contents.json)` | `optional, not shipped today` | ✅ set exists; no `appearances` in `Contents.json` today |
| 5 | `Shipped` | `Menu bar status item` | `drawn in code, not an asset` | `Apps/GanchoMac/GanchoMenuBarCommand.swift:233 (hookImage) · used by StatusItemController.swift:112 and GanchoMenuBarHelper/main.swift:119` | `18 pt, strokes 9 / 13, isTemplate = true; paused / stopped / denied use SF Symbols` | ✅ `:233` is `private static let hookImage: NSImage = {`; `Apps/GanchoMac/StatusItemController.swift:112` and `Apps/GanchoMenuBarHelper/main.swift:119` are both `button.image = ….templateImage()` |
| 6 | `Shipped` | `Live Activity, Dynamic Island` | `GanchoMark imageset (tile svg)` | `Apps/GanchoWidgets/Assets.xcassets/GanchoMark.imageset/gancho-mark.svg · ClipLiveActivity.swift:83` | `19 / 20 / 24 / 38 pt, keyline #34C759` | ✅ SVG byte-identical to `Resources/Brand/gancho-mark.svg`; `Apps/GanchoWidgets/ClipLiveActivity.swift:83` is `struct GanchoMark: View {`; sizes at `:20` (24), `:43` (20), `:48` (19), `:62` (38); keyline `:51` uses `GanchoMark.green` = `#34C759` |
| 7 | `To apply` | `Widget header` | `SF "paperclip" today` | `Apps/GanchoWidgets/RecentClipsWidget.swift:89` | `swap for the bare mark as a template image, 12 pt, strokes 9 / 13` | ✅ `:89` = `Image(systemName: "paperclip")` (`.caption.bold()`, `.foregroundStyle(.tint)`) |
| 8 | `To apply` | `Mac onboarding header` | `SF "paperclip" 44 pt today` | `Apps/GanchoMac/OnboardingView.swift:58` | `use the tile (add GanchoMark.imageset to GanchoMac/Assets.xcassets), 44 to 56 pt` | ✅ `:58` = `Image(systemName: "paperclip")` `.font(.system(size: 44))` `.foregroundStyle(.tint)`; `Apps/GanchoMac/Assets.xcassets/GanchoMark.imageset` does NOT exist yet (new) |
| 9 | `To apply` | `Wrapped view` | `SF "paperclip" today` | `Apps/GanchoMac/WrappedView.swift:14` | `bare mark in brand green` | ✅ `:14` = `Image(systemName: "paperclip")` `.font(.system(size: 36))` `.foregroundStyle(.tint)` |
| 10 | `Shipped` | `Settings About` | `NSApp.applicationIconImage` | `Apps/GanchoMac/AboutSettingsTab.swift:37` | `inherits the app icon, nothing to do` | ✅ `:37` = `Image(nsImage: NSApp.applicationIconImage)` (72 × 72) |
| 11 | `None` | `Keyboard extension` | `no mark today` | `Apps/GanchoKeyboard/KeyboardView.swift` | `keep it that way, system keyboard chrome` | ✅ file exists |
| 12 | `Shipped` | `Website` | `favicon + inline bare mark` | `site/assets/gancho-mark.svg · site/index.html:424 (.brand .mark, color var(--accent))` | `identical paths, keep in sync with Resources/Brand` | ✅ `site/assets/gancho-mark.svg` byte-identical to `Resources/Brand/gancho-mark.svg` (it is the TILE; used as favicon at `site/index.html:20`); `:424` is the inline bare mark (`currentColor`, strokes 7 / 11); CSS `.brand .mark` at `:72`; a second identical inline mark at `:1214` |
| 13 | `Optional` | `README` | `no logo today` | `README.md` | `optional: Resources/Brand/gancho-mark.svg at 64 px above the title` | ✅ exists; first line `# Gancho — Smart Clipboard`, no logo |

No path on the list is missing.

---

## SVG comparison: board vs repo

Repo hashes (sha1): `Resources/Brand/gancho-mark.svg` = `Apps/GanchoWidgets/Assets.xcassets/GanchoMark.imageset/gancho-mark.svg` = `site/assets/gancho-mark.svg` = `7d76f727bdcd383fc80f4ef4915edbc61b6d593c`; `gancho-mark-green.svg` `5a0a6b59…`; `gancho-appicon.svg` `7be0e4b4…`.

| Board drawing | Repo file | Byte-for-byte | Visual |
|---|---|---|---|
| §1 bare mark (150 pt, `#34C759`) and its code block (`currentColor`) | `Resources/Brand/gancho-mark-green.svg` | No — board hoists `fill`/`stroke`/caps/joins to `<svg>`; repo sets them per element (caps/joins only on `<path>`), has `width="96" height="96"`, `xmlns`, `role="img" aria-label="gancho"`, literal `#34C759` and explicit closing tags | Yes — identical circle, path `d`, strokes 7 / 11 (round caps on a closed circle render the same) |
| §2 macOS tile | `Resources/Brand/gancho-mark.svg` | No — gradient id `gbM5` vs `g`, `#FFFFFF` vs `#ffffff`, attributes on `<g>` vs per element | Yes — same gradient (`#43D267`→`#2BB14E`, y 8→88), rect 8/8/80/80 rx 20, transform `translate(48,48) scale(0.8) translate(-41,-45)` |
| §2 iOS master | `Resources/Brand/gancho-appicon.svg` | No (same serialisation differences; repo has `width/height 1024`) | Yes — full-bleed rect, gradient y 0→96, scale 0.92 |
| §2 "iOS as shown by the system" | none (adds `clipPath` rx 21.5) | n/a | illustration of the system mask only |
| §3 template (108, 18, 16, 12 pt), strokes 9 / 13 | no SVG file; drawn in code `GanchoMenuBarCommand.swift:233-261` | n/a | Yes — code converts the same path to AppKit y-up: stem (50,64)→(50,39), arc centre (42.5, 26.01) r 15, 60°→120° clockwise (the 300° large arc), barb (31.5, 48.5), eye oval rect (42, 64, 16, 16); `lineWidth` hook 13 / eye 9; `side = 18`; `NSColor.black`; `isTemplate = true` |
| §3 Live Activity tiles | `GanchoMark.imageset/gancho-mark.svg` | No (serialisation) | Yes (same as macOS tile) |
| §5 clear-space crop | `gancho-mark-green.svg` geometry | n/a | Yes (viewBox crop `16.5 6.5 52 90`) |
| Website inline mark | `site/index.html:424` | n/a | Same geometry, `currentColor` |

App-icon PNGs checked visually (`icon_256.png`, `AppIcon-1024.png`): tile with transparent margin / full bleed, mark off-centre right as the vectors predict.

---

## Coverage

| Board element | Covered by |
|---|---|
| Header strip (ID, title, tag, "checked against main") | context only |
| Intro paragraph | context only |
| "Not adopted" note | GC-V7-1 (supersedes 24-grid hook on Onboarding / MenuBarDark / iPhoneSurfaces boards) |
| §1 The mark, single source | GC-V7-1 — kept, no change (documentation) |
| §2 App icon tiles (macOS, iOS master, iOS system mask) | GC-V7-1 — kept, no change |
| §3 template + light/dark menu-bar mocks | GC-V7-1 — kept, no change (already shipped in code) |
| §3 Status states strip | GC-V7-1 — kept, no change (SF Symbols) |
| §3 Live Activity tiles 19/20/24/38 | GC-V7-1 — kept, no change |
| §3 Widget header strip `Recent clips` | GC-V7-1 — new work (checklist row 7) |
| §4 Colour tokens | GC-V7-1 — kept, no change; text-contrast note relates to SY-V4-3 / B-GC-02 |
| §5 Clear space and minimum size | GC-V7-1 — guidance only |
| §6 Do and don't | GC-V7-1 — guidance; "Don't paperclip" drives rows 7–9 |
| §7 rows 1, 2, 3, 5, 6, 10, 12 (Shipped) | GC-V7-1 — kept, no change |
| §7 row 4 iOS dark/tinted (Optional) | GC-V7-1 — optional, not scheduled |
| §7 rows 7, 8, 9 (To apply) | GC-V7-1 + owner decision 2 — new work |
| §7 row 11 Keyboard (None) | kept, no change |
| §7 row 13 README (Optional) | GC-V7-1 — optional, not scheduled |
| Numbered pins | none drawn on this board |

---

## Feasibility

### GC-V7-1 — Brand mark source of truth and rollout (UI)

**What changes:** nothing in the vectors, icons, menu bar, Live Activity or site. Three SF `paperclip` call sites become the brand mark (owner decision 2). Optional rows 4 and 13 only if the owner asks.

**A. Widget header — `Apps/GanchoWidgets/RecentClipsWidget.swift:89`**
- Today: `Image(systemName: "paperclip").font(.caption.bold()).foregroundStyle(.tint)` inside `header` (`HStack(spacing: 5)`), next to `Text("Recent clips")` (`.caption.bold()`, `.secondary`).
- Board: bare mark as a template, 12 pt, strokes 9 / 13.
- Exists: `GanchoMark.imageset` in the widget catalog (TILE, strokes 7 / 11 — wrong variant for 12 pt).
- New: a single-colour template rendering of the hook with strokes 9 / 13. No such SVG exists in `Resources/Brand`; the 9 / 13 variant only exists as AppKit drawing (`hookImage`, private, macOS-only). Options: (a) new imageset in `Apps/GanchoWidgets/Assets.xcassets` (same path `d`, strokes 9 / 13, `template-rendering-intent: template`, preserves vector); (b) a SwiftUI `Shape` of the same path in `GanchoDesign` usable by widgets and Mac. Either copies the Resources/Brand path, satisfying "never retrace".
- Keep 12 pt frame and the existing `HStack(spacing: 5)`.

**B. Mac onboarding header — `Apps/GanchoMac/OnboardingView.swift:58`**
- Today: `Image(systemName: "paperclip").font(.system(size: 44)).foregroundStyle(.tint)` in `valueStep`.
- Board: the TILE (`GanchoMark.imageset`), 44 to 56 pt.
- New: `Apps/GanchoMac/Assets.xcassets/GanchoMark.imageset/` (`gancho-mark.svg` copied byte-for-byte from `Resources/Brand/gancho-mark.svg` + `Contents.json` with `preserves-vector-representation`, mirroring the widget set). `project.yml` already sources all of `Apps/GanchoMac`, so no `project.yml` change expected; run `make project` if the generator needs it. Replace with `Image("GanchoMark").resizable().interpolation(.high).frame(width: N, height: N)` (as `ClipLiveActivity.swift:88-92`), `accessibilityHidden(true)` (decorative; title follows).

**C. Wrapped — `Apps/GanchoMac/WrappedView.swift:14`**
- Today: `Image(systemName: "paperclip").font(.system(size: 36)).foregroundStyle(.tint)`; the card is rendered to PNG by `ImageRenderer` at `:74`.
- Board: bare mark in brand green → `GanchoColors.brandGreen` (`GanchoColors.swift:21`), not `.tint` (accent follows the system). At 36 pt (≥ 24 pt) the master strokes 7 / 11 apply (§6 "Below 24 pt use the template strokes 9 / 13").
- New: bare-mark asset for the Mac (copy of `gancho-mark-green.svg`) or the shared `Shape` from A at strokes 7 / 11. Must render in `ImageRenderer` (vector asset or Shape both do).

**Dependencies:** none hard. Related: SY-V4-3 / B-GC-02 (green is a fill, never text — no text changes here). Supersedes the 24-grid hook on V4_Gancho_Onboarding / V4_Gancho_MenuBarDark / V4_Gancho_iPhoneSurfaces specs.

**Verify:**
- Unit (Swift Testing): if a shared `Shape` is added, test its path bounds at 96 match `x 22…63, y 12…91` (± stroke) and stroke widths 7/11 vs 9/13 per size class.
- Asset parity: a test or `scripts/check-site.sh`-style check that every copied `gancho-mark*.svg` is byte-identical to `Resources/Brand` (today's three copies already are).
- Grep gate: `grep -rn '"paperclip"' Apps` returns nothing in Swift.
- UI (XCTest): `ActivationFunnelUITests` already walks onboarding (`onboarding-continue`); capture the step-1 header by element and compare with this board §2 tile. `wrapped-card` id exists for Wrapped capture. Widget: visual check in the widget gallery / simulator (no widget UI tests in repo).
- `make lint` / `make test`; no new user-facing strings (no l10n impact).

**BLOCKED / open questions:**
1. Onboarding tile size: board says `44 to 56 pt`. Which value? (Today 44; changing it shifts the step-1 layout.)
2. Widget header tint: board draws the 12 pt mark in ink `#1D1D1F` beside ink text; code tints the glyph with `.tint` and greys the label `.secondary`. Keep `.tint` (accent) on the template, or primary ink? The board strip is an illustration, so current label styling is assumed to stay.

### Optional rows (not scheduled)
- Row 4 iOS dark/tinted icon: new PNGs + `appearances` in `Apps/GanchoiOS/Assets.xcassets/AppIcon.appiconset/Contents.json`. Needs owner OK.
- Row 13 README logo: `README.md` + `Resources/Brand/gancho-mark.svg` at 64 px. Needs owner OK.

No B-GC bug or SY item is realised on this board.

---

## Other findings (outside the 13 rows)

- Only three `paperclip` SF Symbol uses exist in app/package Swift: the three above. `project.yml:104` mentions "menu-bar paperclip" in a YAML comment (stale wording, not UI).
- `Apps/GanchoMenuBarHelper/main.swift:91` uses SF `link` as the glyph of the "last copied" menu row — a content glyph, not a brand slot; §6 "Don't" names `"link"` only "where the brand should appear".
- `Apps/GanchoiOS/IOSOnboardingView.swift:23` iOS onboarding hero uses SF `doc.on.clipboard.fill` 44 pt with `.tint` — a brand-like slot the board's list does not mention.
- `GanchoMenuBarCommand.swift:229` doc comment cites `assets/gancho-mark.svg` (design-system path), not `Resources/Brand/gancho-mark-green.svg`.
- `GanchoWelcome_Current` draws the step-1 paperclip at 48 pt; code is 44 pt (code wins).

---

## Owner notes

- Pick: GC-V7-1 = `pick`, no note.
- Owner decision 1: "Keep the current app icon. V4_Gancho_Brand is the source of truth: exact SVG of Resources/Brand, 18 pt menu-bar template, a 13-step "Apply to the app" list with repo paths (GC-V7-1)."
- Owner decision 2: "Replace SF Symbol "paperclip" with the brand mark at OnboardingView.swift:58, RecentClipsWidget.swift:89, WrappedView.swift:14."
- Comment thread (Onboarding/Brand, resolved): board glyph was not the real icon; real icon kept; V4_Gancho_Brand created; three "paperclip" spots pending; old glyph recorded as "not adopted".
