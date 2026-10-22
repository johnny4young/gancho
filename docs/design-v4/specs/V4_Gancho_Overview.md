# V4_Gancho_Overview — spec

- **Board:** `V4_Gancho_Overview.dc.html` (canvas page "Gancho v4", position x 0 / y 160).
- **Canvas size:** 1600 × 1506 pt (HTML root and `canvas.json` agree). Board title in the canvas: `Gancho v4 · overview`. HTML `<title>`: `Gancho v4 overview`.
- **What it shows:** no app UI. It is the index of the Gancho v4 pass: what v4 is, what was kept, dropped and shipped since v2, the board-to-ID map, the 2026-10-17 screenshot pass, the novel boards and the Oct 18 triage. Every string on it is board copy (context), not app copy.
- **Related Current boards (reference only):** the 15 chips under `Current boards (15)` map to `GanchoPanel_Current` (04), `GanchoPanelActions_Current` (05–06), `GanchoPanelColorImage_Current` (07–08), `GanchoPanelEmpty_Current` (09), `GanchoWelcome_Current` (01–03), `GanchoSettings_Current` (10–13), `GanchoSettingsMore_Current` (14–16), `GanchoPaywall_Current` (17), `GanchoPrivacyCenter_Current` (18), `GanchoMCPAccess_Current` (19), `GanchoIntelligence_Current` (20), `GanchoMenuBar_Current` (21), `GanchoLibrary_Current` (22), `GanchoSnippetEditor_Current` (23), `GanchoPhone_Current` (iPhone, kept).

## Board frame

- Root: 1600 × 1506, radius 12, background `#ECEDF0`, padding 24 (top/bottom) × 28 (left/right), vertical stack with 14 gap.
- Board font: `-apple-system, "SF Pro Text"`; mono runs `ui-monospace, "SF Mono"`. Ink `#1D1D1F`, secondary `#5B5B61`, body `#3A3A3F`.
- Order top to bottom: (1) header row, (2) four-column card grid (fills remaining height), (3) board table card, (4) pass card (three columns), (5) NOVEL card, (6) TRIAGE strip.

## 1 · Header row

Horizontal, bottom-aligned, gap 16; spacer between title block and paragraph.

- Eyebrow, 11 pt / 700, uppercase, letter-spacing .08em, `#1F7A3A`:
  `Gancho · proposal v4 · 2026-10-17 · consolidates v1 + v2 + v3 against main @ 486201d (0.10.2 prep)`
- H1, 28 pt / 800, letter-spacing −.02em, 4 pt above:
  `v4 · the current app, one step further on every screen`
- Right paragraph, max width 520, 12.5 pt, line-height 1.5, `#5B5B61` ("current" bold):
  > The owner’s rule for this pass: compare each proposal with the **current** UI and only propose what beats it. The panel and the iPhone app absorbed most of v2 and v3 since the boards were drawn; v4 keeps that work as the baseline and closes the remaining gaps.

## 2 · Four-column grid

Columns 1.05fr · 1fr · 1fr · 1.1fr, gap 14. Each card: white, radius 14, padding 14, border 1 px `rgba(0,0,0,.06)`, vertical gap 8, clipped. Card title 14 pt / 800 with a 10 × 10 swatch (radius 3), gap 8. Bullet list: padding-left 16, 11.5 pt, line-height 1.45, `#3A3A3F`, gap 5; bold lead-ins as drawn. Text below is verbatim (bold = `**`, mono = backticks).

### 2a · `What v4 is` (swatch `#34C759`)

> - **One proposal, built on v0.10.2 (main @ 486201d).** Every board shows the current screen or names it, then the v4 evolution. Nothing the app does is removed; relocations are written on the board.
> - **Rule of the merge:** the code wins over the v2 boards and over the site screenshots (which predate the one-toolbar panel and the hero peek).
> - **Language:** brand green #34C759 / #30D158 with dark text on fills, kind tints from `kindTint`, board colours from `BoardIdentityColor`, radii 8 / 10 / 14, type 15 / 13 / 12 / 11 on the Mac and Dynamic Type on iOS.
> - **Motion (GC-37…42):** the code already has the token pair `GanchoMotion.quick` (0.18 s snappy) and `smooth` (0.22 s), blur-replace swaps and a Reduce Motion gate; v4 adds no third curve. Press 80 ms · settle 180 ms · leave 140 ms ease-in stay as the rule for anything new.

### 2b · `Kept from v1 · v2 · v3` (swatch `#1D1D1F`)

> - **v1:** search modes as a visible group (now pills in the field), masked secret rows with their lifetime, dark panel surfaces.
> - **v2:** keys drawn on the verbs, the content as a card with a kind edge, footer that lists the keys for the current state, iPhone board chips and swipe actions.
> - **v3:** Direction A (list + stage) as the only direction; states GC-05/07/08/09/10/12; one Transform (GC-11); image Translate and eyedropper (GC-15/16); settings status-first, concealed rule, retention timeline, verify group (GC-17/19/20/21); ambient rule, mini-panel menu, hook badges (GC-23/24/25); iPhone detail, boards, iPad, drag-out, onboarding (GC-27/28/33/34/35/36).
> - **Current app:** everything in the green “kept” strips — it is the base, not a competitor.
> - **Design notes folded in (gap pass, 2026-10-17):** the first panel redesign (diagnosis, A/B/C, PR plan), “Pasteboard y Settings Capture” (iOS status row, Add app menu, built-in exclusions) and “Texto en la imagen” (OCR in the peek, typography, iOS parity). Each idea is listed on the Archive board with where it lives now.
> - **Recovered in the gap pass:** the motion storyboard (Motion board), share sheet, large widget, Live Activity actions, keyboard inserted mark and iOS text-in-image (iPhoneSurfaces), Library kind chips + sort, and the colour hero with a contrast check (Peek).

### 2c · `Dropped, and why` (swatch `#FF3B30`)

> - **GC-02 single column** and **GC-03 filmstrip**: the panel's minimum is 720 pt and ⌘G gallery already covers visual browsing inside the same window.
> - **v2 iPhone orb + floating cards**: the orb duplicated the system Paste control (the only banner-free path) and the cards hid the native list, swipe actions and Dynamic Type.
> - **v2 2×2 action grid**: the shipped dock (verbs in one row, key under each, keyboard-walkable) is better; v4 adds Stack to it.
> - **GC-13/14/15, GC-18, GC-30, GC-32, GC-40**: shipped in 0.9–0.10 (OCR regions, per-line copy and Translate, denylist identity, keyboard board chips, Live Activity, swipe actions) — documented as kept, not redrawn.
> - **GC-22 per-board sync**: deferred — sync is a global Pro toggle on the private CloudKit database; per-board scoping needs schema work and is not a UI change.
> - **v2 transient “Hidden · from 1Password” row** and the Library “Sensed, not stored” scope: concealed copies never get a row; they count in the receipt and the Privacy status tile.
> - **Gallery date scrubber, “Copy a sample” button, footer size preset**: small v1 / note ideas superseded by date headers, the live onboarding step and the ⌘/ sheet (reasons on the Archive board).

### 2d · `What changed in the app since v2 (the baseline)` (swatch `#32ADE6`)

> - **Mac panel** now has one toolbar (boards · types · app · save filter), a hero peek with kind pill, title edit, insight strip, Transform / Smart paste menus, More-actions chips and the action dock with keys; footer with sync, capture, paste-stack strip, hints and ⌘/.
> - **States shipped:** capture notice banner (paused · private · denied · screen share · storage), multi-select bar, board picker ⌘B / ⇧⌘B, snippet banner, Ask gancho, By meaning + Related by meaning, ⌘G gallery, text size and panel size presets, translucency and ambient toggles.
> - **Images:** Live-Text-style regions, per-line copy, secret hold-back, Copy text ⇧⌘C.
> - **iOS:** Liquid Glass bottom bar with search + UIPasteControl, board rail with identity, filter menu by type and app, pinned + date sections, peek sheet with detents, reuse banner, three empty states, iPad split view with hardware shortcuts, boards home, Pro screen, Intelligence, Privacy Center with unreadable-clip repair.
> - **Settings:** sidebar of seven tabs, denylist with icons and suggestions, retention per kind, text recipes, MCP access, backups, Wrapped.

## 3 · `Boards and the GC-IDs each one realises`

Card: white, radius 14, padding 12 × 14, border `rgba(0,0,0,.06)`. Title 13 pt / 800, 6 below. Table full width, 11 pt; header row `#5B5B61` / 700, cells padding 4 × 6; body rows separated by a 1 px `rgba(0,0,0,.07)` top rule; board name bold; size `#5B5B61`. Each ID is a chip: height 18, padding 0 × 6, radius 7, `#E5E5EA` fill, `#1D1D1F` ink, mono 10 pt / 800, letter-spacing .04em.

Headers: `Board` · `Size` · `Realises`. Rows verbatim:

| Board | Size | Realises |
|---|---|---|
| `Panel` | `1900 × 1380` | `GC-01` `GC-06` `GC-08` `GC-10` `GC-11` `GC-25` |
| `PanelStates` | `2400 × 1340` | `GC-05` `GC-07` `GC-08` `GC-09` `GC-10` `GC-12` |
| `Peek` | `2290 × 900` | `GC-11` `GC-13` `GC-14` `GC-15` `GC-16` |
| `MenuBarDark` | `1640 × 1060` | `GC-04` `GC-23` `GC-24` `GC-25` |
| `Motion` | `1760 × 1115` | `GC-37` `GC-38` `GC-39` `GC-41` `GC-42` |
| `Library` | `1260 × 1385` | `GC-17` `GC-28` |
| `Settings` | `1640 × 1660` | `GC-17` `GC-18` `GC-19` `GC-20` `GC-21` |
| `iPhone` | `1700 × 1100` | `GC-26` `GC-27` |
| `iPhoneFlows` | `2240 × 1150` | `GC-27` `GC-28` `GC-21` |
| `iPhoneSurfaces` | `1760 × 1180` | `GC-29` `GC-30` `GC-31` `GC-32` |
| `iPad` | `1400 × 1140` | `GC-33` `GC-34` |
| `Onboarding` | `2000 × 1140` | `GC-35` `GC-36` |
| `Archive` | `1600 × 1640` | `GC-43` |

### Reconciled board → ID map (derived, not drawn)

The drawn table is the v3-era map. The catalog `board` field, the "Extended, same ids" line (section 5) and the Archive board move several IDs. Sizes checked against `canvas.json`: all match except Archive (canvas 1600 × 1760, table says 1600 × 1640). Brand, Novel and Novel2 are not in the table.

| Board (canvas size) | Catalog items (pick state) | Legacy IDs from the drawn table and where they went |
|---|---|---|
| Brand (1600 × 1820) | GC-V7-1 | — (not in table) |
| Novel (2400 × 2212) | GC-09, GC-10, GC-25, GC-V6-1…4 | — (not in table) |
| Novel2 (2400 × 2212) | GC-V4-1, GC-11, GC-12, GC-20, GC-V6-5…8 | — (not in table) |
| Panel | GC-01, GC-V4-2, GC-V4-3, GC-V4-4, GC-V5-3, GC-V5-6 | GC-06 shipped (capture notice banner); GC-08 → PanelStates; GC-10, GC-25 → Novel; GC-11 → Novel2 |
| PanelStates | GC-05, GC-07, GC-08 | GC-09, GC-10 → Novel; GC-12 → Novel2 |
| Peek | GC-16, GC-V4-14 | GC-11 → Novel2; GC-13/14/15 shipped (PeekImageText) |
| MenuBarDark | GC-04, GC-23, GC-24, GC-V5-1 | GC-25 → Novel |
| Motion | GC-V4-22 (maybe), GC-V4-23, GC-V4-24 | GC-37/38/39/41/42 → GC-V4-21…24 (V4-21 shipped, V4-20 skipped) |
| Library | GC-V4-5, GC-V4-6, GC-V4-7, GC-V4-13 | GC-17 → Settings; GC-28 → iPhoneFlows (see open question 1) |
| Settings | GC-17, GC-19, GC-21, GC-V5-2, GC-V5-4, GC-V5-5 | GC-18 shipped; GC-20 → Novel2 |
| iPhone | GC-26, GC-V4-8, GC-V4-9, GC-V4-10, GC-V4-11 | GC-27 → iPhoneFlows |
| iPhoneFlows | GC-27, GC-28, GC-V4-12 | GC-21 → Settings (catalog) |
| iPhoneSurfaces | GC-V4-15…19 | GC-29 → GC-V4-15; GC-30 shipped (+GC-V4-19); GC-31 large → GC-V4-16; GC-32 actions → GC-V4-17 |
| iPad | GC-33, GC-34 | — |
| Onboarding | GC-35, GC-36 | — |
| Archive (1600 × 1760) | GC-V4-20 (skip) | GC-43 = the catalog + Archive itself |
| System Components | SY-V4-3, SY-V4-6, SY-V4-7, SY-V4-8, SY-V4-9 | — |

## 4 · Pass card (three columns)

Card: white, radius 12, padding 16 × 20, grid 1.1fr · 1fr · 1fr, gap 28. Lists 11.5 pt / 1.45, `#3A3A3F`, padding-left 16, 8 above.

### 4a · `Pass 2026-10-17 · screenshots are the source of truth` (14 pt / 800, swatch `#1D1D1F`)

> - 23 Mac screenshots (v0.10.1 build) and main @ a251a658 (v0.10.2) re-read against every v4 board and all 49 catalog items.
> - **Catalog 49 → 61:** 2 moved to the Archive as shipped (GC-15, GC-V4-21), 7 corrected or narrowed (GC-24, GC-V4-3, GC-V4-6, GC-V4-7, GC-V4-11, GC-21, GC-35), 6 new (GC-V5-1…6) + 8 from research (GC-V6-1…8); 7 items extended by the novel boards.
> - **Decided:** chip text goes from 10 pt (.caption) to 11 pt (.subheadline) — GC-V5-6, consequences on the Panel board.

### 4b · `New this pass` (13 pt / 800)

> - GC-V5-1 menu shows the real panel shortcut (MenuBarDark)
> - GC-V5-2 accent text and Privacy hero that pass AA (Settings)
> - GC-V5-3 untitled image rows say what they are (Panel)
> - GC-V5-4 settings sidebar ring follows selection (Settings)
> - GC-V5-5 Intelligence pipeline fits its window (Settings)
> - GC-V5-6 chip text 11 pt, decided (Panel)

### 4c · `Current boards (15)` (13 pt / 800)

Chips: height 20, padding 0 × 8, radius 999, `#F2F2F5`, 11 pt / 600, margin right 4 / bottom 4, wrapping. Verbatim, in order:
`Panel (04)` · `Panel actions (05–06)` · `Colour + Images (07–08)` · `No matches (09)` · `Welcome (01–03)` · `Settings ×4 (10–13)` · `Settings ×3 (14–16)` · `Paywall (17)` · `Privacy Center (18)` · `MCP Access (19)` · `Intelligence (20)` · `Menu bar (21)` · `Library (22)` · `Snippet editor (23)` · `iPhone (kept)`

## 5 · NOVEL card

White, radius 12, padding 16 × 20, 3 pt green left edge (inset shadow `#34C759`). Title row 14 pt / 800, gap 10: badge `NOVEL` (height 20, padding 0 × 8, radius 6, `#34C759` fill, `#0B2A14` ink, 10.5 pt / 800) + `Two boards after this one: Novel (capture and paste) and Novel2 (find, transform and trust)`. Below, three columns (gap 24, 8 above), 11.5 pt / 1.45, `#3A3A3F`:

> **Baseline to beat.** macOS 26 Spotlight clipboard (⌘Space ⌘4): a plain time list, plain text only, 8 h by default, may keep third-party passwords. Paste 7: cards, pinboards, Intelligent Clipboard prediction, MCP. Gancho wins on privacy, previews and keyboard flow; the novel boards close the gaps in prediction, gestures and live trust.

> **New (GC-V6-1…8):** Up next, double-copy merge, copy-time HUD, notch shelf, jump to context, live agent reads, suggested snippets + placeholders, iPhone keyboard Up next + Control Center capture state.

> **Extended, same ids:** GC-V4-1 filter tokens · GC-09 masked everywhere · GC-10 stack cursor · GC-11 step pipeline · GC-12 prompt-to-transform · GC-20 retention dial + forget · GC-25 capture-state glyph. Research: research/clipboard-ui.md, 14 patterns with sources.

## 6 · TRIAGE strip

Min height 40, padding 9 × 16, radius 12, white, border `rgba(0,0,0,.08)`, 3 pt green left edge, 13 pt / 1.4. Badge `TRIAGE` (height 20, padding 0 × 8, radius 6, `#1D1D1F` fill, white ink, 10.5 pt / 800, letter-spacing .06em), gap 12, then:

> **Triage · Oct 18, 2026** — 60 pick · 1 maybe · 1 skip of 62 (GC-V7-1 brand source of truth picked Oct 19). Skipped items moved to Archive; maybe/pending items are tagged on their boards.

Counts verified against the catalog (62 Gancho items): 60 pick, 1 maybe (GC-V4-22, Motion), 1 skip (GC-V4-20, Archive). 49 − 2 + 6 + 8 = 61, + GC-V7-1 = 62. The seven "extended" items match the seven listed in section 5.

## Implementation notes (not UI)

The whole board is annotation. No string here ships in the app. Notes that bind other boards are restated as rules below.

## Design language (verbatim rules + code anchors)

| Rule as drawn | Value | Code today |
|---|---|---|
| Brand green | `#34C759` light / `#30D158` dark | `GanchoTokens.Palette.brandGreen`, `Packages/GanchoKit/Sources/GanchoDesign/GanchoColors.swift:21` — exact match |
| "dark text on fills" | Board ink on green: `#0B2A14` (light), `#04210D` (dark) | `ContrastingForeground` (`GanchoDesign/ContrastingForeground.swift`) resolves to pure black/white by luminance; the two dark-green inks are not tokens. SY-V4-3: Paste "dark ink (6.8:1)", green text `#1C7A37` (5.4:1), Delete `#D70015` |
| Accent | follows system accent, brand green under Multicolor | `Palette.accent`, `GanchoColors.swift:68-79` (`controlAccentColor` at :72); using it as text ink is B-GC-02 (GC-V5-2) |
| Kind tints from `kindTint` | url `#32ADE6`; code/json/uuid `#5856D6`; image `#FF9F0A`; file `#007AFF`; color `#5AC8FA`; jwt/secret/card `#FF3B30`; default `#8E8E93` | `GanchoDesign/Components.swift:104` |
| Board colours from `BoardIdentityColor` | blue `#2E70D1`, orange `#F08C08`, teal `#17999E`, pink `#D4547D`, purple `#874AB8`, brown `#996633` (closed list) | `GanchoDesign/BoardColors.swift:7` |
| Radii 8 / 10 / 14 | 8 tiles/cards, 10 rows/fields, 14 panel/hero/dock | `GanchoTokens.Radius.card` 8, `.md` 10, `.lg` 14 (`GanchoTokens.swift`); `.sm` 6 and `.xl` 20 also exist and are not in the v4 rule |
| Type 15 / 13 / 12 / 11 on the Mac | 15 title, 13 body, 12 secondary, 11 caption/chips | `GanchoTokens.FontSize` has 11/13/15/22 (no 12); panel text uses `panelFont(PanelTextStyle)` scaled by `panelTypeScale` (Small 0.9, Standard 1, Large 1.15), `GanchoDesign/PanelTypography.swift` |
| Dynamic Type on iOS | system text styles | `PanelFontModifier` uses `Font.system(style.textStyle)` on iOS |
| Chip text 11 pt (GC-V5-6, decided) | `.caption` 10 pt → `.subheadline` 11 pt; chip height 22 | `railChipLabel` uses `.panelFont(.caption…)` at `Apps/GanchoMac/PanelView.swift:918` and `:922`. Catalog GC-V5-6: footer, ⌘N and section headers stay at 10 pt |
| Motion: two curves | `GanchoMotion.quick` = `.snappy(duration: 0.18, extraBounce: 0)`; `smooth` = `.smooth(duration: 0.22)` | `GanchoDesign/GanchoMotion.swift:7,9` — exact match |
| Blur-replace swaps + Reduce Motion gate | swap = blur-replace, `.identity` under Reduce Motion; animations `nil` under Reduce Motion | `GanchoMotion.replace(reduceMotion:)`, `animation(_:reduceMotion:)` — exist |
| "v4 adds no third curve" | Press 80 ms · settle 180 ms · leave 140 ms ease-in for anything new | 80 ms press and 140 ms ease-in are not in `GanchoMotion` (see open question 2) |

Shared stylesheet (defined in this board's `<helmet>`, not drawn here; the other v4 boards draw with it): chip 22 h, radius 999, 11 pt / 600, active fill `#34C759` + ink `#0B2A14` (dark `#30D158` + `#04210D`); search field 44 h, 15 pt; toolbar padding 6 × 12, gap 4; list column 440 wide; row 50 h, radius 10, gap 3, selected wash `rgba(52,199,89,.14)` (dark .16) with a 3 pt green bar inset 8 top/bottom; kind tile 36 × 36, radius 8; section header 10 pt / 700 uppercase; hero radius 14, host 24 pt / 800; dock radius 14, padding 4, key 58 h, primary flex 2, key label 10 pt mono; footer 30 h, 11 pt, keycaps 16 h / 9 pt; panel radius 14 on `#F5F5F7` (dark `#1C1C1E`, hero `#2C2C2E`), hairlines `rgba(0,0,0,.08)` / `rgba(255,255,255,.1)`; secondary text `#5B5B61` (dark `#A1A1A6`); `@media (prefers-reduced-motion: reduce)` disables all transitions.

## Cross-board rules (every other Gancho v4 board must obey)

1. **Baseline first.** Each board shows the current screen (or names it), then the v4 evolution. Nothing the app does is removed; any relocation is written on the board.
2. **Code wins** over v2 boards and site screenshots. For this pass the 23 Mac screenshots (v0.10.1) and main @ a251a658 are the source of truth.
3. **Only propose what beats the current UI** (owner rule, 2026-10-17). The current app ("kept" strips) is the base, not a competitor.
4. **Each piece of data appears once per screen** (owner cross-app rule).
5. **Colour:** brand green `#34C759` / `#30D158` with dark ink on green fills; kind colour only from `kindTint`; board colour only from `BoardIdentityColor`; one saturated control per surface (SY-V4-8); accent text must pass 4.5:1 (GC-V5-2).
6. **Radii** 8 / 10 / 14 only.
7. **Type** 15 / 13 / 12 / 11 pt on the Mac through `panelFont` (scales with Text size); Dynamic Type on iOS. Chips 11 pt `.subheadline` (GC-V5-6); 10 pt only for footer, ⌘N badges and section headers.
8. **Motion:** only `GanchoMotion.quick` (0.18 s snappy) and `smooth` (0.22 s); swaps via `GanchoMotion.replace`; everything behind the Reduce Motion gate. New motion uses press 80 ms · settle 180 ms · leave 140 ms ease-in. No new curve.
9. **Panel minimum 720 pt** wide (`PanelView.swift:300`, `PanelController.swift:27` = 720 × 460). No single-column (GC-02) or screen-edge filmstrip (GC-03); visual browsing stays in ⌘G gallery.
10. **Dock:** verbs in one row, key under each, keyboard-walkable; v4 adds Stack. No 2×2 action grid.
11. **iPhone:** keep the system Paste control (UIPasteControl) as the only banner-free path; native list, swipe actions and Dynamic Type stay. No orb, no floating cards.
12. **Concealed copies never get a row** anywhere (no "Hidden · from 1Password" row, no "Sensed, not stored" scope); they count only in the receipt and the Privacy status tile. Matches the AGENTS.md privacy rule.
13. **Sync stays one global Pro toggle**; no per-board sync UI (GC-22 deferred, needs schema work).
14. **Shipped items are kept, not redrawn:** GC-06, GC-13, GC-14, GC-15, GC-18, GC-30, GC-32 (actions are new, GC-V4-17), GC-40, GC-V4-21, and the shipped parts of GC-24, GC-V4-3, GC-V4-7, GC-V4-11, GC-35.
15. **Superseded, do not revive:** gallery date scrubber (date headers), "Copy a sample" (live onboarding step), footer size preset (⌘/ sheet and General).
16. **Annotations are not UI.** `v4 · …`, `kept:`, `needs:`, `exists`, `Reuses`, `proposal`, `MAYBE`, `PENDING DECISION`, pins, footnotes and Build-order notes never become app copy.
17. **Triage tags:** skipped items live only on Archive (GC-V4-20); maybe/pending items carry their tag on their board (GC-V4-22 on Motion).
18. **Brand:** the current app icon stays; V4_Gancho_Brand is the source of truth (GC-V7-1).
19. **Repo rules:** new strings in String Catalogs EN + ES; a11y ids kebab-case with semantic suffixes; macOS-26-only APIs (Liquid Glass, FoundationModels) behind `#available`; no clipboard content in logs.

## Coverage

| Card / frame | Covered by |
|---|---|
| 1 · Header (eyebrow, H1, owner-rule paragraph) | context only; rules 1–3 |
| 2a · What v4 is | context only; design language + rules 1, 2, 5–8 |
| 2b · Kept from v1 · v2 · v3 | context only; IDs listed point to their boards (see reconciled map) |
| 2c · Dropped, and why | Archive (GC-02, GC-03, GC-22, v2 orb/cards/grid/concealed row, scrubber, sample button, footer preset); shipped kept (GC-13/14/15, GC-18, GC-30, GC-32, GC-40); rules 9–15 |
| 2d · What changed in the app since v2 | kept, no change (baseline) |
| 3 · Boards and the GC-IDs each one realises | context only; superseded by catalog `board` field (reconciled map); open question 1 |
| 4a · Pass 2026-10-17 | context only; GC-V5-6 decision → Panel |
| 4b · New this pass | GC-V5-1 (MenuBarDark), GC-V5-2/4/5 (Settings), GC-V5-3/6 (Panel) |
| 4c · Current boards (15) | context only (reference boards) |
| 5 · NOVEL card | GC-V6-1…4 (Novel), GC-V6-5…8 (Novel2); extended GC-V4-1, GC-09, GC-10, GC-11, GC-12, GC-20, GC-25 |
| 6 · TRIAGE strip | context only; GC-V4-20 (Archive), GC-V4-22 (Motion, maybe), GC-V7-1 (Brand) |
| Numbered pins | none drawn |

## Feasibility

No catalog item, B-GC bug or SY item has `board = V4_Gancho_Overview.dc.html`, so there are no feasibility blocks here. Each ID is specified on its own board. The design language rules above list where each one lives in code and what is missing (dark-green ink tokens, 12 pt size token, 80 ms / 140 ms motion constants, chip size change).

### Open questions

1. **BLOCKED: board map.** The drawn table lists GC-17 and GC-28 under Library and GC-21 under iPhoneFlows, while the catalog places GC-17/GC-21 on Settings and GC-28 on iPhoneFlows, and Library's catalog items (GC-V4-5/6/7/13) are absent from the table. Should Library's spec cover the GC-17 status tiles and GC-28 board identity as well, or is the table just stale? (Precedence would favour the board, but the Overview's own "Extended" line and the Archive already move IDs; not resolved here.)
2. **BLOCKED: motion.** "v4 adds no third curve" sits next to "leave 140 ms ease-in", and the Motion board calls it "the two code curves plus one 140 ms departure". Is the 140 ms ease-in (and the 80 ms press) a new `GanchoMotion` token or a local constant per call site?
3. **Dark ink.** The board draws `#0B2A14` / `#04210D` on green; code uses `ContrastingForeground` (pure black). Does SY-V4-3 require these exact inks as tokens, or is black acceptable?
4. **Archive size.** Table says 1600 × 1640; the canvas board is 1600 × 1760 (cosmetic).

## Owner notes

- No pick note targets this board.
- Owner rule (2026-10-17): compare every proposal with the current UI and only propose what beats it; code wins over v2 boards and site screenshots. Drawn as the header paragraph and "Rule of the merge".
- Triage Oct 18, 2026: 60 pick · 1 maybe · 1 skip; GC-V7-1 picked Oct 19 (keep the current app icon; Brand board is the source of truth).
- The one "maybe", GC-V4-22 (Motion), carries the owner note: "no entiendo la utilidad de esto, pero siento que no es necesario".
- Cross-app owner rule: each piece of data appears once per screen.
