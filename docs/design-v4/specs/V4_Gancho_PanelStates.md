# V4_Gancho_PanelStates — spec

- **Board:** `V4_Gancho_PanelStates.dc.html` (canvas title "Gancho v4 · panel states"), canvas **2400 × 1340**, background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14.
- **Shows:** six macOS panel states that are silent or weak in v0.10.2, each drawn as one panel at the **Compact preset 760 × 480** (light appearance only; the stylesheet defines `.panel.dark` but no frame uses it).
- **Related Current boards (reference only):** `GanchoPanelEmpty_Current` (No matches + Clear filters), `GanchoPanel_Current` (list + peek + dock), `GanchoPanelActions_Current` (More actions chips, 864 × 540 Standard).
- **IDs drawn:** GC-05, GC-07, GC-08 (catalog board = this board); GC-09, GC-10 (catalog board = `V4_Gancho_Novel`); GC-12 (catalog board = `V4_Gancho_Novel2`). GC-06 is mentioned as shipped and kept.

Layout: header strip, then a 3-column grid (`repeat(3, 760px)`, gap 14 row × 28 column) holding six frames in two rows, then a 3-column notes grid with six numbered pins.

| Row | Col 1 | Col 2 | Col 3 |
|---|---|---|---|
| 1 | GC-05 Empty | GC-07 Private Mode | GC-08 No results |
| 2 | GC-09 Secret selected | GC-10 Three selected | GC-12 Smart paste |

---

## 0. Header strip (not UI)

Left to right: ID tags `GC-05` (green tag `#34C759` on `#0B2A14`), `GC-07`, `GC-08`, `GC-09`, `GC-10`, `GC-12` (dark tags `#1D1D1F` / white; 22 pt high, radius 7, 11 pt / 800, monospaced). Title `Panel states · the moments that are still silent in v0.10.2` (22 pt / 800). Subtitle (13 pt `#5B5B61`, max 860 wide): `Every state keeps the list usable, names what changed in one line and offers the next key. Drawn at the Compact preset (760 × 480). GC-06 (paused banner with cause + Resume) is shipped and is kept unchanged.` Right: `Gancho · macOS · v4`.

Each frame has a label row above the panel: green ID tag + bold title (13 pt / 800) + `small` "today:" note (12 pt / 600 `#5B5B61`). The "today:" notes describe current behaviour and are annotations, not UI.

---

## 1. Shared panel anatomy (all six frames)

Panel: 760 × 480, background `#F5F5F7`, text `#1D1D1F`, base 13 pt, radius 14, border 1 pt `rgba(0,0,0,.08)`, shadow `0 1 2 rgba(0,0,0,.08), 0 22 48 rgba(0,0,0,.22)`.

Body = list column (fixed **400 pt**, right border 1 pt `rgba(0,0,0,.08)`) + peek/stage column (flex, padding 12 × 14, gap 10 — 8 in frames that set it), then footer.

### 1.1 Search bar (list column top) — context; realised by GC-V4-1 on `V4_Gancho_Novel2`
44 pt high, padding 0 14, gap 8, bottom border 1 pt `rgba(0,0,0,.08)`, colour `#5B5B61`.
- Magnifier icon 15 pt.
- Input: a11y label `Search your clipboard`, placeholder `Search`, 15 pt, placeholder colour `#8A8A8F`.
- Mode segmented group (a11y `Search mode`): track `rgba(29,29,31,.07)`, padding 2, gap 1, pill radius. Segments `Fuzzy`, `Exact`, `Regex`: 20 pt high, padding 0 7, 10.5 pt / 700. Selected = background `#FFFFFF`, text `#1D1D1F`; unselected = no fill, `#5B5B61`.
- `Meaning` toggle: sparkles icon 11 pt + `Meaning`, 24 pt high, padding 0 9, `rgba(29,29,31,.07)`, 10.5 pt / 700, `#5B5B61`, `aria-pressed=false` in every frame.

### 1.2 Toolbar rails — context; realised by GC-V4-3 (`V4_Gancho_Panel`)
Padding 6 × 12, gap 4, bottom border. Board rail (masked fade 22 pt at right), vertical divider 1 × 14 `rgba(0,0,0,.14)`, filter rail.
Chip: 22 pt high, padding 0 7, radius pill, `rgba(29,29,31,.07)`, `#5B5B61`, 11 pt / 600, gap 5. Selected chip: `#34C759` fill, `#0B2A14` text, 700, check icon 11 pt. Glyph-only chip 22 × 22.
- Board rail: scope chip (selected; label per frame: `All clips · 0` / `All clips · 128` / `Work · 12`), `Favorites` (star `#FF9F0A`), `Work` (swatch 9 × 9 radius 3 `#2E70D1`), `Brand` (swatch `#F08C08`), `New board…` (plus).
- Filter rail: `All` (selected), `Links` (`#32ADE6`), `Code` (`#5856D6`), `Colors` (`#5AC8FA`), `Images` (`#FF9F0A`), `Secrets` (lock `#FF3B30`), `All apps` (dashed square), `Save filter` (13 pt, no fill).

### 1.3 Section header and rows
- Section header: padding 6 10 2, 10 pt / 700, tracking .06 em, uppercase, `#5B5B61`; left label, right count.
- Rows: gap 3, padding 2 6. Row 50 pt high, padding 0 8, gap 10, radius 10. Selected row: fill `rgba(52,199,89,.14)` + 3 pt leading bar `#34C759` (inset 8 pt top/bottom, radius 2).
- Tile 36 × 36, radius 8. Title 13 pt / 600; preview 12 pt `#5B5B61` (mono for code/colour); source line 10.5 pt `#6E6E73`; quick key `⌘N` badge 16 pt high, radius 5, `rgba(29,29,31,.08)`, 10 pt / 600 mono.
- Expiry badge (`.bch` amber): 20 pt high, `rgba(255,159,10,.18)` / `#7A4B00`, timer icon 9 pt.
- Pin marker: filled pin 10 pt `#6E6E73`.

### 1.4 Dock (peek bottom)
Container: padding 4, gap 4, radius 14, `rgba(29,29,31,.06)`, border `rgba(0,0,0,.06)`, pinned to bottom. Button 58 pt high, padding 7 2, radius 10, icon 15 pt, label 11 pt / 700, shortcut `small` 10 pt / 500 mono at 75 % opacity. Primary button: flex 2, `#34C759` / `#0B2A14`.

### 1.5 Footer
30 pt high, padding 0 10, gap 12, 11 pt `#5B5B61`, top border. Left: capture pill (20 pt, radius pill, 11 pt / 700, 7 pt dot). Right: key hints (key caps 16 pt high, min 17 wide, radius 4, `rgba(29,29,31,.08)`, 9 pt / 700) and the help button (a11y `Keyboard shortcuts (⌘/)`, info-circle icon 13 pt). Capture-pill wording is GC-V4-4 (`V4_Gancho_Panel`); this board only fills in per-state text.

---

## 2. Frame GC-05 — "Empty · first launch" (row 1, col 1)
Realises **GC-05**. Label note: `today: title + one line + “⌘C in any app to start”`.

**List column**
- Scope chip `All clips · 0` (selected).
- No section header, no rows. Centered stack (gap 8, padding 0 28, centered):
  1. Tile 56 × 56, radius 16, gradient 160° `#5FD57F` → `#34C759`, white clipboard glyph 26 pt.
  2. `Your history starts here` — 14 pt / 700.
  3. `Copy anything — text, a link, an image — and it appears here, ready to paste again.` — 12 pt `#5B5B61`, line-height 1.4.
  4. `⌘C in any app to start` — 11 pt `#6E6E73`.
  5. Button (glass style, margin-top 6): down-arrow icon 12 pt + ` Import from Maccy or CSV…`. Glass: 28 pt high, padding 0 10, radius 10, `#FFFFFF`, border `rgba(0,0,0,.08)`, 12 pt / 600.

**Stage (peek column, gap 8)**
- Section label `The whole loop, three keys` (11 pt / 700 uppercase `#5B5B61`).
- Three key cards (each: padding 8 × 10, radius 12, `#FFFFFF`, border `rgba(0,0,0,.06)`, gap 10; keycaps 18 pt high, radius 5, `rgba(29,29,31,.08)`, 10.5 pt / 700; text 12 pt, line-height 1.3, bold title + `#5B5B61` second line):
  1. Keys `⇧` `⌘` `V` — **`Open the panel from anywhere`** / `or click the hook in the menu bar`
  2. Keys `↑` `↓` — **`Pick a clip, or just type to search`** / `⌘1–9 jumps straight to a row`
  3. Key `⏎` — **`Paste where you were typing`** / `⌥⏎ pastes plain text`
- Spacer, then `Shown once. It leaves after your first paste and the stage becomes the peek.` (11 pt `#6E6E73`) — drawn as stage copy; treat as UI copy unless owner says otherwise (see Feasibility).

**Footer:** green pill (`rgba(52,199,89,.16)` / `#1F7A3A`, dot `#34C759`) `Capturing · 0 clips`; hints `⌘` `,` `settings`, `esc` `hide`; help button.

**States:** stage disappears permanently after the first paste; the stage becomes the normal peek.

---

## 3. Frame GC-07 — "Private Mode · indigo, timed, with a receipt line" (row 1, col 2)
Realises **GC-07**. Label note: `today: amber banner “Private Mode is on” + Resume; no timer`.

**List column**
- Scope chip `All clips · 128`.
- **Banner** (margin 6 6 0, padding 7 × 10, radius 10, gap 8, 11 pt, line-height 1.25), background `rgba(94,92,230,.12)`:
  - Eye-slash icon 14 pt, `#3634A3`.
  - Title (11.5 pt / 700, `#3634A3`): `Private Mode is on · since 14:02` (time = sample).
  - Detail (`#3A3A3F`): `3 copies skipped, 0 read · turns off at 15:02 or when you say so` (numbers/times = sample).
  - Trailing button `Turn off ⌥⌘P`: 22 pt high, padding 0 9, pill, 11 pt / 700, fill `#5E5CE6`, text `#FFFFFF`.
- Section header `Before private mode` / `5 clips`.
- Five rows, every title and preview masked as `•••`, no source line, quick keys `⌘1`…`⌘5`. Tiles keep kind identity: code (`#5856D6` @16 %), text/AA (`#5AC8FA` @16 %), link (`#32ADE6` @16 %, **row 3 selected**), image (`#52BCCF` with `#F39B3A` circle), secret (`rgba(255,59,48,.16)` / `#C8231B` lock).

**Peek**
- Header: kind pill `url` (`rgba(50,173,230,.16)` / `#0B5C80`, link icon 11 pt) + title `•••` (14 pt / 700).
- Hero (flex, centered, `#FFFFFF`, border `rgba(0,0,0,.08)`, radius 14, padding 12 × 14, 12 pt `#5B5B61`): `Previews hidden while Private Mode is on.` ⏎ `Pasting still works; only new copies are skipped.`
- Dock: primary `Paste into Mail` `⏎` (target app = sample), `Plain` `⌥⏎`, `Board` `⌘B`.

**Footer:** indigo pill (`rgba(94,92,230,.14)` / `#3634A3`, dot `#5E5CE6`) `Private mode · 58 min left`; hints `⌥` `⌘` `P` `off`, `esc` `hide`; help.

**Colour family (indigo):** fill `#5E5CE6`, ink `#3634A3`, tint 12 % (banner) / 14 % (pill). Amber stays for paused circumstances (GC-06, unchanged).

**Timers / auto-off:** banner states start time and auto-off time; footer counts down minutes left; Private Mode turns off at the auto-off time "or when you say so" (button / shortcut). Auto-off duration comes from a new Settings → Privacy picker (pin 2); options are not drawn.

---

## 4. Frame GC-08 — "No results · the other modes, counted" (row 1, col 3)
Realises **GC-08**. Label note: `today: “No matches · Try another word.” + Clear filters`.

**List column**
- Search value `invoice q3 pdf` (sample); mode `Exact` selected.
- Scope chip `Work · 12` (selected).
- Centered stack (gap 8, padding 0 24):
  1. Tile 56 × 56, radius 16, `rgba(29,29,31,.07)`, magnifier 24 pt `#5B5B61`.
  2. `No matches` — 14 pt / 700.
  3. `No clips for “invoice q3 pdf” in Work, exact match.` — 12 pt `#5B5B61` (query, board and mode interpolated).
  4. Alternatives list (full width, gap 5, margin-top 4). Each = glass button 34 pt high, space-between, label left, count badge right (`.kn`):
     - `Fuzzy` `3` — **highlighted**: fill `rgba(52,199,89,.12)`, border `rgba(52,199,89,.3)` (best alternative)
     - `Regex` `0`
     - `Meaning` `2`
     - `All boards` `12`
     - `Older than 30 days` `1`
  5. `Clear filters` — text button, 12 pt / 700, `#1F7A3A`, margin-top 2.

**Stage (gap 8)**
- Section label `Fuzzy · 3 results, press ↓ to use them`.
- Three rows (padding 0), row 1 selected:
  1. PDF tile (`#007AFF` @16 %, doc icon) — `invoice-q3.pdf` / `PDF · 212 KB` / `Finder · 2 d` / `⌘1`
  2. Text tile (`#8E8E93` @16 %, `#4B4B50`) — `Invoice Q3 — payment terms` / `Please find attached the invoice for Q3…` / `Mail · 9 d` / `⌘2`
  3. Monogram tile `S` (gradient `#5BC4F0` → `#32ADE6`, `#0A2B3A`) — `Stripe · invoice in_1Q4ab2` / `https://dashboard.stripe.com/invoices/in_1Q4ab2` / `Safari · 11 d` / `⌘3`
  (all sample data)
- Spacer, then (11 pt `#6E6E73`): `Counts come from the same ClipSearch query run once per mode; meaning uses the local index only when it is on.` — this is an implementation note (see below), not UI.

**Footer:** green pill `Capturing · Mail in front`; hints `↓` `use fuzzy`, `⌘` `↑` `recall search`, `esc` `hide`; help.

**Behaviour:** ↓ from the empty list moves into the best alternative (here Fuzzy) and applies it. Clicking an alternative applies that mode/scope. Meaning row appears only when the Meaning index toggle is on (pin 3).

---

## 5. Frame GC-09 — "Secret selected · countdown and timed reveal" (row 2, col 1)
Realises the panel part of **GC-09** (catalog board `V4_Gancho_Novel`). Label note: `today: row ••• + timer under 1 h; peek masked, no reveal on Mac`.

**List column** — scope `All clips · 128`; header `Today` / `5 clips`; rows (sample):
1. Code tile — `Example · Swift` / `let greeting = "Hello"` (mono, `let` `#A33EA3`, string `#2E7D32`) / `Xcode · now` / `⌘1`
2. Colour tile `#008080` (inset 1 pt `rgba(0,0,0,.12)`) — `Ocean` / `#008080` / `Figma · now` / `⌘2`
3. Monogram `E` — `Synthetic link` / `https://www.example.com:8443/a%2Fb?q=a%26b#…` / `Safari · 7 s` / `⌘3`
4. Image tile — `Synthetic landscape` / `PNG · 1200 × 800` / `Vitrine · now` / pin marker / `⌘4`
5. **Selected** secret tile (`rgba(255,59,48,.16)` / `#C8231B` lock) — `Stripe key · masked` / `sk_live_•••••••••••• 4Q2v` / `Terminal · 2 min` / amber badge `9:41` / `⌘5`

**Peek (gap 8)**
- Header chips (gap 6, wraps): pill `secret` (`rgba(255,59,48,.16)` / `#C8231B`, lock 11 pt); chip `Terminal`; chip clock-icon 10 pt + ` 2 min ago`.
- Title `Stripe key · masked` (15 pt / 800).
- Hero (secret variant): background `#FFF8F7`, border `rgba(255,59,48,.25)`, radius 14, padding 12 × 14.
  - `sk_live_•••••••••••••••• 4Q2v` — 14 pt / 700 mono.
  - Row (margin-top 8, gap 8, 11 pt `#7A4B00`): timer icon 12 pt + `Self-destructs in ` **`9:41`** (bold mono) ` · never synced, never in backups`.
  - Progress bar (margin-top 8): 6 pt high, radius 3, track `rgba(255,159,10,.2)`, fill `#FF9F0A` at 62 % (remaining fraction, sample).
- Actions row (gap 6, wraps), glass buttons 28 pt:
  - eye icon + ` Reveal for 10 s`
  - hourglass icon + ` Keep 10 more min`
  - trash icon + ` Delete now` — text `#C8231B`
- Dock: primary `Paste into Terminal` `⏎`, `Plain` `⌥⏎`, `Stack` (stack icon) `⌥⌘⏎`.

**Footer:** green pill `Capturing · Terminal in front`; hints `⏎` `paste (stays masked here)`, `esc` `hide`; help.

**States:** reveal shows plaintext for 10 s then re-masks; Keep 10 more min extends expiry, bounded by the retention floor (pin 4); Delete now deletes the clip. Countdown in row badge, hero text and bar stay in sync.

---

## 6. Frame GC-10 — "Three selected · the stack is a visible queue" (row 2, col 2)
Realises the panel part of **GC-10** (catalog board `V4_Gancho_Novel`). Label note: `today: context bar exists; stack only as a footer strip + popover`.

**List column**
- Scope `All clips · 128`.
- Selection context bar (banner style, `rgba(52,199,89,.1)`): `#1F7A3A` / 700 check icon 12 pt + ` 3 clips`; spacer; icon buttons (13 pt, `#1D1D1F`, padding 2) with a11y label = tooltip: `Copy combined…`, `Prepare context for AI…`, `Add to paste stack`, `Add to board`, `Delete` (`#C8231B`); divider 1 × 14 `rgba(0,0,0,.14)`; text button `Clear` (11 pt `#5B5B61`).
- Header `Today` / `5 clips`. Rows 1–3 **selected** (multi-selection, each with green fill + bar):
  1. `E` — `Synthetic link` / `https://www.example.com:8443/a%2Fb…` / `Safari · 7 s` / `⌘1`
  2. text tile — `Ship address` / `Carrera 7 # 71-21, Bogotá` / `Notes · 1 h` / `⌘2`
  3. text tile — `Order number` / `GAN-2026-0412` / `Mail · 1 h` / `⌘3`
  4. code — `Example · Swift` / `let greeting = "Hello"` / `Xcode · now` / `⌘4` (unselected)
  5. colour — `Ocean` / `#008080` / `Figma · now` / `⌘5` (unselected)
  (sample data)

**Stage (gap 8)**
- Header row: section label `Selection · 3 clips`; spacer; chip `2.1 KB combined` (sample).
- Hero (padding 10):
  - Title row (12 pt / 700, margin-bottom 6): stack icon 12 pt + ` Paste stack · 3 waiting`; right keycap `⌥⌘V pastes next` (the recorded "Paste from stack" shortcut; sample).
  - Queue rows (gap 8, padding 6 × 8, radius 9, 12 pt; title 600, ellipsis): number badge (`.kn`) `1`/`2`/`3`, kind icon 11 pt, title, remove button (a11y `Remove`, x-circle 13 pt `#6E6E73`).
    1. Row 1 (next): background `rgba(94,92,230,.12)`, link icon `#32ADE6`, `Synthetic link`, pill `next` (`#5E5CE6` / `#FFFFFF`).
    2. Row 2: `#FFFFFF`, text icon `#8E8E93`, `Ship address`.
    3. Row 3: `#FFFFFF`, text icon `#8E8E93`, `Order number`.
  - Caption (11 pt `#5B5B61`, margin-top 6): `Front to back, one per keypress, with the panel closed. Drag to reorder.`
- Dock: primary `Paste next` (stack icon) `⌥⌘V`; `Combined` (no shortcut); `Board` `⌘B`; `Delete` (trash) `⌫`.

**Footer:** green pill `Capturing · Pages in front`; indigo (`#3634A3`) stack-icon 11 pt + ` Stack 3`; hints `⇧` `↑↓` `extend`, `⌘` `click` `toggle`, `⌥⌘` `⏎` `stack`; help.

**Behaviour:** queue is drag-reorderable; each item removable; ⌥⌘⏎ enqueues the selection; the stack shortcut pastes the front item with the panel closed.

---

## 7. Frame GC-12 — "Smart paste · was → will paste" (row 2, col 3)
Realises the panel part of **GC-12** (catalog board `V4_Gancho_Novel2`). Label note: `today: result box with Paste / Copy result, no diff`.

**List column** — scope `All clips · 128`; header `Today` / `5 clips`; rows (sample):
1. **Selected** text tile — `Meeting notes` / `zephyr beta monday. marta reviews kepler dashboards befor friday…` / `Portavoz · 2 min` / `⌘1`
2. `Example · Swift` / `let greeting = "Hello"` / `Xcode · now` / `⌘2`
3. `Ocean` / `#008080` / `Figma · now` / `⌘3`
4. `Synthetic link` / `https://www.example.com:8443/a%2Fb?q=a%26b#…` / `Safari · 7 s` / `⌘4`
5. `Synthetic landscape` / `PNG · 1200 × 800` / `Vitrine · now` / pin / `⌘5`
6. `Stripe key · masked` / `sk_live_•••••••••••• 4Q2v` / `Terminal · 2 min` / badge `9:41` / `⌘6`

**Peek (gap 8)**
- Header: pill `text` (`rgba(142,142,147,.18)` / `#3A3A3F`, AA icon 11 pt); title `Meeting notes` (14 pt / 800); spacer; chip sparkles 10 pt + ` Smart paste`.
- Action chips row (gap 4, right fade mask 28 pt): 24 pt high, padding 0 9, pill, 11 pt / 700. Selected = `#1D1D1F` / `#FFFFFF`; others `rgba(29,29,31,.07)` / `#5B5B61`. Order: `Fix grammar` (selected), `Summarize`, `Tone ▾`, `Key points`, `Redact PII`, `Translate ▾`.
- Hero (padding 10): two equal columns, gap 10, 11.5 pt, line-height 1.45.
  - Left: label `Was` (10 pt uppercase `#5B5B61`), text `#5B5B61`: `zephyr beta monday. marta reviews kepler dashboards befor friday. checklist from ilarion after the call` with `befor` struck through.
  - Right: label `Will paste` (`#1F7A3A`), text: `Zephyr beta Monday. Marta reviews Kepler dashboards before Friday. Checklist from Ilarion after the call.` with highlights (`rgba(52,199,89,.22)`) on `Zephyr`, `Monday`, `Marta`, `before`, and the final `.`.
  - Change chips (wrap, margin-top 8): `5 capitalisations`, `1 spelling`, `1 period`, and green chip (`rgba(52,199,89,.14)` / `#1F7A3A`, shield icon 10 pt) ` on-device · 0.4 s` (all sample).
- Dock: primary (flex 1.4) `Paste fixed` `⇧⏎`; `Original` `⏎`; `Copy` `⌘C`; `Discard` (x icon) `esc`.

**Footer:** green pill `Capturing · Pages in front`; hints `⇧` `⏎` `paste result`, `←` `back to list`; help.

Note the drawn text "Kepler", "Friday", "Checklist", "Ilarion" are capitalised in Will paste but not highlighted (drawing inconsistency vs the "5 capitalisations" chip).

---

## 8. Implementation notes (not UI)

Numbered pins (verbatim):
1. `Empty keeps the shipped copy and adds the three keys on the stage plus the importer the app already has ( MigrationImportView , reachable today only from Settings and the welcome window).`
2. `Private Mode gets its own family (indigo) so it never looks like a paused circumstance (amber). The receipt line reuses PrivateActivityReceipt counters, never content. The auto-off timer is new code: one Settings → Privacy picker.`
3. `No results runs the other ClipSearchQuery.Mode s once and shows their counts; ↓ moves into the best alternative. Meaning counts only when the index toggle is on.`
4. `Secret : masked preview and expiry already exist in the row; the peek adds a progress bar, Reveal for 10 s (iOS has detail-reveal ; the Mac peek does not), Keep 10 min (bounded by the retention floor) and Delete now.`
5. `Selection : the context bar is today's; the stage shows the queue with a “next” marker and the stack shortcut recorded in General, instead of a popover under a 9 pt strip.`
6. `Smart paste keeps every action of SmartPasteAction and Translate; the diff is computed locally from the result string (word diff), with ⇧⏎ paste and ⌘C copy as today's result box offers.`

In-frame annotation (GC-08 stage): `Counts come from the same ClipSearch query run once per mode; meaning uses the local index only when it is on.`

Header annotation: `GC-06 (paused banner with cause + Resume) is shipped and is kept unchanged.`

"today:" label notes per frame are quoted in each frame section above.

---

## 9. Coverage

| Board element | ID(s) |
|---|---|
| Header strip | context only |
| Shared search bar + mode segments + Meaning toggle | GC-V4-1 (`V4_Gancho_Novel2`), context only here |
| Shared rails / scope chip with count | GC-V4-3 (`V4_Gancho_Panel`), context only here |
| Footer capture pill wording | GC-V4-4 (`V4_Gancho_Panel`); per-state text owned by each frame's ID |
| Dock `Paste into <App>` | GC-V4-2 (`V4_Gancho_Panel`), context only here |
| Frame GC-05 Empty (list + stage + footer) | GC-05 |
| Frame GC-07 Private Mode (banner, masked list, peek, footer) | GC-07 |
| Frame GC-08 No results (alternatives, stage preview, footer) | GC-08 |
| Frame GC-09 Secret selected | GC-09 (panel slice; full item on `V4_Gancho_Novel`) |
| Frame GC-10 Three selected | GC-10 (panel slice; full item on `V4_Gancho_Novel`) |
| Frame GC-12 Smart paste | GC-12 (panel slice; "Describe the change…" field lives on `V4_Gancho_Novel2`) |
| Pin 1 | GC-05 |
| Pin 2 | GC-07 |
| Pin 3 / GC-08 stage annotation | GC-08 |
| Pin 4 | GC-09 |
| Pin 5 | GC-10 |
| Pin 6 | GC-12 |
| GC-06 mention | kept, no change (shipped) |

---

## 10. Feasibility

### GC-05 — Empty panel teaches the three keys
- **Changes:** first-run empty state gains the importer button; the peek column shows the three-key stage; footer shows `Capturing · 0 clips`; stage dismissed forever after first paste.
- **Code:** `Apps/GanchoMac/PanelResultsView.swift:193-292` (`PanelResultsEmptyState`, `firstRunContent` at 224, a11y `panel-empty-firstrun`); hint copy `Apps/GanchoMac/PanelView.swift:1281-1289` (`firstRunCaptureHint`); importer `Apps/GanchoMac/MigrationImportView.swift` (sheets today in `SettingsView.swift:36` and `OnboardingView.swift:49`); shortcut name/default `Apps/GanchoMac/GlobalShortcuts.swift:9-10` (⇧⌘V default); footer `Apps/GanchoMac/PanelStatusFooter.swift`.
- **Exists:** title, body copy, `⌘C in any app to start` and the blocked-cause variants; importer view; first-reuse milestone.
- **New:** importer button + sheet from the panel; stage view; persisted "first paste done" flag. Do **not** reuse `ActivationTracker` (`AppModel.swift:999-1006` skips recording when telemetry consent is `.disabled`), so a dedicated `UserDefaults` flag set on first successful paste is needed. Icon size differs (code 64 pt, board 56 pt radius 16).
- **Rule:** the `⇧ ⌘ V` keycaps must render the *configured* `togglePanel` shortcut, not a literal (same bug family as B-GC-01).
- **Deps:** GC-V4-4 (footer wording), B-GC-01/GC-V5-1 (render real shortcut).
- **Verify:** unit test on a pure "show stage" predicate (empty history + flag unset); UI test with `-seed` empty store: `panel-empty-firstrun` shows importer button (new id e.g. `panel-empty-import-button`) and stage (`panel-first-run-stage`), and both disappear after a paste; snapshot vs frame GC-05; EN+ES strings in `Localizable.xcstrings`.
- **BLOCKED:** Is `Shown once. It leaves after your first paste and the stage becomes the peek.` user-facing copy or an annotation? (It is styled as UI on the stage.)

### GC-07 — Private Mode in indigo with timer and auto-off
- **Changes:** private-mode notice gets indigo tint, `since HH:MM` title, receipt line, `Turn off` button with shortcut; masked list header `Before private mode`; peek hero copy; indigo footer countdown; new auto-off picker in Settings → Privacy.
- **Code:** `PanelStatusFooter.swift:66-140` (`PanelCaptureNoticeView`: tint `.warning` at 108, title/detail 116/127, action `Resume` at 136); `Packages/GanchoKit/Sources/GanchoAppCore/PanelCapturePresentation.swift` (notice precedence); `Packages/GanchoKit/Sources/ClipboardCore/CapturePreferences.swift:17` (`isPrivateModePaused: Bool` only); `Packages/GanchoKit/Sources/GanchoAppCore/CaptureLifecycleController.swift:43,127` (toggle, engage hook); `Packages/GanchoKit/Sources/ClipboardCore/MacPasteboardMonitor.swift:167` (private mode stops polling entirely); `PrivateActivityReceipt.swift` (`skippedCaptures` counter, fed by `AppModel.swift:494-500` `onIgnore` for denylist/sensitive only); `Apps/GanchoMac/PrivacySettingsTab.swift`; `GanchoDesign/GanchoColors.swift` (no indigo token today); `GlobalShortcuts.swift:13` (`togglePrivateMode` has **no default**).
- **Exists:** masking in peek/rows while private (`ClipPeek.swift:90`, `previewsHidden` in `PanelView.swift:439`), toggle, notice, receipt store.
- **New:** `privateModeStartedAt` and `privateModeEndsAt` persisted with preferences; auto-off scheduler (also fires when the app relaunches past the deadline); Settings → Privacy picker; indigo palette token (light + dark); counting copies during Private Mode **without reading** — the monitor does not poll while private, so it must observe `changeCount` deltas only (no content read) and record them via a new receipt counter or `recordPrivateSkippedCapture`; section-header rename; peek hero copy.
- **Deps:** GC-V4-4 (footer pill), GC-17 (Privacy settings layout), SY-V4-8 (one saturated control: indigo `Turn off` button vs green primary dock button in the same frame).
- **Verify:** unit tests: auto-off fires at the deadline (injected clock), deadline persists across relaunch, skip counter increments on `changeCount` change while private and never calls a content read (mock pasteboard asserts no `data(forType:)`); presentation test for indigo `.privateMode`; UI test `capture-notice` text + countdown with a fixed-clock launch arg; snapshot vs frame GC-07.
- **BLOCKED:** (1) `Turn off ⌥⌘P` / footer `⌥⌘P off`: no default shortcut exists — add ⌥⌘P as default, or show the recorded shortcut and hide the hint when none? (2) Auto-off picker options and default are not drawn (e.g. 15 min / 1 h / until I turn it off?). (3) "0 read" claims a count of reads — is it a fixed promise string or a real counter (what would increment it)?

### GC-08 — No results shows counts in the other modes
- **Changes:** on zero results, run the query in each other mode/scope once, list counts as buttons, preview the best alternative in the stage, ↓ applies it.
- **Code:** `PanelResultsView.swift:262-291` (`noResultsContent`, `detail`), a11y `panel-empty-noresults`, `clear-filters`; `Packages/GanchoKit/Sources/GanchoAppCore/PanelSearchModel.swift:297` (`hasActiveFilter`), `:361-418` (`refresh`), `:470` (`savedRule`); `Packages/GanchoKit/Sources/GanchoKit/ClipSearch.swift:7-14` (modes exact/fuzzy/regex); `GRDBClipboardStore.swift:340` (`search`); meaning: `PanelSearchModel.meaningEnabled`, `AppModel+MeaningSearch.swift`; ↓ handling and ⌘↑ recall `PanelView.swift:96-101,559-570`.
- **Exists:** `No matches`, `No clips for “…”.`, `Clear filters`, three modes, meaning toggle, ⌘↑ recall.
- **New:** an `AlternativeCounts` probe in `GanchoAppCore` (pure, cancellable, keyed by the same request id so stale counts never land); detail line with board + mode (`in Work, exact match.`); count rows; stage preview; ↓ from empty list applies best alternative; footer hint `↓ use fuzzy`. Counts cost up to 4 extra queries per empty result — debounce with the existing refresh request id; regex is a scan, cap it.
- **Deps:** GC-V4-1 (mode control drawn in field), GC-V4-3 (scope chip with count).
- **Verify:** unit tests on the probe with an in-memory `PanelSearchSource` fake: counts per mode, Meaning skipped when index off, best-alternative choice, cancellation on query change; UI test: type a no-match exact query, assert rows `no-results-alt-fuzzy` etc. and ↓ switches mode; snapshot vs frame GC-08.
- **BLOCKED:** `Older than 30 days` `1` has no backing concept: the panel has no date filter, search already covers all non-archived history, and free-tier archiving is 365 days (`UserTier.swift:25`). What does this row count (archived clips? a default date window?) — or drop it? Also: is "best alternative" = highest count, or a fixed order Fuzzy > Meaning > All boards?

### GC-09 — Masked everywhere (panel slice)
- **Changes:** Mac peek for a sensitive clip gets countdown text, progress bar, `Reveal for 10 s`, `Keep 10 more min`, `Delete now`; dock `Stack ⌥⌘⏎`; footer hint `paste (stays masked here)`.
- **Code:** `Apps/GanchoMac/ClipPeek.swift:89-101` (masking), `:381-390` (expiry label, warning under 600 s); row countdown `Packages/GanchoKit/Sources/GanchoDesign/Components.swift:162-170,274-293` (under 3600 s, `Expires soon`); `RetentionEngine.swift:55-70` (sensitive purge by `createdAt + sensitiveLifetime`, ignores `expiresAt`); `RetentionSettingsTab.swift:29-44` (5/10/30 min; copy says "you can shorten but not extend"); iOS reveal `Apps/GanchoiOS/ClipDetailView.swift:312` (`detail-reveal`); sync upload `Packages/GanchoKit/Sources/GanchoKit/SyncLocalStore.swift:208-221` (no sensitive filter); export `GanchoArchive.swift:22-28,225` (`excludeSensitive` default true); delete `GRDBClipboardStore.deleteAllSensitive` (bulk only).
- **Exists:** row mask + countdown, peek mask, expiry label, iOS reveal, archive exclusion.
- **New:** Mac reveal (timed), keep-longer, single-clip delete from peek with undo semantics, progress bar, secret hero styling.
- **Deps:** GC-V4-9 (iPhone secret rows), GC-25/GC-24 for other surfaces; full GC-09 scope (widgets, keyboard, MCP) on `V4_Gancho_Novel`.
- **Verify:** unit tests for remaining-fraction math and reveal timer (injected clock); retention test that a kept item survives exactly the extension and never past the cap; UI test with `-seed` sensitive clip: `peek-reveal-button` shows plaintext and re-masks after 10 s; snapshot vs frame GC-09.
- **BLOCKED:** (1) Reveal conflict: this board draws `Reveal for 10 s` (button); the catalog item and `V4_Gancho_Novel` say "Hold ⌥ to reveal". Which one? (2) `Keep 10 more min` contradicts the shipped rule "shorten but not extend" and the engine purges by `createdAt` regardless of `expiresAt`; what is the "retention floor" cap? (3) `never synced` is false today: `pendingUploads()` uploads sensitive rows to iCloud. Change sync to skip `isSensitive` rows (privacy change), or change the copy?

### GC-10 — Paste stack with a visible cursor (panel slice)
- **Changes:** with a multi-selection the stage shows the queue (numbered, `next` marker, remove, drag reorder) and a dock (`Paste next`, `Combined`, `Board`, `Delete`); footer shows `Stack N`; context bar `Clear`.
- **Code:** `Apps/GanchoMac/PanelSelectionContextBar.swift` (five icons + `Clear selection`); `Apps/GanchoMac/PasteStackStrip.swift` (footer strip + popover, reads `KeyboardShortcuts.getShortcut(for: .pasteFromStack)`); `AppModel.swift:1303-1335` (`pasteStackEntries`, `pasteNextFromStack`); `Packages/GanchoKit/Sources/GanchoAppCore/PasteStack.swift`; ⌥⌘⏎ enqueue `PanelView.swift:586-600`; `GeneralSettingsTab.swift:60` (`Paste from stack shortcut:` recorder, **no default**).
- **Exists:** queue model, reorder, remove, paste-next, ⌥⌘⏎ enqueue, context bar, combined copy.
- **New:** stage queue view replacing the popover, `next` marker, combined-size chip, dock for selection, footer `Stack N` label. Status-item `3/5`, floating strip, skip/back/reset and 2-min idle end live on `V4_Gancho_Novel`.
- **Deps:** GC-V5-1 / B-GC-01 (render recorded shortcuts), GC-24/GC-25 (status item).
- **Verify:** unit tests on `PasteStack` ordering/next; UI test: select 3, ⌥⌘⏎, assert `paste-stack-queue` rows and `next` on row 1, drag reorder; snapshot vs frame GC-10.
- **BLOCKED:** (1) The frame shows the 3 selected clips already as the queue: does selecting enqueue automatically, or is the queue only filled by ⌥⌘⏎ / `Add to paste stack` (today's behaviour)? (2) `⌥⌘V pastes next` assumes a default stack shortcut; none exists, and some users bind the panel to ⌥⌘V (B-GC-01 evidence). Show the recorded one and hide when unset? (3) Indigo is used for the stack `next` marker and footer `Stack 3` while GC-07 claims indigo as Private Mode's own family — keep both?

### GC-12 — Describe the change: diff (panel slice)
- **Changes:** Smart paste moves from a menu to a chip row in the peek; result box becomes a `Was` / `Will paste` word diff with change-category chips and on-device timing; dock `Paste fixed ⇧⏎`, `Original ⏎`, `Copy ⌘C`, `Discard esc`.
- **Code:** `Packages/GanchoKit/Sources/GanchoAI/SmartPasteService.swift:15-46` (`summarize`, `proofread`=“Fix grammar”, `formal`, `friendly`, `keyPoints`, `redactPII`); `Apps/GanchoMac/ClipPeek+SmartPaste.swift` (menu, translate submenu, `smart-paste-menu`); `ClipPeek.swift:736-756` (`resultBox`: `Paste` / `Copy result`, ids `paste-result`, `copy-result`).
- **Exists:** all six actions + Translate; result box with Paste and Copy buttons.
- **New:** chip row (`Tone ▾` folds formal/friendly), pure word-diff in `GanchoAppCore` or `GanchoAI` (no model call), change categorisation (capitalisation / spelling / punctuation), latency chip, keyboard ⇧⏎ / ⌘C / esc on the result. The "Describe the change…" field, Coaching and recipes are on `V4_Gancho_Novel2`, not drawn here.
- **Deps:** GC-11 (One Transform, `V4_Gancho_Novel2`), GC-V4-2 (dock naming).
- **Verify:** unit tests for the word diff and category counts on the drawn sample (expect 5 capitalisations — see drawing note in §7); UI test: run Fix grammar with the stub model, assert `smart-paste-diff` and ⇧⏎ pastes the result; snapshot vs frame GC-12.
- **BLOCKED:** Pin 6 says ⇧⏎ paste exists in "today's result box"; code has only buttons, no ⇧⏎ binding (`PanelView.swift:586-600` routes ⏎ / ⌥⏎ / ⌥⌘⏎ only). Confirm ⇧⏎ is new. Also: `Discard` on `esc` conflicts with esc = hide panel (`PanelView.swift:605-612`) — esc discards first when a result is open?

### Bugs / SY items linked
- B-GC-01 (menu shows ⇧⌘V while panel shortcut may be ⌥⌘V) — relevant to GC-05 and GC-10 keycaps; fix belongs to GC-V5-1.
- B-GC-02 (accent-green text contrast) — the green `Clear filters` text (`#1F7A3A`) and green labels on this board already use dark ink; fix belongs to GC-V5-2.
- SY-V4-8 (one saturated control per surface) — GC-07 frame has indigo `Turn off` plus green primary dock button.

---

## 11. Owner notes
- Pick notes: GC-05, GC-07, GC-08, GC-09, GC-10, GC-12 are all `pick` with no note.
- No owner comment thread on this board. General owner rules apply: compare with current UI and only propose what beats it; each piece of data once per screen; annotations are not UI.
