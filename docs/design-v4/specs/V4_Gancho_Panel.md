# V4_Gancho_Panel — spec

- **Board:** `V4_Gancho_Panel.dc.html` (title tag `Gancho panel v4`)
- **Canvas:** 1900 × 1380, background `#ECEDF0`, radius 12, padding 24/28, vertical gap 14.
- **What it shows:** the macOS history panel at the Standard preset (864 × 540) twice — v0.10.2 as built (left) and the v4 proposal (right) — plus a "kept as is" strip, eight numbered notes, the decided chip-size change (GC-V5-6) and a 2026-10-17 review pass (GC-V4-3 correction, GC-V5-3).
- **Related Current boards (reference only):** `GanchoPanel_Current`, `GanchoPanelActions_Current`, `GanchoPanelColorImage_Current`.
- **Catalog items on this board:** GC-01, GC-V4-2, GC-V4-3, GC-V4-4, GC-V5-3, GC-V5-6. Bug: B-GC-04 (via GC-V5-3).
- Only light-mode panels are drawn. The board CSS defines dark tokens (`.panel.dark` `#1C1C1E`, text `#F2F2F7`, active chip `#30D158` on `#04210D`, hero `#2C2C2E`) but no dark artboard uses them.

---

## 0. Header strip

Left to right: ID tags `GC-01` (green tag `#34C759` on `#0B2A14`), `GC-06`, `GC-08`, `GC-10`, `GC-11`, `GC-25` (dark tags `#1D1D1F`/white; 22 h, radius 7, 11 px/800 mono); title `Panel · v4 is the current panel with its gaps closed` (22 px/800); subtitle `Left: v0.10.2 as built, redrawn from PanelView.swift, ClipPeek.swift, PanelStatusFooter.swift. Right: v4 — same keys, same privacy rules, nothing dropped; the changes are the numbered notes.`; right-aligned `Gancho · macOS · v4 · 864 × 540 Standard preset`.

Header ID tags are annotations, not UI.

---

## 1. Artboard "NOW · Current · v0.10.2 (from code)" (left, 864 × 540)

Label row: tag `NOW`, `Current · v0.10.2 (from code)`, small `pixel replica from screenshots: GanchoPanel_Current · selected row, link peek, capture paused`.

Context only: it shows today's panel. Differences from v4 are listed in §2.

Panel shell: 864 × 540, bg `#F5F5F7`, radius 14, border `rgba(0,0,0,.08)`, shadow `0 1px 2px rgba(0,0,0,.08), 0 22px 48px rgba(0,0,0,.22)`. Body = list column 440 pt + peek (flex). Hairline `rgba(0,0,0,.08)` between them; there is **no gap** between list and peek (one surface).

### 1.1 List column (440 wide)
1. **Search row**: 44 h, padding 0 14, gap 8, colour `#5B5B61`, bottom hairline. Magnifier 15 pt; input 15 px, placeholder `Search your clipboard` (`#8A8A8F`), a11y label `Search your clipboard`.
2. **Toolbar** (padding 6/12, gap 4, bottom hairline):
   - Boards rail (masked fade on the right 22 px): `All clips` chip active (checkmark 11 pt + text), `Favorites` glyph chip (star, outline), `New board…` glyph chip (plus).
   - Vertical divider 1 × 14, `rgba(0,0,0,.14)`, margin 0 4.
   - Filters rail: `All` active (checkmark + text); glyph chips `Links` (`#32ADE6`), `Code` (`#5856D6`), `Colors` (`#5AC8FA`), `Images` (`#FF9F0A`), `Secrets` (`#FF3B30`), `All apps` (dashed square), `Save filter` (13 pt line-decrease circle, no background).
   - Chip: 22 h, padding 0 7, capsule, bg `rgba(29,29,31,.07)`, text `#5B5B61` 11 px/600; active bg `#34C759`, text `#0B2A14` 700; glyph-only chip 22 × 22.
3. **By meaning row**: padding 6 12 2; button `By meaning`, 22 h, padding 0 9, border `rgba(0,0,0,.12)`, radius 6, white, 11 px/600.
4. **Section header**: `Today` … `5 clips` (sample). Padding 6 10 2, 10 px/700, tracking .06em, uppercase, `#5B5B61`.
5. **Rows** (gap 3, padding 2 6). Row 50 h, padding 0 8, radius 10, gap 10; tile 36 × 36 radius 8; title 13 px/600; preview 12 px `#5B5B61`; source line 10.5 px `#6E6E73`; ⌘N badge 16 h, padding 0 4, radius 5, 10 px/600 mono, bg `rgba(29,29,31,.08)`.
   1. code tile (`#5856D6` @16%): `Example · Swift` / `let greeting = "Hello"` (syntax: `let` `#A33EA3`, string `#2E7D32`) / `Xcode · now` / `⌘1` (sample)
   2. colour tile `#008080`: `Ocean` / `#008080` / `Figma · now` / `⌘2`
   3. **selected** link tile (gradient `#5BC4F0→#32ADE6`, monogram `E` `#0A2B3A`): `Synthetic link` / `https://www.example.com:8443/a%2Fb?q=a%26b#…` / `Safari · 7 s` / `⌘3`. Selected: bg `rgba(52,199,89,.14)` + 3 pt bar `#34C759` inset 8 top/bottom.
   4. image tile (thumbnail sample `#52BCCF` + orange dot `#F39B3A`): `Synthetic landscape` / `PNG · 1200 × 800` / `Vitrine · now` / pin glyph 10 pt `#6E6E73` + `⌘4`
   5. secret tile (lock, `#FF3B30` @16%, glyph `#C8231B`): `•••` / `•••`, no source line, `⌘5`.

### 1.2 Peek (padding 12 14, gap 10)
1. Header row (min 24 h, gap 8): kind pill `url` (link glyph; 20 h, padding 0 8, 11 px/700, bg `rgba(50,173,230,.16)`, text `#0B5C80`); title `Synthetic link` 14 px/700; `Edit title` wand button `#1F7A3A`.
2. Hero (padding 12 14, radius 14, bg gradient `#EAF6FD → #fff 60%`, border `rgba(0,0,0,.08)`): host `example.com` 24 px/800; URL `https://www.example.com:8443/a%2Fb?q=a%26b#section-2` 12 px mono `#5B5B61`; footer row `Content` (11 px `#5B5B61`) … `Edit` (12 px/700 `#1F7A3A`, wand 11 pt).
3. Insight strip (11 px `#5B5B61`): clock glyph + `7 sec`.
4. Two buttons (28 h, padding 0 10, radius 10, white, border, 12 px/600): `Aa` `Transform` ⌄; sparkles (`#1F7A3A`) `Smart paste` ⌄.
5. `More actions` chip with ⌄ (22 h).
6. Dock (`Actions` group; gap 4, padding 4, radius 14, bg `rgba(29,29,31,.06)`): `Paste` `⏎` (primary, flex 2, `#34C759`/`#0B2A14`), `Plain` `⌥⏎`, `Pin` `⌘P`, `Board` `⌘B`. Button 58 h, padding 7 2, radius 10, label 11 px/700, key 10 px mono at 75 %.

### 1.3 Footer (30 h, gap 12, padding 0 10, 11 px `#5B5B61`, top hairline)
Grey dot 6 pt `#6E6E73` + `Paused` … spacer … keycaps `↑` `↓` `navigate`, `→` `actions`, `⏎` `paste`, `Keyboard shortcuts (⌘/)` info button (13 pt). Keycap: 16 h, min-width 17, radius 4, 9 px/700.

---

## 2. Artboard "V4 · v4 proposal" (right, 864 × 540)

Label row: green tag `V4`, `v4 proposal`, small `same selection, capturing, stack of 2 waiting`.

Same shell and geometry as §1 unless stated.

### 2.1 Search row — pin 1 (GC-V4-1, drawn here; catalog board = Novel2)
Magnifier; input placeholder **`Search`** (a11y label stays `Search your clipboard`); segmented group `Search mode` (padding 2, capsule, bg `rgba(29,29,31,.07)`, gap 1): `Fuzzy` (selected: white pill, `#1D1D1F`), `Exact`, `Regex` (unselected `#5B5B61`) — each 20 h, padding 0 7, 10.5 px/700. Then toggle `Meaning` with sparkles (24 h, padding 0 9, capsule, bg `rgba(29,29,31,.07)`, `#5B5B61`, 10.5 px/700, not pressed). The separate `By meaning` row is gone.

### 2.2 Toolbar — pin 5 (GC-V4-3) + chip size (GC-V5-6)
- Boards rail: `All clips · 128` (active, checkmark; a11y label `All clips · 128`; count is sample), `Favorites` glyph chip (star filled `#FF9F0A`), `Work` (9 × 9 square dot radius 3 `#2E70D1` + name), `Brand` (dot `#F08C08` + name), `New board…` (plus).
- Divider, then filters rail identical to §1.1 (`All` active; Links, Code, Colors, Images, Secrets, All apps, Save filter).
- Chips drawn at 22 h / 11 px (GC-V5-6).

### 2.3 Section header and rows
`Today` … `5 clips`. Rows 1–4 identical to §1.1 (including row 4 preview `PNG · 1200 × 800` — see GC-V5-3 conflict). Row 5 changed — pin 7 (GC-09, catalog board = Novel):
- tile lock; title `Stripe key · masked`; preview `sk_live_•••••••••••• 4Q2v`; source `Terminal · 2 min`; expiry badge (20 h chip, bg `rgba(255,159,10,.18)`, text `#7A4B00`, timer glyph 9 pt) `9:41`; `⌘5`. All sample.

### 2.4 Peek
1. **Provenance header — pin 2 (GC-01)** (gap 6, wraps, min 24 h): kind pill `url`; chip app icon (10 × 10, radius 3, sample gradient `#4FC3F7→#1565C0`) + `Safari`; chip clock 10 pt + `7 s ago`; chip board dot (8 × 8 `#2E70D1`) + `Work`; spacer; green chip (bg `rgba(52,199,89,.14)`, text `#1F7A3A`, cloud-check 11 pt) `Synced · Mac + iPhone`. Chips: 20 h, padding 0 7, capsule, 11 px/600, `#3A3A3F` on `rgba(29,29,31,.07)`.
2. **Title row** (gap 8): `Synthetic link` 15 px/800 (−.01em); `Edit title` wand `#1F7A3A` 12 pt; caption `title written on-device` 10.5 px `#6E6E73`.
3. **Hero**: same card plus a 4 pt leading stripe in the kind tint `#32ADE6` (full height) *(not built: leading accent bars are banned; the kind shows through the card's tinted wash and the header chip)*. Host `example.com`; URL as §1.2; chip row (wrap, gap 4, margin-top 10): `decoded · /a/b?q=a&b`, `https`, `port 8443`, `#section-2`, and right-aligned `Edit` (wand 10 pt, `#1F7A3A`). The `Content` label is gone. The insight strip is gone.
4. **Transform — pin 4 (GC-11, catalog board = Novel2)**: one button (white, 28 h): wand 12 pt, `Transform`, keycap `⌘T` (16 h, 9.5 px), ⌄. Beside it 11 px `#5B5B61`: `recipes · text · code · smart paste · translate — one list, type to filter`. `Smart paste` button and `More actions` chip are gone.
5. **Board suggestion** (padding 6 10, radius 10, bg `rgba(52,199,89,.1)`, 11 px): sparkles `#1F7A3A` 12 pt, `Add to Brand?` (600), spacer, `Add` (700 `#1F7A3A`), `Dismiss` ✕ (11 pt `#6E6E73`). Exists today (`board-suggestion`); drawn at 11 pt (GC-V5-6).
6. **Dock** — pins 3 & 4: `Paste into Figma` `⏎` (primary, flex 2; GC-V4-2), `Plain` `⌥⏎`, `Pin` `⌘P`, `Board` `⌘B`, `Stack` `⌥⌘⏎` (layers glyph; GC-10).

### 2.5 Footer — pins 3, 4, 6
Left to right:
- Capture chip (pill 20 h, bg `rgba(52,199,89,.16)`, text `#1F7A3A`, dot 7 pt `#34C759`): `Capturing · Figma in front` (GC-V4-4 + GC-V4-2).
- cloud-check 12 pt + `Synced` (existing sync status).
- Stack chip (bg `rgba(94,92,230,.14)`, text `#3634A3`, layers 10 pt): `Stack 2` (GC-10).
- spacer; hints `↑` `↓` `move`; `→` `actions`; `⏎` `paste`; `⌘` `1–9` `nth`; `⌘` `/` `all keys`; info button `Keyboard shortcuts (⌘/)`.

Pin 6 states (text only, drawn as one state): green `Capturing · Figma in front`, amber `Paused · screen sharing`, indigo `Private mode · 58 min left`, red `Access denied`.

---

## 3. Strip "Already in v0.10.2 · kept as is"

White card (padding 12 14, radius 14). Tag `Already in v0.10.2 · kept as is` (bg `#E3F5E8`, `#1F7A3A`). Checkmark chips (22 h, 11 px):
`One toolbar: boards · types · app · save filter` · `Hero peek with kind pill, title edit, insight strip` · `Action dock with the key under every verb` · `Footer: sync · capture · paste stack strip · hints · ⌘/` · `⌘G gallery, Compact / Standard / Large, Text size` · `Capture banner (paused · private · denied · screen share)` · `Multi-select bar · board picker ⌘B · snippet banner` · `Ask gancho row · By meaning · Related by meaning` · `Ambient wash (off by default) · Reduce Motion gating` · `Masked secrets as ••• · expiry countdown under 1 h`

All are "kept, no change". Note: "insight strip" and the "By meaning" row are listed as kept yet the v4 artboard removes them (pins 2 and 1); the pins win.

---

## 4. Numbered notes (4-column grid)

### Implementation notes (not UI)
1. > **Search modes in the field.** Fuzzy · Exact · Regex already exist as `PanelSearchModel.mode` (fuzzy is the default) but have no control; the meaning toggle lives on its own 28 px row. v4 puts the three modes and Meaning as pills inside the 44 px field and drops the extra row, so GC-08's "four ways out" are visible before anything fails.
2. > **Provenance moves into the peek header.** Source app with its icon, age, boards and sync state sit beside the kind pill, so the hero rises and the insight strip under it disappears. All of it is already loaded by `ClipPeek.insightStrip` and `boardMembership`.
3. > **Paste names the app it pastes into.** `PasteBackWorkflow` already records `intendedTarget` (the frontmost bundle id); the dock's primary button and the footer chip show its name, so the user never guesses where ⏎ lands.
4. > **One Transform, with Stack in the dock.** Transform ⌄, Smart paste ⌄ and the More-actions chips become one searchable popover (GC-11, drawn on the Peek board). The dock gains Stack ⌥⌘⏎ so the paste queue — today only a context-menu item and a footer strip — has a visible verb (GC-10).
5. > **Scope and app chips carry identity.** The active scope shows its count; user boards keep their colour dot; the app filter shows the real app icon (`SourceApp.icon`) when one is chosen. Glyph-only rest state and the checkmark on the active chip stay — that is the WCAG rule the code already follows.
6. > **Footer state has a colour and a cause.** The capture chip reads **Capturing · Figma in front** in green, **Paused · screen sharing** in amber, **Private mode · 58 min left** in indigo, **Access denied** in red — the same badge the menu-bar hook shows (GC-06 · GC-25). Today the dot is green or grey only.
7. > **Secrets stay masked, but say how long.** The row shows the masked tail (`sk_live_•••• 4Q2v`, already the stored masked preview) and the live expiry badge the code renders under one hour; the peek adds Reveal 10 s (today the Mac peek has no reveal at all — iOS does). Drawn on the States board (GC-09).
8. > **Nothing removed.** Every verb of the current panel keeps its key: ⌥⏎ plain, ⌘P pin, ⌘B / ⇧⌘B boards, ⌘S snippet, ⌘Y preview, ⌘G gallery, ⇧⌘C OCR, ⌘↑ recall, ⌘1–9, esc. The cheat-sheet (⌘/) lists them, as today.

Pins 1–4 use green markers, 5–8 dark markers (no meaning stated).

---

## 5. Card "DECIDED · GC-V5-6 — Chip text is 11 pt"

White card, 2 pt inset green border `#34C759`, padding 16 20.

Left column (340 wide):
- Tag `DECIDED · GC-V5-6`, title `Chip text is 11 pt`.
- Text: **Was (v0.10.x):** chips use `PanelTextStyle .caption` = 10 pt at Standard (screenshots 04–09). **Decided by the owner (2026-10-17):** chips move one step up to `.subheadline` = 11 pt. All v4 boards already draw chips at 11 px; the peek board chips on the Mac boards were raised from 10.5 to 11 px in this pass.
- `WAS · 10 pt` sample row: chips 20 h, padding 0 8, radius 10, 10 px/600 — `All clips` (active `#74B652`, text `#111`, checkmark 10 pt), `Seed board 1` (dot 10 pt `#E8912D`), `Seed board 2` (`#E8912D`), `Seed board 3` (`#3D8F96`); inactive bg `#E4E4E6`, text `#4A4A4F`.
- `NOW · 11 pt` (`#1D6B2F`) same row: chips 22 h, padding 0 8, radius 11, 11 px/600, dots 11 pt.

Right three columns (12 px):

**Type mapping (Mac)**

| Text size | scale | was | now |
|---|---|---|---|
| Small | 0.9 | 9 pt | **9.9 pt** |
| Standard | 1.0 | 10 pt | **11 pt** |
| Large | 1.15 | 11.5 pt | **12.65 pt** |

> The chip glyph moves with it: `.caption` → `.subheadline` (glyph frame 12 → 13 pt). iOS / iPadOS already use `.subheadline` Dynamic Type on chips (CaptureView railChip): no change there.

**Geometry**
> - Height 20 → 22 pt (vertical padding stays 4 pt; the line grows from ~12 to ~13 pt).
> - Horizontal padding stays 8 pt titled / 6 pt glyph-only; capsule radius = half height.
> - Titled chips ~8 % wider. The boards rail in the 432 pt list column no longer fits All clips + Favorites + three boards: it scrolls (it is already a horizontal ScrollView) and the toolbar keeps its two-row layout earlier.
> - Footer, ⌘N badges and section headers stay at 10 pt (.caption2): they are labels, not chips.

**Components that change**
> - `PanelView.railChipLabel`: board, kind and app chips (also used by the source-app menu and New board).
> - `TypeBadge .pill` (Components.swift): kind pill in the peek header.
> - `PeekActionButton.chipLabel`: More actions chips (glyph .caption2 → .caption).
> - `ClipPeek` board chips (.caption2) and the “Add to board?” suggestion (.caption).
> - Unchanged: `PanelStatusFooter`, `ClipShortcutBadge`, section headers, `PasteStackStrip` counters.

### Consequences to implement (all from the card)
1. `railChipLabel` text and glyph: `.caption` → `.subheadline` (10 → 11 pt Standard; 9.9 Small; 12.65 Large).
2. Glyph frame 12 × 12 → 13 × 13.
3. Chip height 20 → 22 pt; vertical padding stays 4; horizontal padding stays 8 titled / 6 glyph-only; capsule.
4. Applies to board chips, kind chips, the app chip (source-app menu label) and New board.
5. `TypeBadge .pill` → 11 pt.
6. `PeekActionButton.chipLabel` title → 11 pt, glyph `.caption2` → `.caption`.
7. `ClipPeek` board chips (`.caption2`) and the `Add to board?` suggestion (`.caption`) → 11 pt.
8. Board rail overflows sooner at 432 pt: it scrolls (already a horizontal ScrollView); the toolbar falls back to its two-row layout earlier.
9. Unchanged at 10 pt (`.caption2`): footer, ⌘N badges, section headers, PasteStackStrip counters.
10. iOS/iPadOS: no change.

---

## 6. Card "PASS 2026-10-17 · Checked against screenshots 04–09"

Tag `PASS 2026-10-17`, title `Checked against screenshots 04–09`. Two entries:
- `GC-V4-3` (amber tag): > Corrected: user boards already show their colour dot (Seed board 1–3) and the app filter shows the real icon once chosen. What is still missing is the count on the active scope.
- `GC-V5-3` (green tag): > **Untitled image row says what it is.** Screenshot 08: an image clip without a title or thumbnail reads only “...”. v4 shows “Image · 1200 × 800 · PNG” (already stored metadata) so the row is identifiable without opening the peek. *proposal*

---

## Coverage

| Board element | ID(s) |
|---|---|
| Header ID tags (GC-01, GC-06, GC-08, GC-10, GC-11, GC-25) | annotation; GC-06 = shipped (Archive) |
| NOW artboard (whole) | context only (current UI) |
| v4 search row: Fuzzy/Exact/Regex + Meaning, placeholder `Search` | GC-V4-1 (catalog board Novel2); pin 1; feeds GC-08 |
| v4 toolbar `All clips · 128` | GC-V4-3 |
| v4 toolbar board dots, app icon | kept, no change (PASS card: already shipped) |
| v4 chip size 22 h / 11 px everywhere | GC-V5-6 |
| v4 rows 1–3 | kept, no change |
| v4 row 4 preview `PNG · 1200 × 800` | GC-V5-3 (see conflict) |
| v4 row 5 masked tail + `9:41` expiry | GC-09 (catalog board Novel); pin 7 |
| v4 peek provenance header, `Synced · Mac + iPhone`, insight strip removed | GC-01; pin 2 |
| v4 `title written on-device` caption | GC-01 (Archive: "v4 peek header says written on-device") |
| v4 hero 4 pt kind stripe (removed: leading accent bars are banned), URL part chips, `Content` label removed | no pin, no catalog ID — unassigned (Archive: link chips "v4 hero keeps decoded · https · port") |
| v4 single Transform ⌘T + hint line; Smart paste / More actions removed | GC-11 (Novel2); pin 4 |
| v4 `Add to Brand?` suggestion | kept (exists); size via GC-V5-6 |
| v4 dock `Paste into Figma` | GC-V4-2; pin 3 |
| v4 dock `Stack ⌥⌘⏎` | GC-10 (Novel); pin 4 |
| v4 footer `Capturing · Figma in front` chip | GC-V4-4 (+ GC-V4-2 for the app name); pins 3, 6 |
| v4 footer `Synced` | kept (SyncStatusView) |
| v4 footer `Stack 2` | GC-10 |
| v4 footer hints `move`, `⌘ 1–9 nth`, `⌘ / all keys` | no catalog ID — unassigned |
| Kept-as-is strip | kept, no change |
| Pin 1 | GC-V4-1 / GC-08 (other boards) |
| Pin 2 | GC-01 |
| Pin 3 | GC-V4-2 |
| Pin 4 | GC-11, GC-10 (other boards) |
| Pin 5 | GC-V4-3 |
| Pin 6 | GC-V4-4 (GC-25 related) |
| Pin 7 | GC-09 (other board) |
| Pin 8 | kept, no change (key inventory) |
| DECIDED card | GC-V5-6 |
| PASS card | GC-V4-3, GC-V5-3 (+ B-GC-04) |

---

## Feasibility

### GC-01 — Provenance in the peek header
- **Changes:** move source app (icon + name), age, boards and sync state from `insightStrip` into the header row next to `TypeBadge(.pill)`; drop `insightStrip`; title moves to its own row with `title written on-device`; hero loses the `Content` label.
- **Code:** `Apps/GanchoMac/ClipPeek.swift` — `header` :319-359, `insightStrip` :362-416 (called at :132), `boardIDs` via `model.boardMembership` :280-284 (`AppModel.swift:1943`). App icon/name: `SourceApp.icon/displayName` (ClipPeek :366-372). Board mark: `BoardIdentityMark` (`Packages/GanchoKit/Sources/GanchoDesign/BoardIdentityEditor.swift:7`).
- **Exists:** app, age, expiry, up to 3 boards.
- **New:** per-clip sync chip (`Synced · Mac + iPhone`): `ClipItem` has no sync state; it lives in DB columns `needsUpload`/`syncSystemFields` (e.g. `Pinboards.swift:71`) with no read API for the peek. Device list beyond `sourceDeviceName` is unknown. `title written on-device`: no title-provenance flag is stored (`ContentBoundTitleStore.swift:23-52` writes the title only when empty, no marker). Expiry (`hourglass`) is not drawn in the v4 header — where it goes is open.
- **Deps:** GC-V5-6 (chip size), GC-09 (Reveal in peek).
- **Verify:** UI test that `peek-source-app` and `peek-board-*` sit inside the header and that no insight strip exists; snapshot vs board §2.4.
- **BLOCKED:** (a) What does `Synced · Mac + iPhone` mean per clip — uploaded (`needsUpload = 0`) or "on these devices"? CloudKit doesn't give a device list. (b) `title written on-device` needs a stored provenance flag (schema + sync field) — accept that, or drop the caption? (c) Where does the expiry label go once the strip is removed?

### GC-V4-2 — Paste button names the target app
- **Changes:** dock primary label `Paste into <App>`; footer capture chip `Capturing · <App> in front`.
- **Code:** dock actions `ClipPeek.swift:781-817` (title `Paste` :784); `PeekActionButton.dockLabel` `PeekActionButton.swift:59-98` (`.minimumScaleFactor(0.8)` :71); target read at paste time `AppModel.swift:1033-1037` (`currentReuseTargetBundleID`, frontmost app excluding Gancho) and passed at :900/:910 to `PasteBackWorkflow.deliver` (`Packages/GanchoKit/Sources/GanchoAppCore/PasteBackWorkflow.swift:79-99`).
- **Exists:** bundle-id read; the panel is non-activating (`PanelController.swift:15`, :348) so the frontmost app stays the target.
- **New:** observable "current target" state (read on `.ganchoPanelDidShow` and on `NSWorkspace.didActivateApplicationNotification`), display name via `SourceApp.displayName`; localized string `Paste into %@` (EN+ES).
- **Deps:** GC-V4-4 (footer chip).
- **Verify:** unit test for the label resolver (nil target → `Paste`); UI test that `preview-paste` label contains the app name; `PeekDockUITests` ordering unchanged (`preview-paste` stays index 0).
- **BLOCKED:** label when there is no target or when Accessibility is off (paste degrades to copy-only, `PasteBackWorkflow.swift:93-95`) — `Paste` / `Copy`?

### GC-V4-3 — Scope chip with count
- **Changes:** active scope chip reads `<Scope> · <count>`; each board shows its count in its hover help (catalog text).
- **Code:** `PanelView.swift` `boardRail` :956-1005 (`All clips` :960-969), `boardChip` :1009-1031 (`.help(title)` :1027), `railChipLabel` :911-942 (title `maxWidth: 120` :923). Counts: `store.count()` and `fullStore.count(inBoard:)` already used by Library (`LibraryView+Browsing.swift:197-202`).
- **Exists:** colour dots, app icon (`PanelView.swift:843-846`), counting APIs.
- **New:** panel-side board count cache refreshed with `model.refreshBoards()`; a11y label with count; EN+ES strings.
- **Deps:** GC-V5-6.
- **Verify:** UI test `board-all` label `All clips · N` with seeded N; switching board updates count.
- **BLOCKED:** is the count the scope total or the filtered result (kind/app/query active)? Board says "the active scope shows its count" only.

### GC-V4-4 — Footer capture chip with colour and cause
- **Changes:** replace dot + `Capturing`/`Paused` with a tinted pill naming state and cause: green `Capturing · <App> in front`, amber `Paused · screen sharing`, indigo `Private mode · 58 min left`, red `Access denied`.
- **Code:** `Apps/GanchoMac/PanelStatusFooter.swift:37-49` (`captureIndicator`, id `capture-indicator`); policy `Packages/GanchoKit/Sources/GanchoAppCore/PanelCapturePresentation.swift:46-78` (`notice` + `isCapturing`); banner tints `PanelStatusFooter.swift:106-111`; menu-bar mapping `StatusItemController.swift:247-269`.
- **Exists:** notice precedence, causes (storage, denied, private, screen share, paused).
- **New:** footer variant per notice; an indigo token (none in `GanchoColors.swift`; only success/warning/danger/accent); private-mode remaining time — `CapturePreferences.isPrivateModePaused` is a Bool with no timer; `.storageEphemeral` and plain `.paused` not drawn.
- **Deps:** GC-V4-2 (app name), GC-25 (timed private mode / glyph states), B-GC-02 accent-ink contrast for green text.
- **Verify:** unit test mapping `PanelCapturePresentation` → chip (title, tint) for every case; update `PanelUITests.swift:380-417` (`capture-indicator` values).
- **BLOCKED:** (a) `58 min left` requires timed private mode — is that GC-25's scope? (b) copy for `.storageEphemeral`, plain manual pause and screen lock is not drawn. (c) Banner tints private mode amber today (`PanelStatusFooter.swift:108`); should the banner move to indigo too?

### GC-V5-3 — Untitled image rows say what they are (+ B-GC-04)
- **B-GC-04 location (verified):** the `...` in screenshot 08 is the **masked** row, not an untitled one. The second image in the Images filter is the seed `Hidden fixture title` with `isSensitive: true` (`Apps/GanchoMac/AppModel+UITestSeeds.swift:230-232`). `ClipCard` marks it `previewsHidden` (`Packages/GanchoKit/Sources/GanchoDesign/Components.swift:155`), hides the title (:198), renders `•••` (:244-245) and hides the source/time line (:386-387) — which is why the replica has no meta line.
- **Real untitled images:** titles are never generated for images (`ContentBoundTitleStore.swift:18-21`); capture stores preview `Image (<bytes>)` (`Packages/GanchoKit/Sources/GanchoAppCore/ClipItemFactory.swift:36-41`), shown via `ByteSize.humanizedPreview` (`ByteSize.swift:15-18`) as the row's primary line (`Components.swift:249-250`).
- **Stored metadata:** byte size (in preview) and UTI (`contentTypeIdentifier`, `GRDBClipboardStore.swift:656`). Pixel dimensions are **not** stored — the board's "already stored metadata" is wrong for `1200 × 800`.
- **New:** dimensions at capture (or derived from the thumbnail decode), a format short name from UTI, a row formatter `Image · W × H · FORMAT`.
- **Verify:** unit test for the formatter; UI test in `PanelAppearanceUITests.testImageFilteringKeepsRowIdentityAndShortcutBadges`.
- **BLOCKED:** (a) Should a **sensitive** image show `Image · W × H · PNG` (privacy rule: masked rows show only the mask)? (b) Store dimensions (schema + sync) or compute from the thumbnail? (c) Board conflict: the v4 row draws the title `Synthetic landscape` plus subtitle `PNG · 1200 × 800`, while the PASS card says `Image · 1200 × 800 · PNG` for untitled rows — which format and order?

### GC-V5-6 — Chip text at 11 pt (decided)
- **Changes:** consequences 1–10 in §5.
- **Code (verified):** `PanelView.swift:916-927` (`railChipLabel`: glyph `.caption` + frame 12×12 :918-919, title `.caption` :922, padding h 8/6 :926, v 4 :927); source-app menu label :837-849; New board :977-981. `Components.swift:68-75` (`TypeBadge .pill`, `.caption` semibold, padding 8/3; used only at `ClipPeek.swift:321`). `PeekActionButton.swift:100-104` (glyph `.caption2`, title `.caption`). `ClipPeek.swift:402` (board chips `.caption2`), :293 (suggestion `.caption`). Typography `Packages/GanchoKit/Sources/GanchoDesign/PanelTypography.swift:14-88` (scales 0.9/1/1.15 :61-68). iOS `Apps/GanchoiOS/CaptureView.swift:296` already `.subheadline`.
- **Exists:** `.subheadline` case in `PanelTextStyle`.
- **New:** none beyond style swaps; heights follow from the font.
- **Deps:** none (blocks the chip geometry of GC-V4-3 and GC-01).
- **Verify:** `PanelAppearanceUITests.testCompactSpanishToolbarWithLargeTextAndSourceFilter` (wraps earlier), `PanelDisplayPreferencesUITests.testTextSizeChangesRowHeight`; UI test that a rail chip is 22 pt tall at Standard; snapshot vs §5 rows.
- **BLOCKED:** — (note: `TypeBadge .pill` padding is v 3 / h 8, so its height also grows; the card does not say whether `.pill` should be 22 pt or stay 20.)

---

## Owner notes
- Pick notes: none on GC-01, GC-V4-2, GC-V4-3, GC-V4-4, GC-V5-3, GC-V5-6 (all `pick`).
- GC-V5-6 decided by the owner on 2026-10-17 (card).
- Owner rules that apply: compare with the current UI and only propose what beats it; code wins over v2 boards; each piece of data appears once per screen (the provenance header must not repeat app/age shown in the row's source line within the peek; the footer `Synced` and the peek `Synced · Mac + iPhone` should be checked against this rule).
- The board draws list and peek as one surface with a hairline and no gap — matches the owner's stated preference and the current code (`PanelView.swift:242-276`).
