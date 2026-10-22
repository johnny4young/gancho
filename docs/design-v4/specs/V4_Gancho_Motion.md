# V4_Gancho_Motion — spec

- **Board:** `V4_Gancho_Motion.dc.html` (page title `Gancho motion v4`)
- **Canvas:** 1760 × 1115 pt, background `#ECEDF0`, radius 12, padding 24 (top/bottom) × 28 (left/right), vertical gap 14. Content width 1704 pt.
- **What it shows:** a motion storyboard for four moments (row selection/stage swap, paste press → hide, drop on a board) plus the motion-token table with its Reduce Motion substitutions and the rules every new animation must respect. It is mostly annotation; the only buildable UI is motion behaviour, a drop-target state and one toast.
- **Related Current board:** `GanchoPanel_Current` (today's panel: list with `⌘1…⌘6` rows, board rail `All clips` / `Seed board 1…3`, dock `Paste ↩` · `Plain ⌥↩` · `Pin ⌘P` · `Board ⌘B`). Reference only.
- **Catalog items realised:** GC-V4-22 (MAYBE, pending decision), GC-V4-23, GC-V4-24. Shipped/kept: GC-V4-21 (Archive). Skipped: GC-V4-20 (Archive).

Units: board CSS px = pt. Mini frames are storyboard illustrations (schematic panel), not layouts to build; their sizes are recorded so the storyboard can be redrawn, not to size real views.

---

## Shared board styles (apply to every card below)

- **ID chip** (`.id`): 22 tall, padding 0 9, radius 7, SF Mono 11 pt weight 800, letter-spacing .04em. Default `#1D1D1F` on white text; green variant (`.id.g`) `#34C759` fill, `#0B2A14` text.
- **Card** (`.card2`): padding 14, radius 14, fill `#FFFFFF`, border 1 `rgba(0,0,0,.06)`, inner gap 10.
- **Card label** (`.lab`): 13 pt weight 800, gap 8; trailing `small` 12 pt weight 600 `#5B5B61`.
- **Frame** (`.frame`): width 176 (flex 0 0 176), column gap 6; frames in a row are 8 apart.
  - Time label (`.ms`): SF Mono 10 pt weight 800, letter-spacing .04em, `#1F7A3A`.
  - Viewport (`.fv`): 118 tall, radius 12, `#FFFFFF`, border 1 `rgba(0,0,0,.08)`.
  - Caption (`.ft2`): 10.5 pt, `#5B5B61`, line-height 1.3; code identifiers set in mono.
- **Mini panel** (`.mini`, used by GC-38 and GC-39 frames): at (10, 10), 150 × 98, radius 8, fill `#F5F5F7`, border 1 `rgba(0,0,0,.1)`, shadow 0 8 22 `rgba(0,0,0,.14)`.
  - List column (`.ml`): 62 wide, right border 1 `rgba(0,0,0,.08)`, padding 4, gap 3, five row bars 10 tall, radius 3, `rgba(29,29,31,.08)`.
  - Selected row bar (`.rw.sel`): `rgba(52,199,89,.22)` with a leading 2 wide bar `#34C759` (inset 2 top/bottom, radius 1).
  - Stage column (`.mr`): padding 4, gap 3; hero block (flex, radius 5, `#FFFFFF`, border 1 `rgba(0,0,0,.08)`) above a dock bar 12 tall, radius 4, `#34C759`.

---

## 1. Header strip (top, full width)

Realises: context only (lists IDs).

Left to right, gap 12, vertically centred:
1. ID chips: `GC-38` (green), `GC-39`, `GC-41`, `GC-42` (black).
2. Title (22 pt, weight 800, letter-spacing −.02em, line-height 1.15): `Motion · four moments, two curves, one Reduce Motion rule`
3. Subtitle (13 pt, `#5B5B61`, line-height 1.4, max width 860): `Recovered from the v3 storyboard and the first panel redesign note, re-grounded in GanchoMotion (quick 0.18 s · smooth 0.22 s · blur-replace · Reduce Motion gate) and the panel's 100 ms open budget. Nothing moves that the user did not cause.` (`GanchoMotion` in mono)
4. Flexible spacer.
5. Right (13 pt `#5B5B61`, no wrap): `Gancho · macOS + iOS · v4`

### Implementation notes (not UI)
- The whole strip is annotation. Principle to carry into code review: “Nothing moves that the user did not cause.”

---

## 2. Two-column grid (columns 1fr 1fr, row gap 14, column gap 28 → each card ≈ 838 wide)

### 2.1 Card “Select a row, swap the stage” (row 1, left) — GC-38 → GC-V4-21 (shipped, Archive)

Label: chip `GC-38` (green) + `Select a row, swap the stage` + small `bar slides · stage blur-replaces`.

Four frames, left to right:

| # | Time label | Drawing | Caption (verbatim) |
|---|---|---|---|
| 1 | `rest` | Mini panel, row 2 selected, all other rows flat. | `rows flat, one 3 px bar on the selected row` |
| 2 | `hover · 120 ms` | Row 1 tinted `rgba(52,199,89,.1)`; row 2 still selected; nothing else changes. | `background tint only; nothing moves` |
| 3 | `select · 0.18 s` | Selection moved to row 3. | `the bar slides to the new row (matchedGeometryEffect, as the active chip already does); the row never lifts` |
| 4 | `stage · 0.22 s` | Row 3 selected; hero block at opacity .55 with 1 pt blur (mid blur-replace). | `the peek swaps with GanchoMotion.replace (blur-replace, down-up); counts roll with numericText` |

States drawn: rest, hover, selected (moved), stage swapping. No row lift, no scale.

#### Implementation notes (not UI)
- Pin 1 applies (see §4).
- Board time label for hover is `120 ms`; the token table (§2.4) puts “hover ring” under `settle` (0.18 s). Code animates row hover with `GanchoMotion.quick` (0.18 s). Shipped as coded; no change requested.

### 2.2 Card “Paste press, then the panel leaves” (row 1, right) — GC-39 → GC-V4-22 (MAYBE · PENDING DECISION, do not implement)

Label: chip `GC-39` (green) + `Paste press, then the panel leaves` + small `press · check · hide · ⌘V` + triage tag `MAYBE · undecided` (18 tall, padding 0 7, radius 999, 10 pt weight 800, letter-spacing .05em, border 1 `#B26A00`, text `#8A4F00`, fill `#FFF4E0`, margin-left 4).

Owner note box (11.5 pt, line-height 1.4, text `#5C3A00`, fill `#FFF8EB`, border 1 `#F0D3A0`, radius 8, padding 5 × 9, margin-top −4), verbatim:
> **Owner: unclear value.** Functional part (Command-V only after the panel hides; “Copied” when Accessibility is missing) already exists in PasteBackService; the rest is animation.

Four frames:

| # | Time label | Drawing | Caption (verbatim) |
|---|---|---|---|
| 1 | `0 ms` | Mini panel at rest, row 2 selected, dock `#34C759`. | `⏎ keydown · the primary button answers first` |
| 2 | `80 ms` | Dock bar `transform: scale(.96)`, fill `#2DB450` (a shade darker). | `button to .96, a shade darker (PeekActionButton already bounces its symbol)` |
| 3 | `120–260 ms` | Whole mini panel opacity .7, scale .99; dock fill `#1F7A3A`. | `label flips to a check (no colour change), then the panel hides in 140 ms ease-in` |
| 4 | `260 ms` | Panel gone; a white card (inset 10, radius 8, border 1 `rgba(0,0,0,.1)`, padding 8, 10 pt `#5B5B61`) stands for the target app: bold `#1D1D1F` line `Figma · Text layer` (sample), mono line `https://www.example.com/a/b?q=a&b` (sample, break-all), green weight-700 `#1F7A3A` line `Pasted · 1 of 3 in stack` (sample). | `⌘V is sent only at 0 opacity (PasteBackWorkflow), never before; ⌘1–9 skip the press frame: 180 ms in all` |

Timings as drawn: press 80 ms → check 120–260 ms → hide 140 ms ease-in → ⌘V at opacity 0. `⌘1–9`: no press frame, “180 ms in all”.

#### Implementation notes (not UI)
- Pin 2 applies (see §4).
- Frame 3 draws the dock at `#1F7A3A` while its caption says “no colour change”. HTML wins for the drawing, but the caption is an explicit rule; recorded as open question Q-22c.
- Frame 4 is the *target app*, not Gancho UI. `Pasted · 1 of 3 in stack` is not existing Gancho copy and is not specified as a Gancho surface (open question Q-22d).

### 2.3 Card “Drop a clip on a board” (row 2, left) — GC-41 → GC-V4-23

Label: chip `GC-41` (green) + `Drop a clip on a board` + small `ring · tick · Undo`.

Common drawing elements:
- **Board rows** stack at (10, 10), width 84, gap 4. Each row: 22 tall, padding 0 × 8, radius 7, fill `#FFFFFF`, 11 pt, gap 6; leading swatch 8 × 8 radius 2; name (flex); trailing count 10 pt `#5B5B61`, tabular digits.
  - `Work` (sample) swatch `#2E70D1`, count `12` (sample).
  - `Brand` (sample) swatch `#F08C08`, count `4` → `5` (sample).
- **Dragged card**: at (96, 30), 70 × 28, radius 7, fill `#FFFFFF`, border 1 `rgba(0,0,0,.12)`, shadow 0 8 18 `rgba(0,0,0,.18)`, padding 0 × 6, gap 5, 10 pt weight 700; leading tile 12 × 12 radius 3 `#32ADE6`; text `example.com` (sample); rotated 3°.

Four frames:

| # | Time label | Drawing | Caption (verbatim) |
|---|---|---|---|
| 1 | `drag` | Rows `Work 12`, `Brand 4`; card lifted, rotated 3°. | `the card lifts with a 3° tilt (ClipDragProvider already hands text, URL or PNG to other apps)` |
| 2 | `hover · 150 ms` | `Brand` row: scale 1.04 + 2 pt ring `#34C759` (box-shadow 0 0 0 2). Card moved 30 pt left (still 3°). Badge at (126, 22): 14 × 14 circle `#34C759`, white `+`, 10 pt weight 800 — sits on the dragged card's corner. | `the board row is the target: scale 1.04 + 2 px green ring, badge turns +` |
| 3 | `drop · 220 ms` | `Brand` count `5` in `#1F7A3A`; card at scale .3, translated (−200, 10), opacity .4 (shrinking into the row). | `the card shrinks into the row; the count ticks 4 → 5 with numericText` |
| 4 | `settled` | Rows `Work 12`, `Brand 5` (count back to `#5B5B61`). Toast at left/right 10, bottom 8: 24 tall, radius 8, fill `#1D1D1F`, white 10 pt, padding 0 × 8, gap 6: check glyph (10 × 10, stroke 2.6, path `M5 12l5 5 9-10`), text `Added to Brand`, trailing (margin-left auto, weight 700, `#7EE69A`) `Undo ⌘Z`. | `toast with Undo (ToastPresenter has the slot); refused drops — secret clip, Free limit — shake 2 × 3 px and say why` |

States: drag lifted · target hovered (ring + scale + `+` badge) · dropped (count tick, accent-ink count) · settled (toast with Undo) · refused (shake 2 × 3 pt + reason; reason copy not drawn).

UI strings: `Added to Brand` (pattern `Added to <board name>`), `Undo`, `⌘Z`.

#### Implementation notes (not UI)
- Pin 3 applies (see §4).
- The toast here is a schematic in a 176 pt frame. The real toast is `ToastView` (top-centre of the screen, `ganchoSurface`, style symbol + tint). Treat the drawn dark pill as illustration; only the copy and the Undo action are specified.
- Refusal copy (“say why”) is not drawn.

### 2.4 Card “Curve family · the v3 tokens on the code's two curves” (row 2, right) — GC-42 → GC-V4-24

Label: chip `GC-42` (green) + `Curve family · the v3 tokens on the code's two curves`.

Table (11 pt; header cells 10 pt weight 700, uppercase, letter-spacing .06em, `#5B5B61`, bottom border 1 `rgba(0,0,0,.12)`; body cells padding 3 × 8, top border 1 `rgba(0,0,0,.06)`; token column weight 800; “Used by” and “With Reduce Motion” columns `#5B5B61`). **Reduce Motion substitution table, verbatim:**

| Token | Value in the code | Used by | With Reduce Motion |
|---|---|---|---|
| `arrive` | `GanchoMotion.smooth` · 0.22 s, no overshoot | popovers, swipe return | opacity 100 ms |
| `settle` | `GanchoMotion.quick` · 0.18 s snappy | selection bar, active chip, hover ring, chips | no translate; background + bar only |
| `leave` | ease-in 140 ms `new` | panel hide, drop shrink, menu close | opacity 100 ms |
| `swap` | `GanchoMotion.replace` · blur-replace down-up | stage content, ambient wash, OCR lines | plain swap (`.identity`, as coded) |
| `press` | .96 for 80 ms + symbol bounce | every primary button; the iOS Paste control stays system | check flash only |

The `new` tag after `ease-in 140 ms`: 16 tall, 9.5 pt, weight 700, fill `#1D1D1F`, white text, radius 999.

Code values behind the names (verified, `Packages/GanchoKit/Sources/GanchoDesign/GanchoMotion.swift`):

| Token | Exact code value | Reduce Motion in code today |
|---|---|---|
| `settle` | `quick = .snappy(duration: 0.18, extraBounce: 0)` (line 7) | `quick(reduceMotion: true)` → `nil` (no animation, instant) |
| `arrive` | `smooth = .smooth(duration: 0.22)` (line 9) | `smooth(reduceMotion: true)` → `nil` |
| `swap` | `replace(reduceMotion:)` → `BlurReplaceTransition(configuration: .downUp)` (lines 32–35) | `.identity` |
| `leave` | does not exist | — |
| `press` | does not exist as a token (symbol bounce only on symbol change, `PeekActionButton.swift:65–67`) | bounce suppressed (`value: ""`) |

#### Implementation notes (not UI)
- Pin 4 applies (see §4).
- The board says the substitution column “is what `GanchoMotion.animation(_:reduceMotion:)` already does”. Only `swap` (`.identity`) and, loosely, `settle` (no move because no animation) match. `opacity 100 ms` (arrive, leave) and `check flash only` (press) are **new** behaviour: today Reduce Motion returns `nil` (instant). See Q-24a.

---

## 3. Card “Rules” (full width, below the grid)

Label: `Rules` + small `what every new animation must respect`. Rows 11 pt, line-height 1.35, gap 7; rule name column 78 wide weight 700; body `#3A3A3F`.

| Rule | Text (verbatim; identifiers in mono) |
|---|---|
| `Two curves` | `the code has exactly two (quick, smooth) and a Reduce Motion gate that returns nil; v4 adds one departure curve and no spring.` |
| `Budget` | `the panel opens with orderFront on a reused NSPanel to stay far under 100 ms; every arrival animation is an overlay on the already-laid-out window, never a delay before it.` |
| `Haptics` | `are not motion: the iPhone swipe commit (shipped, swipeActions) still buzzes under Reduce Motion.` |
| `Countdowns` | `secret timers stay text (9:41) in every mode; no animated ring.` |
| `Rolling digits` | `PanelResultsView already uses numericText for section counts; the board count and the stack badge join it.` |

### Implementation notes (not UI)
- All five rules are part of GC-V4-24 (they belong in the `GanchoMotion` doc comment / design doc, not in UI).
- `9:41` is sample countdown text.

---

## 4. Numbered pins (full width, 4 columns, gap 10 × 18; 12 pt `#3A3A3F`, line-height 1.45; pin badge 20 × 20 black circle, white 11 pt weight 800)

All pins are annotation (not UI). Verbatim:

1. **Selection and stage (GC-38).** No row lift: the 3 px bar slides between rows with the same `matchedGeometryEffect` the active chip already uses, and the peek swaps with the shipped blur-replace. Hover is a tint only.
2. **Paste order (GC-39).** Press, check, hide, then ⌘V — the order is the feedback. `PasteBackWorkflow` keeps sending ⌘V only once the panel is gone; without Accessibility the check reads “Copied” and the toast says “press ⌘V”.
3. **Drop on a board (GC-41).** Drag-out exists (`ClipDragProvider`); dropping onto a board row in the toolbar or the Library sidebar is new and gets a ring, a count tick and an Undo toast. Masked clips are not drag sources, as today.
4. **Tokens and Reduce Motion (GC-42).** The five v3 names map onto the two code curves plus one 140 ms departure; the substitution column is what `GanchoMotion.animation(_:reduceMotion:)` already does, written down once. GC-40 (swipe actions) shipped on iPhone and is kept.

---

## 5. PASS strip (bottom, full width)

Fill `#FFFFFF`, radius 12, padding 14 × 18, inset 3 pt left bar `#34C759`.
- Badge `PASS 2026-10-17` (20 tall, radius 6, `#1D1D1F`, white 10.5 pt weight 800) + heading (14 pt weight 800) `Checked against main @ a251a658`.
- Two columns (gap 8 × 24, 12 pt `#3A3A3F`):
  - Chip `GC-V4-21` (grey `#E5E5EA`): **Shipped, moved to the Archive.** The selection wash + 3 px bar is one shared view that glides between rows (SharedSelectionGeometry / matchedGeometryEffect in ClipCard), the peek swaps with GanchoMotion.replace and section counts use numericText.
  - Chip `GC-V4-22/23/24` (lavender `#E8E7FB` / `#3D3BB0`): Still proposals: paste press → check → hide (maybe), drop on a board, and the five motion tokens. GC-V4-20 (panel arrival from the hook) was discarded in triage on Oct 18 — see Archive.

### Implementation notes (not UI)
- Annotation only. GC-V4-20 is **not drawn** on this board; it is mentioned here and lives in `V4_Gancho_Archive` (owner pick: skip).

---

## Coverage

| Board element | Covered by |
|---|---|
| Header strip (chips, title, subtitle, platform line) | context only |
| Card GC-38 · frame `rest` | GC-V4-21 — shipped, Archive (kept, no change) |
| Card GC-38 · frame `hover · 120 ms` | GC-V4-21 — shipped (code uses 0.18 s quick; kept) |
| Card GC-38 · frame `select · 0.18 s` | GC-V4-21 — shipped |
| Card GC-38 · frame `stage · 0.22 s` | GC-V4-21 — shipped |
| Card GC-39 · MAYBE tag + owner note | GC-V4-22 (pending decision) |
| Card GC-39 · frames `0 ms`, `80 ms`, `120–260 ms`, `260 ms` | GC-V4-22 (pending decision, do not implement) |
| Card GC-41 · frames `drag`, `hover · 150 ms`, `drop · 220 ms`, `settled` | GC-V4-23 |
| Card GC-42 · table rows arrive / settle / leave / swap / press | GC-V4-24 |
| Rules card (5 rules) | GC-V4-24 |
| Pin 1 | GC-V4-21 (shipped) |
| Pin 2 | GC-V4-22 |
| Pin 3 | GC-V4-23 |
| Pin 4 | GC-V4-24; GC-40 mention = shipped (iPhone `swipeActions`), kept |
| PASS strip · GC-V4-21 | Archive (shipped) |
| PASS strip · GC-V4-22/23/24 | GC-V4-22 / 23 / 24 |
| PASS strip · GC-V4-20 mention | Archive — owner pick “skip” (discarded in triage Oct 18) |

Legacy IDs on this board (from the Archive row “GC-37 · 38 · 39 · 41 · 42 motion storyboard and tokens → v4 Motion (GC-V4-21…24); GC-V4-20 skipped”):

| Legacy | Now |
|---|---|
| GC-37 (panel arrival, not drawn here) | GC-V4-20 — skipped, Archive |
| GC-38 | GC-V4-21 — shipped, Archive |
| GC-39 | GC-V4-22 — MAYBE |
| GC-40 | shipped (iPhone swipe actions + context menu), kept |
| GC-41 | GC-V4-23 |
| GC-42 | GC-V4-24 |

---

## Feasibility

### GC-V4-24 — Motion tokens and the Reduce Motion substitution table (pick)

**What changes**
- Name the five tokens in `GanchoMotion`: `settle` = `quick`, `arrive` = `smooth`, `swap` = `replace(reduceMotion:)`, plus new `leave` (ease-in 0.14 s) and `press` (scale .96, 0.08 s). Decide whether names are aliases or renames (keep `quick`/`smooth` call sites compiling).
- Write the substitution column once as a pure, testable policy (per token: animation or nil, transition or `.identity`, whether scale/translate are allowed).
- Fold off-token literals onto the tokens and put every one behind the Reduce Motion gate:
  - `Apps/GanchoMac/PanelView.swift:309` `.snappy(duration: 0.12)` (shortcuts overlay) — not Reduce-Motion gated.
  - `Apps/GanchoMac/PanelResultsView.swift:170` `.snappy(duration: 0.2)` (section count) — gated by hand; should be `settle`.
  - `Apps/GanchoMac/ClipPeek.swift:168` `.easeOut(duration: 0.1)` (chip scroll) — gated by hand.
  - `Apps/GanchoMac/DenylistSettingsSection.swift:178` `.easeOut(duration: 0.15)` — not gated.
  - `Apps/GanchoMac/PeekImageText.swift:38, 41, 395, 499` bare `withAnimation {}` and `:281` `.transition(.opacity)` — not gated; board puts “OCR lines” under `swap`.
  - `Apps/GanchoMac/PanelView.swift:291` ambient tint animates with `smooth`; board lists “ambient wash” under `swap`.
  - iOS: `Apps/GanchoiOS/ReuseSuggestionBanner.swift:105` `.snappy` (gated), `Apps/GanchoiOS/ClipDetailView.swift:67` `withAnimation(.snappy)` (no gate at the call site).
- Extend numericText (“Rolling digits” rule) to the Library board count `Apps/GanchoMac/LibraryView+Sidebar.swift:118` and the stack badge `Apps/GanchoMac/PasteStackStrip.swift:26`.
- Record the rules (two curves + one departure, 100 ms budget, haptics stay, countdown stays text) in the `GanchoMotion` doc comment.

**Exists**
- `GanchoMotion.swift:5–36` (two curves, `animation(_:reduceMotion:)` → nil, `usesBlurReplace`, `replace`); tests `Packages/GanchoKit/Tests/GanchoDesignTests/GanchoMotionTests.swift:6–20`.
- Uses: `Components.swift:216, 223, 315, 318–321` (selection, hover, pin); `PanelView.swift:781–783, 992–995` (rails); `PeekActionButton.swift:34–36, 49–51, 65–67`; `ClipPeek.swift:123, 147, 150, 160–162, 620–622`.
- Countdown is already text: `Components.swift:289` `Text(expiresAt, style: .timer)`, `ClipPeek.swift:383` `.relative`.
- Haptics: iPhone swipe is system `swipeActions` (`Apps/GanchoiOS/CaptureShell.swift:197, 205`, `BoardsHomeView.swift:222`).
- iOS Paste control is system `UIPasteControl` (`Apps/GanchoiOS/CaptureView.swift:445–457`) — stays untouched.
- Panel open is `makeKeyAndOrderFront` on a reused `KeyPanel` (`PanelController.swift:18, 133–160`); no entrance animation exists today.

**New**: `leave`, `press`, opacity-100 ms substitution (if approved), the policy type, the literal cleanup, numericText on two more counters.

**Deps**: none upstream. GC-V4-23 consumes `leave`, `settle`, numericText; GC-V4-22 (if ever approved) consumes `press` and `leave`.

**Verify**: extend `GanchoMotionTests` with one `@Test` per token × Reduce Motion (on/off) against the policy; a source-scan test (pattern used elsewhere in the repo for guards) that fails on `.snappy(duration:` / `.easeOut(duration:` / bare `withAnimation {` outside `GanchoMotion.swift`; manual check with System Settings › Accessibility › Display › Reduce motion on, compared with the table above.

**BLOCKED**
- Q-24a: Under Reduce Motion, keep today's `nil` (instant) for `arrive`/`leave`, or adopt the board's `opacity 100 ms`? The board claims the column is already what the code does; it is not. Adopting it changes the tested contract in `GanchoMotionTests.reduced`.
- Q-24b: “Third curve”. `V4_Gancho_Overview` says “v4 adds no third curve”, while this board adds `leave` (ease-in 140 ms, tagged `new`) as a “departure curve”. Is `leave` a new `GanchoMotion` static or an ad-hoc AppKit `NSAnimationContext` duration?
- Q-24c: `menu close` and `popovers` / `swipe return` are system animations Gancho cannot retime. Confirm they are listed as descriptive only.
- Q-24d: `V4_System_Components` describes Gancho motion differently (“Select row lifts 2 px + green shadow, 150 ms”, “Panel 180 ms scale .96→1 from the status item”, “Paste press .92 then hide; Reduce Motion → fill only”). This board (item board for 22–24) and the owner's skip of GC-V4-20 override it. System_Components needs correcting.

### GC-V4-23 — Drop a clip on a board: ring, count tick, Undo (pick)

**What changes**
- Board targets accept a dropped clip: the panel board rail chips (`Apps/GanchoMac/PanelView.swift:1009–1045`, `boardChip`) and the Library sidebar board rows (`Apps/GanchoMac/LibraryView+Sidebar.swift:17–24`, `navRow` 103–124).
- Hover target: scale 1.04 + 2 pt accent ring, under `settle` (board labels `150 ms`). Existing focus ring `railRing` is 1.5 pt primary (`PanelView.swift` around 945) and must stay distinct. Badge `+` = the copy-operation drag badge (return a copy operation from the drop proposal).
- On drop: `setBoardMembership(items, board:, member: true)` (`Apps/GanchoMac/AppModel.swift:1970–1990`), count ticks with `.contentTransition(.numericText(value:))` on the Library count (`LibraryView+Sidebar.swift:118`), card shrinks into the row (`leave`, 220 ms as drawn).
- Toast `Added to <board>` + `Undo` (+ `⌘Z`), reusing the `assignWithUndo` pattern (`AppModel.swift:1818–1830`) and `unassign` (1832–1836).
- Refused drop: shake 2 × 3 pt + reason (copy not drawn).
- Drag preview with 3° tilt (currently plain `.onDrag {}` at `Apps/GanchoMac/ClipDragProvider.swift:212`).

**Exists**
- Drag-out: `AppModel.dragProvider(for:)` (`ClipDragProvider.swift:26–42`), gate `ClipDragSource` (169–240) and `clipDragSource` (337–344); masked clips are not draggable (`Packages/GanchoKit/Sources/GanchoAppCore/ClipDragPayload.swift:29–49`). Drag keeps the panel open (`PanelController.noteDragOutStarted`, `PanelController.swift:246–260`).
- Membership write, toast with Undo, `toast-undo` id pattern (`AppModel.swift:1368`), `ToastPresenter` with action slot (`Apps/GanchoMac/ToastPresenter.swift:10–53, 104–142`).
- Library sidebar shows per-board counts; the panel rail chips show **no counts**.
- String `"Added to board"` exists in `Apps/GanchoMac/Localizable.xcstrings` (line 3729).

**New**
- An in-app drag type that carries the clip **id only** (no content) so a board can resolve it; today the provider advertises only external types (plain text / URL / PNG / file URL). A custom `UTType` may need an exported-type declaration in `project.yml` (Info.plist), then `make project`.
- Drop destinations on rail chips and sidebar rows; targeted state; shrink animation; refusal shake.
- Library grid cards are not drag sources today (`LibraryClipCard.swift` has no `clipDragSource`); dropping inside the Library needs that.
- Localized `Added to %@` (EN + ES) plus refusal reasons (EN + ES); `LocalizationTests` gates them.
- `⌘Z` for the toast Undo: the toast panel is non-activating and cannot take keys, so the binding must live in the panel and Library windows, scoped to the last drop.
- Accessibility: drop rows need a `.accessibilityDropPoint` or an equivalent action (the ⌘B picker already covers keyboard users, so this can be skipped if VoiceOver users are routed there).

**Deps**: GC-V4-24 (`settle`, `leave`, numericText rule). Interacts with the Panel/Library board specs (rail chip layout).

**Verify**: unit test (Swift Testing) for a pure “can this clip drop on this board” predicate (sensitive → refuse, already-member → no-op); XCUITest drag from `clip-row` to `board-<uuid>` then assert `gancho-toast`, `toast-undo` and the membership (follow the established `-show-multi-file-drop-target` debug pattern); manual check against frames 1–4.

**BLOCKED**
- Q-23a: Refusal “secret clip” cannot happen from an in-app drag, because masked clips are not drag sources (the board itself says so in pin 3). Drop the case, or should it cover drags from other apps?
- Q-23b: Refusal “Free limit”: there is no free cap on board **membership**; `PinLimits` caps pins (15) and board creation (3) only (`Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift:49–60`). Which limit is meant?
- Q-23c: “The card shrinks into the row” — SwiftUI `onDrop`/`dropDestination` cannot animate the system drag image into the target; it needs an AppKit `NSDraggingDestination` (`animatesToDestination`) or should become “row pulses, image disappears”. Accept the fallback?
- Q-23d: The count tick only exists where counts exist (Library sidebar). On panel rail chips (no counts), is the toast the only confirmation?
- Q-23e: Toast copy names the board (`Added to Brand`) while today's toasts say `Added to board`. Change only the drop toast or all assign toasts? The `⌘Z` hint in the toast is new UI text.

### GC-V4-22 — Paste press, check, hide, then ⌘V (MAYBE · PENDING DECISION — not to implement)

Owner note (verbatim): “no entiendo la utilidad de esto, pero siento que no es necesario”. The board says: “Owner: unclear value.” Spec for the record only.

**What would change**
- Return/click on the primary dock button: press frame (scale .96, darker, 80 ms) → symbol flips to a checkmark (reusing the existing symbol replace + bounce at `PeekActionButton.swift:65–67`) → panel fades out 140 ms ease-in → ⌘V. `⌘1–9` skip the press: 180 ms in total.
- `PanelController.hide()` (`Apps/GanchoMac/PanelController.swift:175–178`) is an instant `orderOut`; it would need an `alphaValue` fade and an alpha reset before the next `orderFront`.
- `PasteBackWorkflow.Effects.hidePanel` is synchronous (`Packages/GanchoKit/Sources/GanchoAppCore/PasteBackWorkflow.swift:39, 90`); it would become `async` (await the fade) before `waitForFocusToReturn` (80 ms, `AppModel.swift:891`). `PasteBackWorkflowTests` would change.

**Exists**: the order contract (hide → wait for focus → paste → copy-only notice, `PasteBackWorkflow.swift:20–27, 90–96`); copy-only toast `Copied — enable Accessibility to paste directly` with action `Enable` (`AppModel.swift:1142–1151`); dock focus/hover animations (`PeekActionButton.swift:49–51`). Return runs `navActions[0]` = Paste (`PanelView.swift:1382–1413`, `pasteSelected`).

**New**: press state, check state, panel fade, async hide. Adds about 260 ms + 80 ms to every paste (`Signpost.pasteDispatch`).

**Deps**: GC-V4-24 (`press`, `leave`).

**Verify (if approved)**: `PasteBackWorkflowTests` asserting paste happens only after the awaited hide; UI test that the panel is gone before the pasteboard write; Instruments signpost compare.

**BLOCKED**
- Q-22a: Owner decision — implement at all? (Default: no.)
- Q-22b: Copy-only wording conflict: the board says the check reads “Copied” and the toast says “press ⌘V”; the code toast says `Copied — enable Accessibility to paste directly` + `Enable`. Code wins unless the owner decides otherwise.
- Q-22c: Frame 3 draws the button darker (`#1F7A3A`), but the caption says “no colour change”.
- Q-22d: Is `Pasted · 1 of 3 in stack` meant as Gancho UI (no surface exists for it) or only sample target-app content?

### GC-V4-21 — Selection bar slides, stage swaps (shipped, Archive)

No work. Verified: `Components.swift:326–339` (12 % accent wash + 3 pt bar, padded `Spacing.xs`), `SharedSelectionGeometry` `Components.swift:452–465`, namespace `PanelResultsView.swift:107`; rail glide `RailGlide` `PanelView.swift:1567–1577`; peek `GanchoMotion.replace` at `ClipPeek.swift:123, 147, 150`; section counts `PanelResultsView.swift:167–171`.

### GC-V4-20 — Panel arrives from the hook (skip, Archive)

Not drawn here; owner pick “skip”. Do not implement. The “Budget” rule still applies to any future arrival animation.

---

## Owner notes

- GC-V4-22 pick = **maybe**, note: “no entiendo la utilidad de esto, pero siento que no es necesario”. On the board: “Owner: unclear value. Functional part (Command-V only after the panel hides; “Copied” when Accessibility is missing) already exists in PasteBackService; the rest is animation.” → PENDING DECISION, do not implement.
- GC-V4-23 pick = **pick**, no note.
- GC-V4-24 pick = **pick**, no note.
- GC-V4-20 pick = **skip** (Archive, discarded in triage Oct 18).
- General owner rules that bind this board: compare every proposal with the current UI and only propose what beats it; code wins over v2 boards; each piece of data appears once per screen; annotations (`v4 · …`, pins, `MAYBE`, `new`, PASS strip) are not UI.
- No owner comment thread targets this board.
