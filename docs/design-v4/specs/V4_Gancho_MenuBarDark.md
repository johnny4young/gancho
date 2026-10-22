# V4_Gancho_MenuBarDark — spec

- **Board:** `V4_Gancho_MenuBarDark.dc.html` (title tag: "Gancho dark, ambient and menu bar v4")
- **Canvas:** 1640 × 1060 pt, background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14.
- **Shows:** the panel at rest in dark mode with the ambient wash behind the peek only (GC-04, GC-23); the status-item menu redrawn as a mini-panel (GC-24); the status-item glyph as one hook plus a state badge (GC-25, drawn here although its catalog board is `V4_Gancho_Novel`). A PASS strip adds GC-V5-1, which fixes bug B-GC-01.
- **Related Current boards:** `GanchoMenuBar_Current`, which is today's in-process menu (state line `Gancho: capturing`, five recents, then `Library`, `Open panel ⇧⌘V`, …), and `GanchoPanel_Current`.
- **Catalog IDs on this board:** GC-04, GC-23, GC-24, GC-V5-1 (board = this file); GC-25 (board = `V4_Gancho_Novel.dc.html`, partly drawn here). Bug: B-GC-01.
- **Not in the catalog:** none. Every ID the board mentions is a catalog item.

Conventions: CSS px = pt. "white N %" means `rgba(255,255,255,N/100)`. "black N %" means `rgba(0,0,0,N/100)`. Text marked "(sample)" is sample data.

---

## 0. Board header (context only)

Left to right, gap 12:
- ID chips, 22 high, radius 7, mono 11/800, letter-spacing .04em: `GC-04` (green: bg `#34C759`, text `#0B2A14`), then `GC-23`, `GC-24`, `GC-25` (dark: bg `#1D1D1F`, text `#FFFFFF`).
- Title: `Dark appearance, ambient wash and the menu bar`, 22/800, letter-spacing −.02em.
- Subtitle (13, `#5B5B61`, max width 860): `The panel at rest in dark mode with the wash behind the peek only; the status item menu becomes a usable mini-panel; one hook glyph with badges.`
- Right-aligned: `Gancho · macOS · v4` (13, `#5B5B61`).

The content row below has three columns with a gap of 28: panel (864), menu (300), and rules/glyphs (flex).

---

## 1. Frame "Dark · ambient wash on · image selected" — GC-04, GC-23

Label row: chip `GC-04` (green), text `Dark · ambient wash on · image selected` (13/800), small text `864 × 540` (12/600, `#5B5B61`).

### 1.1 Panel shell
- 864 × 540, radius 14, `overflow: hidden`.
- **Dark:** background `#1C1C1E`, text `#F2F2F7`, 1 pt border white 10 %.
- **Light (CSS base class, not drawn):** background `#F5F5F7`, text `#1D1D1F`, border black 8 %.
- Shadow in the CSS: `0 1px 2px rgba(0,0,0,.08), 0 22px 48px rgba(0,0,0,.22)`. The `.panel.dark` class does not remove it, which contradicts rule "no light-mode shadows" (§3). See Doubts.
- Body is horizontal: a list column 440 wide, a 1 pt divider (white 10 % in dark, black 8 % in light), then the peek (flex).

### 1.2 Search bar (context: GC-V4-1 owns the search modes)
- Height 44, padding 0 × 14, gap 8, bottom hairline white 10 %, icon colour `#A1A1A6`.
- Magnifier icon 15 pt. Input font 15, text `#F2F2F7`. Placeholder `Search` in `#8A8A8F`. a11y label `Search your clipboard`.
- Segmented group, a11y `Search mode`: inline pill with 2 padding, 1 gap, background white 10 %. Three buttons, each 20 high, padding 0 × 7, radius 999, 10.5/700:
  - `Fuzzy`: pressed, background `#3A3A3C`, text `#F2F2F7`.
  - `Exact` and `Regex`: no background, text `#A1A1A6`.
- `Meaning` button: 24 high, padding 0 × 9, background white 10 %, text `#A1A1A6`, 10.5/700, with an 11 pt sparkle icon before the text. `aria-pressed=false`.

### 1.3 Toolbar (context: GC-V4-3)
Padding 6 × 12, gap 4, bottom hairline white 10 %.

Chip styles:
- **Text chip:** 22 high, padding 0 × 7, radius 999, background white 10 %, text `#C7C7CC`, 11/600, icon 11 pt.
- **Pressed:** background `#30D158`, text `#04210D`, weight 700.
- **Icon-only chip:** 22 × 22.

**Board rail** (fades out over its last 22 pt):
1. `All clips · 128` (sample count). Pressed, with a check icon.
2. Favorites: icon only, star filled `#FF9F0A`.
3. `Work`: 9 × 9 swatch, radius 3, `#2E70D1`.
4. `Brand`: swatch `#F08C08`.
5. `New board…`: icon only, plus sign.

**Divider:** 1 × 14, white 18 %, 4 pt margin each side.

**Filter rail:**
1. `All`: pressed, with a check icon.
2. Icon-only chips: Links (`#32ADE6`), Code (`#A5A3FF`), Colors (`#5AC8FA`), Images (`#FF9F0A`), Secrets (`#FF3B30`), `All apps` (dashed square), `Save filter` (13 pt icon, no background).

a11y labels match the names above.

### 1.4 Section header
`Today` on the left and `5 clips` on the right (sample). 10/700, uppercase, letter-spacing .06em, colour `#A1A1A6`, padding 6/10/2.

### 1.5 Rows (context; the selected-row styling is GC-04)

Layout:
- Row list: gap 3, padding 2 × 6.
- Each row: 50 high, padding 0 × 8, radius 10, gap 10.
- Tile: 36 × 36, radius 8.
- Title: 13/600. Preview: 12, `#A1A1A6`.
- Source/age: 10.5, `#A1A1A6`.
- Key badge: 16 high, padding 0 × 4, radius 5, background white 12 %, text `#C7C7CC`, mono 10/600.

| # | Tile | Title | Preview | Meta | Badge |
|---|---|---|---|---|---|
| 1 | Code: bg `#5856D6` at 16 % (`#5856D629`), icon `#A5A3FF` | `Example · Swift` | mono `let greeting = "Hello"` (`let` `#F09CF0`, `"Hello"` `#7EE69A`) | `Xcode · now` | `⌘1` |
| 2 | Colour swatch `#008080`, inset 1 pt black 12 % | `Ocean` | mono `#008080` | `Figma · now` | `⌘2` |
| 3 | Link: gradient 160° `#5BC4F0`→`#32ADE6`, letter `E` in `#0A2B3A` (15/800) | `Synthetic link` | `https://www.example.com:8443/a%2Fb?q=a%26b#…` | `Safari · 7 s` | `⌘3` |
| 4 (**selected**) | Image thumbnail: bg `#52BCCF`, 18 pt sun `#F39B3A` | `Synthetic landscape` | `PNG · 1200 × 800` | `Vitrine · now` | pin icon 10 pt `#6E6E73`, then `⌘4` |
| 5 | Secret: bg `#FF3B30` at 16 %, lock `#FF6961` | `Stripe key · masked` | `sk_live_•••••••••••• 4Q2v` | `Terminal · 2 min` | expiry chip (bg `#FF9F0A` at 18 %, text `#FFC46B`, clock 9 pt) `9:41`, then `⌘5` |

All row data is sample data.

**Selected row (GC-04):**
- Background: `rgba(48,209,88,.16)` in dark, `rgba(52,199,89,.14)` in light.
- Leading bar: 3 pt wide, inset 8 pt top and bottom, radius 2, `#34C759`.
- The CSS uses `#34C759` for the bar in both appearances. The rule text says only "3 px bar".
- No glow.

### 1.6 Peek (the wash is GC-23)

**Peek column:** padding 12 × 14, gap 10.

**Ambient wash:** an absolute layer behind the peek column only. Value as drawn: `radial-gradient(circle at 85% 90%, rgba(243,155,58,.26), transparent 60%)`. It uses the image's colour `#F39B3A` and does not respond to the pointer. The list column, toolbar, search and footer are not washed.

**Header chips** (min height 24, gap 6, wrap):
- Kind pill `image`: 20 high, padding 0 × 8, 11/700, background `#FF9F0A` at 22 %, text `#FFC46B`, image icon 11 pt.
- Then three chips. Chip style: 20 high, padding 0 × 7, radius 999, background white 10 %, text `#E5E5EA`, 11/600.
  - `Figma`
  - clock icon + `6 s ago`
  - 8 pt swatch `#F08C08` + `Brand`

**Title:** `Synthetic landscape`, 15/800.

**Hero:** 150 high, radius 14, background `#52BCCF`, border white 10 %, centred 60 pt sun `#F39B3A`. The card surface for a non-image hero is `#2C2C2E` in dark and `#FFFFFF` in light.

**Insight chips:** `1200 × 800 · PNG · 184 KB` and `no text found`.

**Spacer**, then the **dock** (a11y group `Actions`):
- Container: padding 4, gap 4, radius 14, background white 6 %, border white 8 %.
- Buttons: 58 high, radius 10, 11/700. Shortcut line in mono 10/500 at 75 % opacity.
  1. Primary (flex 2): background `#30D158`, text `#04210D`. `Paste into Keynote` / `⏎`.
  2. `Copy text` / `⇧⌘C`
  3. `Pin` / `⌘P`
  4. `Board` / `⌘B`
  5. `Stack` / `⌥⌘⏎`

### 1.7 Footer (context: GC-V4-4 / GC-V4-2)
- Bar: 30 high, gap 12, padding 0 × 10, 11 pt `#A1A1A6`, top hairline white 10 %.
- Status pill: background `rgba(48,209,88,.2)`, text `#7EE69A`, 7 pt dot `#30D158`, text `Capturing · Keynote in front`.
- Spacer, then key hints. Key cap: 16 high, min width 17, radius 4, background white 12 %, 9/700.
  - `↑` `↓` `move`
  - `⏎` `paste`
  - `⌘` `/` `all keys`
- Info button: 13 pt icon, a11y `Keyboard shortcuts (⌘/)`.

---

## 2. Frame "Status item menu" — GC-24 (+ GC-V5-1 for the Open panel shortcut)

Label row: chip `GC-24` (green), text `Status item menu`, small text `mini-panel`. Column width 300, gap 8.

### 2.1 Menu-bar strip (context)
- 300 × 26, radius 8 8 0 0, background white 70 %, border black 8 %, padding 0 × 10, items right-aligned with gap 12, 11 pt `#5B5B61`.
- Gancho status button in its pressed state: 22 × 20, radius 5, background black 10 %. Hook template mark 15 pt in `#1D1D1F`.
  - Geometry (viewBox 96): circle cx 50, cy 24, r 8, stroke 9; path `M50 32 L50 57 A15 15 0 1 1 35 57 L31.5 47.5`, stroke 13, round caps and joins.
- Neighbour cloud icon, 12 pt (a system extra, context only).
- Clock `Tue 17 Oct · 14:08` (sample).

### 2.2 Menu
- 300 wide, radius 12, background `#F7F7F9`, border black 10 %, shadow `0 14px 40px rgba(0,0,0,.2)`, vertical padding 5.
- Drawn in light appearance only; the dark menu is the system's.

From top to bottom:

1. **Header** (one sentence; padding 6/12/4; 12/700; 9 pt dot `#34C759`): `Capturing · 128 clips · Keynote in front`. The state, count and front app are sample values.
2. **Section label** (10/700, uppercase, .06em, `#5B5B61`, padding 4/12/2): `Recent · click pastes · ⌥ pastes plain`.
3. **Five recent rows.**
   - Each row: 30 high, padding 0 × 12, gap 9, 12.5 pt, text truncated at the tail.
   - Tile: the 36 pt panel tile scaled to 62 % (about 22 pt, in a 22 × 22 slot).
   - Trailing shortcut: 11 pt `#5B5B61`.

   | # | Tile | Text (sample) | Shortcut |
   |---|---|---|---|
   | 1 | Code: bg `#5856D629`, icon `#5856D6` | `let greeting = "Hello"` | `⌘1` |
   | 2 | Swatch `#008080` | `Ocean · #008080` | `⌘2` |
   | 3 | Link gradient, letter `E` | `example.com/a/b?q=a&b` | `⌘3` |
   | 4 | Image thumbnail | `Synthetic landscape` | `⌘4` |
   | 5 | Secret: bg `#FF3B30` at 16 %, lock `#C8231B` | `Stripe key · masked` | `⌘5` |

4. **Separator:** 1 pt black 10 %, margin 4 × 10.
5. **Command rows.**
   - Each row: 30 high, padding 0 × 12, gap 9, 12.5 pt, text `#1D1D1F`.
   - Leading icon: 13 pt in a 14 pt slot, `#5B5B61`.
   - Trailing shortcut: 11 pt `#5B5B61`, system font.

   Rows in drawn order:
   - `Open panel` with `⇧⌘V`. Per GC-V5-1 this shows the recorded shortcut, not a fixed one.
   - `Library`
   - `Paste stack · 2 waiting`. A second line `next: Ship address` (10.5, `#5B5B61`). Shortcut `⌥⌘V`. This row is 40 high.
   - `Copy text from screen` with `⇧⌘2`.
   - separator
   - `Pause capture`
   - `Private mode` with `⌥⌘P`.
   - `Ignore next copy`
   - separator
   - `Settings…` with `⌘,`
   - `Privacy Center`
   - `Welcome to Gancho`
   - `My Clipboard, Wrapped…`
   - separator
   - `Quit Gancho` with `⌘Q`

**Icons as drawn → SF Symbols in code today:**

| Row | Drawn | Code symbol |
|---|---|---|
| Open panel | window | `macwindow` |
| Library | books | `books.vertical` |
| Paste stack | layers | new |
| Copy text from screen | viewfinder | `text.viewfinder` |
| Pause capture | pause circle | `pause` |
| Private mode | eye-slash | `eye.slash` |
| Ignore next copy | minus circle | `minus.circle` |
| Settings… | gear | `gearshape` |
| Privacy Center | lock | `lock.shield` |
| Welcome to Gancho | hand | `hand.wave` |
| My Clipboard, Wrapped… | gift | `gift` |
| Quit Gancho | power | `power` |

**States drawn:** capturing only.

**Interactions stated:**
- Clicking a recent row pastes it.
- ⌥ pastes as plain text.
- `⌘1`–`⌘5` paste the matching recent row.

Not drawn: the Denied state's `Fix` row (mentioned in §4) and an empty state.

---

## 3. Card "Dark + ambient rules" — GC-23 (label), content also GC-04 and GC-25

Label: chip `GC-23` (green) + `Dark + ambient rules`.

Card: white, radius 14, padding 12 × 14, border black 6 %, gap 8. Each row has a 92-wide bold label (11.5/700); the body text is 11.5 `#3A3A3F`, line height 1.4.

Rows, verbatim:
- **`Surfaces`:** `#1C1C1E panel · #2C2C2E cards · #3A3A3C controls; hairlines at 10 % white, no light-mode shadows` (GC-04)
- **`Accent`:** `#30D158 with #04210D text (7.6 : 1); selected row = 16 % wash + 3 px bar, never a glow` (GC-04)
- **`Ambient wash`:** `7 % (dark) / 10 % (light) of the clip's colour, only behind the peek, 220 ms cross-fade; off with Increase Contrast or Reduce Transparency — the code's PanelAmbientTint.isShown rule, with the list column excluded` (GC-23; `PanelAmbientTint.isShown` is set in mono)
- **`Secrets`:** `no wash, no colour tile: a masked clip never hints at its content` (GC-23)
- **`Status item`:** `one template hook, one 12 px badge; colour lives only on the badge so it reads in every menu-bar manager` (GC-25)

### Dark-mode contrast rules (consolidated; ratios computed with WCAG 2.x)

**Surfaces:**
- Panel `#1C1C1E`, cards/hero `#2C2C2E`, controls `#3A3A3C` (the pressed segment).
- Hairlines and dividers: white 10 %. The toolbar divider is white 18 %. The dock border is white 8 %.

**Text on `#1C1C1E`:**

| Role | Colour | Ratio |
|---|---|---|
| Primary | `#F2F2F7` | 15.25 : 1 |
| Secondary | `#A1A1A6` | 6.61 : 1 |
| Primary on `#2C2C2E` | `#F2F2F7` | 12.49 : 1 |
| Primary on `#3A3A3C` | `#F2F2F7` | 10.17 : 1 |

**Chips:**

| Chip | Text on background | Ratio |
|---|---|---|
| Unpressed chip | `#C7C7CC` on white 10 % | 7.52 : 1 |
| Board/insight chip | `#E5E5EA` on white 10 % | 10.09 : 1 |
| Key badge | `#C7C7CC` on white 12 % | 7.03 : 1 |
| Unpressed search mode | `#A1A1A6` on white 10 % | 4.92 : 1 |

**Accent fills:**
- `#30D158` filled controls carry `#04210D` text. The board says 7.6 : 1; the computed ratio is **8.45 : 1**.
- Light equivalent: `#34C759` with `#0B2A14` = 6.98 : 1.

**Tinted text in dark:**

| Use | Text on background | Ratio |
|---|---|---|
| Capturing footer pill | `#7EE69A` on green 20 % | 7.46 : 1 |
| Image kind pill and expiry chip | `#FFC46B` on amber 22 % | 6.96 : 1 |
| Code tile icon | `#A5A3FF` on indigo 16 % | 6.57 : 1 |
| Secret tile icon | `#FF6961` on red 16 % | 5.10 : 1 |

**Selected row:**
- 16 % `#30D158` wash. Primary text keeps 11.25 : 1; secondary `#A1A1A6` drops to 4.88 : 1, which still passes AA.
- Plus a 3 pt bar. No glow or shadow.

**Ambient wash:** 7 % in dark, 10 % in light.

**Light-mode reference:** the menu's `#5B5B61` on `#F7F7F9` is 6.30 : 1. Accent `#34C759` used as ink on `#F5F5F7` is 2.04 : 1; it must not be used for text (that is GC-V5-2).

---

## 4. Card "Status item glyphs" — GC-25 (badges part only)

Label: chip `GC-25` (green) + `Status item glyphs` + small text `one hook, badges`.

Card: white, radius 14, padding 12. Tiles are 92 wide with a gap of 6, centred.

Each tile:
- Glyph well: 34 × 34, radius 9, background black 8 %, hook 20 pt `#1D1D1F`.
- Badge: a 13 × 13 circle at the bottom-right, offset −5, with a 2 pt white border and a white glyph (8/800).
- Name: 11/700.
- Caption: 10 `#5B5B61`.

| Tile | Badge colour | Badge glyph | Caption |
|---|---|---|---|
| `Capturing` | none | — | `template hook, no badge` |
| `Paused` | `#FF9F0A` | `‖` | `amber · sharing or manual` |
| `Private` | `#5E5CE6` | `/` | `indigo · timer in menu` |
| `Denied` | `#D70015` | `!` | `red · menu offers Fix` |
| `Syncing` | `#32ADE6` | `↻` | `spins 1.2 s · still with Reduce Motion` |
| `Stack` | `#1D1D1F` | `2` (sample count) | `count while a queue waits` |

**States and motion:**
- Syncing spins with a 1.2 s period. With Reduce Motion the glyph stays still.
- The Stack badge shows the queue count while items wait.
- Denied: the menu offers a Fix row (today: `Fix clipboard access…`, in-process only).

**Contrast of the badge glyphs (white on fill):**

| Fill | Ratio |
|---|---|
| `#FF9F0A` | 2.06 : 1 |
| `#32ADE6` | 2.54 : 1 |
| `#5E5CE6` | 5.06 : 1 |
| `#D70015` | 5.38 : 1 |
| `#1D1D1F` | 16.8 : 1 |

The amber and blue badges fail. See Doubts.

---

## 5. Numbered pins (notes row, three columns)

1. **`Status menu as a mini-panel (GC-24).`** `Header is one sentence (state · count · front app), the five recent clips keep their kind tiles and paste with ⌘1–5 (the in-process menu already lists five recents and pastes on click; the helper process stays content-free by design, so this layout applies to the in-process item). Commands keep today's order: open, library, stack, screen text; pause, private, ignore; settings, privacy, welcome, wrapped; quit.`
2. **`One glyph, five badges (GC-25).`** `Today paused / stopped / denied swap the whole glyph for an SF Symbol. v4 keeps the hook and adds a badge, so the mark stays recognisable and the state still reads at 1×. Same colours as the panel footer chip.`
3. **`Dark appearance (GC-04).`** `The current panel already follows the system appearance via materials; the rules on the right fix contrast and remove light-mode shadows. Drawn with the ambient wash on, to show that only the peek breathes.`

## 6. PASS strip (bottom)

- White strip, radius 12, padding 14 × 18, 3 pt green inset bar on the left.
- Black tag `PASS 2026-10-17` + heading `Checked against screenshot 21 (status item menu)`.
- **`GC-24` (amber tag):** `Corrected baseline: the shipped menu already opens with a state line (“Gancho: capturing”, green dot) and five recent clips with their kind glyph. v4 keeps that and adds the count + front app, real tiles, ⌘1–5 and the paste-stack row.`
- **`GC-V5-1` (green tag):** `Open panel shows the shortcut you chose. Settings › General has the panel on ⌥⌘V (screenshot 10) but the menu still prints ⇧⌘V (screenshot 21): GanchoMenuBarCommand.keyEquivalent is hard-coded to the default. Read the recorder’s current shortcut instead, and omit it when none is set.`

### Implementation notes (not UI)

Everything in §0, the frame labels, §3, the §4 captions, §5 and §6 is annotation, not UI copy. Only §1 (panel) and §2 (menu-bar strip and menu) are UI. The sample shortcuts drawn in §2 are not specs: GC-V5-1 says the shortcuts come from the recorders.

---

## Coverage

| Card / frame / pin | ID(s) |
|---|---|
| Board header §0 | context only |
| §1.1 panel shell (dark surfaces, hairlines, shadow) | GC-04 |
| §1.2 search + mode control | context only (GC-V4-1) |
| §1.3 toolbar chips | context only (GC-V4-3; pressed-chip colours are GC-04) |
| §1.4 section header | kept, no change |
| §1.5 rows | context only; selected row = GC-04; secret tile = GC-23 rule; expiry chip = shipped (ClipCard expiry) |
| §1.6 peek wash | GC-23 |
| §1.6 peek header/hero/insight | context only (GC-01 provenance; GC-V5-3 image metadata) |
| §1.6 dock `Paste into Keynote` | context only (GC-V4-2); primary fill colours = GC-04 |
| §1.7 footer pill `Capturing · Keynote in front` | context only (GC-V4-4, GC-V4-2) |
| §2.1 menu-bar strip | context only (hook = GC-V7-1 mark; badge slot = GC-25) |
| §2.2 header sentence | GC-24 |
| §2.2 recent rows ×5, ⌘1–5, ⌥ plain | GC-24 |
| §2.2 `Open panel` shortcut | GC-V5-1 / B-GC-01 |
| §2.2 `Paste stack` row | GC-24 (data depends on GC-10) |
| §2.2 rest of commands | kept, no change (order: see Feasibility GC-24) |
| §3 Surfaces, Accent rows | GC-04 |
| §3 Ambient wash, Secrets rows | GC-23 |
| §3 Status item row | GC-25 |
| §4 glyph tiles ×6 | GC-25 |
| Pin 1 | GC-24 |
| Pin 2 | GC-25 |
| Pin 3 | GC-04 |
| PASS strip, GC-24 entry | GC-24 |
| PASS strip, GC-V5-1 entry | GC-V5-1, B-GC-01 |

---

## Feasibility

### Menu-bar architecture (applies to GC-24, GC-25, GC-V5-1)

**Two possible owners of the NSStatusItem:**
- **Production: `GanchoMenuBarHelper`.** This is a separate paint-only process (`Apps/GanchoMenuBarHelper/main.swift`). It owns the item (`statusItem(withLength:)` at :27) and builds its menu in `rebuildMenu()` (:46–81). It is launched by `GanchoMenuBarHelperLauncher` (SMAppService agent, with a `Process` fallback). `GanchoMacApp.establishMenuBarPresence()` polls for it for about 2 s, then detaches the in-process item.
- **Fallback: `StatusItemController`** (`Apps/GanchoMac/StatusItemController.swift`), inside the main app. Used only with `-use-in-process-status-item` (UI tests), or when the helper never starts. In that case it logs the diagnostic `The menu-bar helper didn’t start; using the built-in icon.`

**IPC (all content-free except one masked string):**
- **App → helper:** an App Group `UserDefaults` suite `group.com.johnny4young.gancho` (`GanchoMenuBarBridge.swift`). Keys:
  - `menu-bar.status.icon` and `.label`
  - `menu-bar.titles` (localized titles)
  - `menu-bar.nonce`
  - `menu-bar.last-copied.preview`, `.label`, `.at`: **one** preview, masked `•••` for protected clips and cleared in private mode (`AppModel.publishLastCopied`, AppModel.swift:846–855)
- `GanchoMenuBarStatusPublisher` (GanchoMacApp.swift:370–402) writes titles once and the status on a 1 s timer, but only when `monitorStatus` changes.
- **Helper → app:** `DistributedNotificationCenter`. Each command has its own name (`com.johnny4young.gancho.menu-bar-command.<rawValue>`), and the object is the per-launch nonce (no `userInfo`). The app validates the nonce in `receiveMenuBarCommand` (GanchoMacApp.swift:186–197).
- **Helper lifecycle:** the helper repaints on `menuNeedsUpdate` and on a 1.5 s watchdog tick.
- **Shared code:** `GanchoMenuBarCommand.swift` and `GanchoMenuBarBridge.swift` are compiled into **both** targets (project.yml:227–228). The helper does **not** link KeyboardShortcuts or GanchoKit.

**Consequence:** the five-recent mini-panel exists today only in the fallback menu. The production helper shows the status header, at most one masked "Last copied" row, and the commands, with no `Fix clipboard access…` row. Pin 1 says "this layout applies to the in-process item". Taken literally, production users would never see GC-24. See BLOCKED under GC-24.

### GC-04 — Dark appearance contrast rules (UI)

**What changes:**
- **Surfaces:** in dark, the panel uses `#1C1C1E`, cards/hero `#2C2C2E`, controls `#3A3A3C`, hairlines white 10 %.
- **Selected row:** the dark wash goes from 12 % to 16 %. The 3 pt bar is kept.
- **Accent fills:** `#30D158` carries `#04210D` text (light: `#34C759` carries `#0B2A14`).
- **Shadows:** remove light-mode shadows in dark.

**Code:**
- `Packages/GanchoKit/Sources/GanchoDesign/GanchoColors.swift`: `brandGreen` is already `#34C759` / `#30D158` at :21–22. There is no on-accent ink token and no surface tokens.
- `Components.swift`:
  - `GanchoSurface` (:8–28): glass on 26, otherwise `.background.secondary`.
  - ClipCard selection (:323–338): `accent.opacity(0.12)` + `frame(width: 3)` bar.
- Shadows:
  - `PanelView.swift:543`: `.shadow(radius: 18, y: 8)`, telemetry prompt.
  - `PanelShortcutsOverlay.swift:63`: `.shadow(radius: 20, y: 8)`.
  - `PanelController.swift:405`: `panel.hasShadow = !translucent`.
- Pressed chips: PanelView rail chips. Dock primary: `PeekActionButton.swift`.

**Exists vs new:**
- Exists: the bar, the brand greens, and the appearance-following materials.
- New: dark surface hex tokens, an on-accent ink token (`#04210D` / `#0B2A14`), 16 % dark selection, and appearance-gated shadows.

**Dependencies:** GC-V5-2 (accent-ink token for text; share the token file).

**Verify:**
- Unit tests in `GanchoDesignTests`: token hex per appearance; a WCAG ratio helper asserting ≥ 4.5 for the ink/fill pairs listed in §3.
- UI snapshot: `ProductScreensUITests`-style capture of the dark panel with `-opaque-panel-for-ui-test`, compared with §1.

**BLOCKED: Do the fixed hex surfaces replace Liquid Glass in dark, or apply only to the opaque branch?** Today the panel surface is `glassEffect(.regular)` (no hex) unless Reduce Transparency, Increase Contrast or an opaque window applies. Pin 3 says the panel "already follows the system appearance via materials".

### GC-23 — Ambient wash only behind the peek (UI)

**What changes:**
- The wash moves from the whole panel to the peek column.
- Opacity: 7 % dark and 10 % light (today 22 % / 14 %).
- 220 ms cross-fade (exists: `GanchoMotion.smooth` = 0.22 s, nil under Reduce Motion).
- Same veto (exists).
- No wash at all for secrets or masked clips.

**Code:**
- `Packages/GanchoKit/Sources/GanchoDesign/PanelDisplayPreferences.swift:61–87`:
  - `isShown` (exists, keep).
  - `opacity(dark:)` returns 0.22 / 0.14 (change).
  - `usesAccent` (keep).
- `Apps/GanchoMac/PanelView.swift`:
  - :288–292 applies `.background { ambientWash }` to the whole panel (move to the peek container).
  - :430–446 `ambientTint` falls back to `kindTint` for sensitive clips (must return nil for secrets, masked clips and private mode).
  - :449–468 MeshGradient: its corner weights already favour bottom-right, as drawn.
- Tests: `Packages/GanchoKit/Tests/GanchoDesignTests/PanelAmbientTintTests.swift:36–39` asserts `opacity(dark:false) < opacity(dark:true)`. The board inverts that (10 % > 7 %), so the test must change.

**Exists vs new:**
- Exists: the toggle `panel-ambient-tint` (Settings › General `Ambient color`, a11y `panel-ambient-tint`), the accessibility veto, and the 220 ms fade.
- New: peek-only placement, the new opacities, and a secret veto.

**Dependencies:** none. GC-V4-24 motion tokens if they rename `smooth`.

**Verify:**
- Unit: `isShown` unchanged; new `PanelAmbientTint.tint(kind:isSensitive:previewsHidden:)` returns nil for secret / sensitive / private.
- Opacity values tests.
- UI snapshot of the selected image row shows the list column untinted.

**BLOCKED: Is "7 %" the peak of the wash or the layer opacity?** The drawn gradient peaks at alpha .26 (rgba(243,155,58,.26)), but the rule says 7 % (dark). Today the layer opacity is 0.22, multiplied by mesh weights of up to 0.7.

### GC-24 — Status item menu as a mini-panel (feature)

**What changes:**
- **Header:** `<state> · <N> clips · <App> in front`.
- **Section label:** `Recent · click pastes · ⌥ pastes plain`.
- **Five recents:**
  - Real kind tiles, about 22 pt.
  - `⌘1`–`⌘5` key equivalents.
  - Click pastes; an ⌥ alternate item pastes plain.
  - Secrets are titled `<secret type> · masked`.
- **Paste stack row:** `Paste stack · N waiting` + `next: <title>` + the stack shortcut, shown when the queue is non-empty.
- **Commands** in this order:
  1. Open panel, Library, Paste stack, Copy text from screen
  2. Pause, Private, Ignore
  3. Settings, Privacy Center, Welcome, Wrapped
  4. Quit

**Code:**
- `StatusItemController.swift:147–205` (`rebuildMenu`):
  - Header :152–158 uses `StatusItemPresentation.accessibilityDescription` "Gancho: capturing".
  - Recents :168–179 use the SF Symbol image, `ClipSafePresentation.displayText` and `pasteRecentItem` → `model.paste(clip)`.
  - Order :183–204 is Library, Open panel, …, Settings, **Welcome, Privacy**, Wrapped.
- Helper `rebuildMenu` + `GanchoMenuBarCommand.helperMenuSections` (:62–67): order Open, Library, Screen text / Pause, Private, Ignore / Settings, Privacy, Welcome, Wrapped / Quit. This is the order the board follows.
- APIs that already exist:
  - `AppModel.paste(_:asPlainText:)` (AppModel.swift:899)
  - `pasteStackEntries` (:1303)
  - `recentItems` (:69)
- Tiles: reuse ClipCard's tile from `GanchoDesign/Components.swift` via `ImageRenderer` → NSImage, or `NSMenuItem.view`.
- Secret label: `ClipSafePresentation` (`Packages/GanchoKit/Sources/GanchoKit/WidgetClips.swift:23`) returns `•••` today. The secret-type name would come from `GanchoAI/SensitiveDataDetector.swift` (verify that it exposes a type name).

**Exists vs new:**
- Exists: the state line + dot, five recents with kind symbol, click-to-paste (fallback only), the commands, and the stack data.
- New:
  - the count and front app in the header
  - real tiles, ⌘1–5, the ⌥ plain alternates, and secret type labels
  - the stack row and the new order (in-process)
  - a total-count query (none exists; `All clips` has no count today)

**Dependencies:**
- GC-10 (stack cursor / "next")
- GC-V4-2 (front-app target name)
- GC-V4-3 (clip count)
- GC-07 (private state wording)
- GC-V5-1 (shortcut text)
- GC-25 (header colour = badge colour)

**Verify:**
- Unit test for a pure `MenuBarMenuPlan` builder in GanchoKit: order, ⌘1–5, alternates, masking, and the stack row hidden when empty.
- XCUITest with `-use-in-process-status-item`, following `PanelUITests.testMenuBarStatusItemOpensSettingsWindow`. Assert `menu-bar-command-*` ids and five recent items.

**BLOCKED:**
- **Which process renders the mini-panel in production?**
  - (a) The fallback only, as pin 1 literally says. Production users would then not see it.
  - (b) Widen the bridge to five masked previews + kinds + tile colours. This breaks the "single clip-derived value" contract in `GanchoMenuBarBridge.swift:11–14`.
  - (c) The helper forwards the click as a new `showMenu` command. The main app pops its own NSMenu at the status button's frame (published content-free through the bridge).
- Also: is the front-app name allowed across the bridge?

### GC-25 — Capture state in the glyph (badges part; feature)

**What changes:** the hook always stays (no SF Symbol swap) and gains one 12 pt coloured badge:
- paused (manual or sharing): amber `#FF9F0A` `‖`
- private: indigo `#5E5CE6` `/`
- denied: red `#D70015` `!`, and the menu offers Fix
- syncing: `#32ADE6` `↻`, spinning 1.2 s, static under Reduce Motion
- stack count: `#1D1D1F` with the number

**Code:**
- `GanchoMenuBarCommand.swift:187–227` `MenuBarStatusIcon`: `.active` hook, while `.paused/.stopped/.denied` swap to `pause.circle` / `stop.circle` / `exclamationmark.triangle.fill` (:199–201).
- Hook drawing :233–260 (18 pt template, strokes 13 / 9).
- `StatusItemPresentation` (StatusItemController.swift:247–269):
  - `.pausedByUser` → label "Gancho: private mode"
  - `.pausedByScreenShare` → `.paused`
  - `.stopped/.pausedByScreenLock` → `.stopped`
- Bridge `writeStatus` carries only icon + label. The publisher re-publishes only on a `monitorStatus` change.
- Sync state: `AppModel.syncStatus` (:163).
- Footer chip today tints private, screen share and paused all `warning` amber (`PanelStatusFooter.swift:106–109`), so "same colours as the footer chip" needs GC-07 / GC-V4-4 first.
- The helper menu has no `fixClipboardAccess`; only the in-process menu adds it (:200–202).

**Exists vs new:**
- Exists: the state source, the hook template, and the screen-share detector.
- New:
  - a badge compositor
  - new icon states (private, syncing, stack N)
  - bridge fields: sync and stack count (content-free)
  - a helper animation timer
  - Fix in the helper menu
- From Novel only (not drawn here): the ignore-next badge, ⌥-click / ⌥⇧-click, and screen-share preview hiding.

**Dependencies:** GC-07 (indigo private + timer), GC-V4-4 (footer chip colours), GC-V7-1 (mark), GC-10 (stack).

**Verify:**
- Unit test on a pure `StatusBadge(status:sync:stackCount:)` mapping.
- Image-render test: badge pixels coloured, hook template-tinted.
- Manual check on light and dark menu bars, and in Ice/Bartender.

**BLOCKED:**
- **How should the coloured badge be drawn?** A template NSImage is tinted monochrome. The coloured badge needs a non-template composite drawn per appearance (and inverted when highlighted), or a separate layer on the status button. Which is acceptable?
- **Badge glyph contrast:** white glyphs on `#FF9F0A` (2.06 : 1) and `#32ADE6` (2.54 : 1) fail. Should they use dark glyphs?
- **Badge set:** this board has Paused / Private / Denied / Syncing / Stack. The catalog (and Novel) has Ignore-next / Paused / Private / Sharing. Which set ships?

### GC-V5-1 + B-GC-01 — Menu shows the real panel shortcut (bug)

**B-GC-01 verified on this branch (a251a65):**
- `Apps/GanchoMac/GanchoMenuBarCommand.swift:135` has `case .openPanel: "v"`.
- `:147` has `case .openPanel: [.command, .shift]`.

The recorder default is `KeyboardShortcuts.Name.togglePanel` = ⇧⌘V (`Apps/GanchoMac/GlobalShortcuts.swift:10–11`). User changes are ignored.

**What changes:** `Open panel` shows the recorded `.togglePanel` shortcut, or no shortcut when it is unset. The menu rebuilds when the shortcut changes.

**Code and fix path:**
- **In-process:** `item.setShortcut(for: .togglePanel)` (KeyboardShortcuts 3.0.1 `NSMenuItem++.swift:108`, which observes `.shortcutByNameDidChange`), or read `KeyboardShortcuts.getShortcut(for:)` in `addCommand` (StatusItemController.swift:207–227).
- **Helper:** cannot link KeyboardShortcuts (project.yml:222–228). The app must publish the key equivalent + modifier mask to the bridge (a new content-free key). It re-publishes on `.shortcutByNameDidChange`. The helper reads the value in `rebuildMenu` (main.swift:64–79). Fall back to "" when absent.
- **Same issue for the drawn sample shortcuts:**
  - `Copy text from screen` is drawn `⇧⌘2`; the code default is ⌃⌥T (`GlobalShortcuts.swift:18–19`).
  - `Private mode` is drawn `⌥⌘P`; the code has no default (:13).
  - `Paste stack` is drawn `⌥⌘V`; the code has no default (:17).

  All three must come from their recorders the same way.

**Exists vs new:**
- Exists: the recorders (`GeneralSettingsTab.swift:59–61`) and the KeyboardShortcuts menu helper.
- New: a bridge key for shortcuts and dynamic key equivalents.

**Dependencies:** GC-24 (same menu rebuild).

**Verify:**
- Unit test for a pure "shortcut → (keyEquivalent, modifierMask)" encoder in a GanchoKit target, including nil → empty.
- UI test: launch with a recorded ⌥⌘V (or a seed argument) and `-use-in-process-status-item`; assert `menu-bar-command-openPanel` shows ⌥⌘V.

**Blocked:** — (only the Doubts below).

---

## Owner notes

- **Pick notes:** GC-04, GC-23, GC-24, GC-25 and GC-V5-1 are all `pick` with an empty note. There are no owner comment threads on this board.
- **Owner rules that apply:**
  - Compare with the current UI and propose only what beats it. Code wins over boards: §1 surfaces vs glass, and the menu order.
  - Each piece of data appears once per screen. In §1 the front app appears both in the dock (`Paste into Keynote`) and in the footer (`Keynote in front`). That is GC-V4-2 / GC-V4-4 territory; flag it there.
  - Annotations are not UI (respected above).

## Doubts not resolved here

1. The board says #04210D on #30D158 is 7.6 : 1; the computed ratio is 8.45 : 1. The claim understates it and both pass.
2. The dark panel CSS still carries the light drop shadow, while the rule says "no light-mode shadows". Follow the rule.
3. The selected bar is `#34C759` even in dark. Should it be `#30D158`?
4. The status-item rule says a 12 px badge; the glyph cards draw 13 pt including a 2 pt border.
5. The "today's order" in pin 1 matches the helper, not the in-process menu that screenshot 21 shows. The in-process order is Library first and Welcome before Privacy.
6. The drawn `Paste stack ⌥⌘V` would collide with a panel recorded on ⌥⌘V (the GC-V5-1 evidence).
7. The helper is not strictly content-free: it already shows one masked "Last copied" preview, while pin 1 says "content-free by design".
8. The menu is drawn only in light appearance.
