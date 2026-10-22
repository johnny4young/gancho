# V4_Gancho_Novel — Capture and paste, rethought

- **Board:** `V4_Gancho_Novel.dc.html`
- **Canvas:** 2400 × 2212 pt, background `#ECEDF0`, radius 12.
- **What it shows:** seven proposal cards (four new features GC-V6-1…4, three extensions of existing catalog items GC-09, GC-10, GC-25) for capture and paste. Each card has a mockup on the left and a text column (Improves / Reuses / Needs / Inspired by) on the right. None of these screens exists in v0.10.2.
- **Related Current boards (reference only):** `GanchoPanel_Current` (screenshot 04), `GanchoPanelActions_Current` (screenshots 05–06).
- **Same IDs drawn elsewhere (merge in the plan):** GC-09 → `V4_Gancho_PanelStates` ("Secret selected · countdown and timed reveal") and `V4_Gancho_Panel` pin 7; GC-10 → `V4_Gancho_PanelStates` ("Three selected · the stack is a visible queue"), `V4_Gancho_Panel` pin 4 (dock `Stack ⌥⌘⏎`) and `V4_Gancho_MenuBarDark` (stack-count badge); GC-25 → `V4_Gancho_MenuBarDark` ("Status item glyphs one hook, badges", pin 2) and `V4_Gancho_Panel` pin 6; GC-V6-1 ranking is reused by GC-V6-8 on `V4_Gancho_Novel2`.

Units: the board is drawn in CSS px at 1×; read every px as pt.

---

## 0. Board header (context only)

- Tag at (28, 24): `V4 · NOVEL` — 22 high, radius 7, padding 0 9, mono 11/800, letter-spacing .04em, bg `#34C759`, text `#0B2A14`.
- Title beside it (gap 12): `Capture and paste, rethought` — 26/800, letter-spacing −.02em, `#1D1D1F`.
- Intro paragraph at (28, 66), width 2340, 13/1.5, `#3A3A3F`:
  `Baseline to beat: macOS 26 Spotlight clipboard (⌘Space ⌘4 — a plain time list, plain text only, 8 h by default) and Paste 7 (cards, pinboards, Intelligent Clipboard prediction, MCP). Each card is a proposal drawn in Gancho’s tokens (brand green #34C759, kind tints, 13 pt rows, 11 pt chips), names the screenshot it improves, what the code already has and what it still needs. Purple ids extend an existing catalog item; black ids are new. Research: research/clipboard-ui.md (2026-10-17).` ("macOS 26 Spotlight clipboard" and "Paste 7" in bold.)
- Footer at (28, bottom 24), width 2340, 11.5, `#5B5B61`: `All mockups are proposals — none of these screens exists in v0.10.2. Sources are the pages listed under each card; web content was read as data only.`

## 0.1 Shared card anatomy (applies to all seven cards)

- Card: 1152 × 474, white, radius 14, shadow `0 1px 3px rgba(0,0,0,.08)`.
- Header row at (20, 16), right 20, gap 8, no wrap:
  - ID tag: 22 high, radius 7, padding 0 9, mono 11/800, letter-spacing .04em. **New** ids: bg `#1D1D1F`, text white. **Extends** ids ("purple"): bg `#E8E7FB`, text `#3D3BB0`.
  - Title: 16/800, letter-spacing −.01em.
  - `PROPOSAL` chip: 18 high, radius 6, padding 0 7, 10.5/800, letter-spacing .04em, bg `#FFF1DB`, text `#7A4B00`.
  - `new` or `extends`: 11, `#5B5B61`.
  - Right-aligned pills `impact X` / `effort Y`: 20 high, radius 999, padding 0 8, 11/700, bg `#F2F2F5`, text `#3A3A3F`, gap 6.
- Mockup well: (20, 54), 660 × 400, radius 12, bg `#ECEDF0`, clips content.
- Text column: (700, 54), width 432, 12/1.45, `#3A3A3F`. Sub-headings `IMPROVES`, `REUSES`, `NEEDS (CODE CHECK)`, `INSPIRED BY`: 10.5/800, letter-spacing .06em, uppercase, `#5B5B61`, margin-bottom 3; paragraphs margin-bottom 10; source URLs 10.5, `#5B5B61`. The text column is annotation, not UI (see each card's Implementation notes).

Shared mock primitives (used inside the wells):

| Primitive | Spec |
|---|---|
| Panel frame | bg `#F8F8F8`, radius 12, ring `0 0 0 1px rgba(0,0,0,.10)` + shadow `0 12px 30px rgba(0,0,0,.18)`, base 13 |
| Search bar | full width, 40 high, bottom hairline `#E3E3E6`, padding 0 14, gap 8, 15 pt `#6E6E73`; magnifier 15, stroke `#6E6E73` 2 |
| Section header | inset 6, 20 high, padding 0 8, 10/600, letter-spacing .03em, `#6A6A70`, label left, count right |
| Row | inset 6, 48 high, radius 10. Tile 34 × 34 radius 8 at (10, 7), glyph 16 stroke 2.1. Title 13/700 at x 56 y 7; subtitle 12 `#55555A` at y 26; single-line body (masked rows) 13 at y 15; text area right edge 96. Meta 10 `#6A6A70` at right 10 / top 7. Key badge right 10 / top 26, 15 high, radius 4, padding 0 4, bg `#E2E2E4`, text `#4A4A4F` 10/600 |
| Selected row | bg `#E3F4E6` + leading bar 3 wide, radius 2, inset 8 top/bottom, `#34C759` |
| Chip | 22 high, radius 11, padding 0 8, gap 5, 11/600, bg `#E4E4E6`, text `#3A3A3F`; **on**: bg `#34C759`, text `#0B2A14` |
| Key cap | min 18 × 18, radius 5, padding 0 4, white, ring 1 `#D6D6DA`, 11/600 `#3A3A3F` |
| Glass HUD | radius 14, bg `rgba(255,255,255,.92)`, ring 1 `rgba(0,0,0,.10)`, shadow `0 14px 34px rgba(0,0,0,.22)` |
| Button | 24 high, radius 7, padding 0 10, gap 6, 12/600, white + ring 1 `#D6D6DA`, `#1D1D1F`. **Green**: bg `#34C759`, text `#0B2A14`, no ring |
| Mini label | 10.5/700, letter-spacing .04em, `#5B5B61` |
| Menu bar (context) | 28 high strip, gradient `#3E74AF → #4A80BC` (wallpaper stand-in). Status item highlight: 22 high, radius 6, padding 0 8, bg `rgba(255,255,255,.28)`, white hook glyph 14 (stroke 2.2), 11/700 white |

Kind tiles used: code `#E5E4FA` / glyph `#5856D6` (`</>`); text `#E6E6E8` / `#6E6E73` (lines); colour = swatch of the value (`#008080`); secret `#FCE3E2` / `#D70015` (lock); link `#DDEFF9` / `#1F8FC0` (chain).

No dark variants are drawn on this board (the notch shelf is dark by design).

---

## 1. Card GC-V6-1 — `Up next: one predicted clip above the list` (realises **GC-V6-1**)

Position (28, 150), 1152 × 474. Header: ID `GC-V6-1` (black/new), `PROPOSAL`, `new`, `impact H`, `effort M`.

Mockup: panel frame at (20, 18), 620 × 370, top to bottom:

1. Search bar: magnifier + `Search your clipboard`.
2. **Up next slot**: left/right 10, top 50, 76 high, radius 12, white, ring 2 `#34C759`.
   - Label at (12, 8): `UP NEXT · ON-DEVICE` — mini label in `#1D7A34`.
   - Code tile 34 × 34 at (12, 28).
   - Body at (58, 30), mono 13: `let greeting = "Hello"` (sample) — syntax colours `let` `#A33EA3`, `"Hello"` `#2E7D32`.
   - Reason at (58, 50), 11, `#55555A`: `Xcode is in front · you pasted this into Xcode 3× today` (sample).
   - Right 12 / top 30, gap 3: key caps `⌘` `↩`.
3. Section header at top 136: `TODAY` … `7 CLIPS` (sample).
4. Rows (top 158 / 208 / 258):
   - text tile · `Seed sign-off` / `Best regards,...` · `1 minute ago` · `⌘1` (sample)
   - code tile · `Example` / mono `let greeting = "Hello"` · `1 minute ago` · `⌘2` (sample)
   - colour swatch `#008080` · `Ocean` / mono `#008080` · `1 minute ago` · `⌘3` (sample)
   - Rows keep ⌘1…; the Up next slot does not take a number (it is `⌘↩`).
5. Footer: 28 high, top hairline `#E3E3E6`, padding 0 10, gap 8, 11 `#55555A`: 6 pt dot `#34C759` + `Capturing`; right-aligned `Up next learns from your pastes · Settings › Intelligence`.

States drawn: one (slot filled). Not drawn: empty / no prediction (implied: slot absent), off.

### Implementation notes (not UI)
- Improves: `Screenshot 04: the list is sorted by time only; the clip you need for the app in front is often 3–6 rows down.`
- Reuses: `PasteBackWorkflow already knows the target app at paste time; clip.lastUsedAt , uses and clip_app_stats.pastes ; Tier 1 Apple Intelligence (optional).`
- Needs (code check): `A per-paste log (clip id · target bundle id · time) — today only counters exist, no event table. Start with a heuristic (same target app + recency); model ranking only on macOS 26. Off by default.`
- Inspired by: `Paste 7 Intelligent Clipboard (predicts the next paste, on-device). Baseline: Spotlight clipboard is a plain time list.` Sources: `https://pasteapp.io/updates · https://chatgate.ai/post/paste-7`

---

## 2. Card GC-V6-2 — `Double-copy merge, splittable` (realises **GC-V6-2**)

Position (1220, 150). Header: `GC-V6-2` (new), `PROPOSAL`, `new`, `impact M`, `effort S`.

Mockup, top to bottom:
1. Menu bar strip; status item at (500, 3): hook glyph + count badge `3` — 16 high, min-width 16, radius 8, padding 0 4, bg `#34C759`, text `#0B2A14` 10.
2. Confirmation HUD (glass) at (300, 40), 330 × 62:
   - Tile (14, 14) 34 × 34, radius 9, bg `#E3F4E6`, copy glyph (two stacked rects) 18 stroke `#1D7A34`.
   - (60, 13) 13/700: `Merged · 3 parts`
   - (60, 33) 11 `#55555A`: `⌘C twice appends · newline separator`
3. Peek frame (panel frame) at (20, 120), 620 × 260 (top 52 pt empty — no search bar drawn):
   - Header row at (14, 52), gap 8: kind chip `text` (bg `#E6E5F8`, text/glyph `#4E4CC4`, lines glyph 11) · bold `Shipping address` (sample) · 11 `#55555A` `3 parts · Safari, Mail, Notes` (sample apps).
   - Merged content box: left/right 14, top 84, 112 high, radius 12, white, inset ring 1 `#E3E3E6`, 13 / line-height 20, padding 10 12. Lines (sample): `Ana Restrepo` / `Cra. 43A #1-50, Envigado` / `+57 300 000 0000`, each part separated by a dashed 1 pt rule (`#B8B8BC`, 4 on / 4 off, margin 3 0) — part boundaries are visible.
   - Controls row at (14, 208), gap 6: `Separator` (11 `#55555A`) · chips `Newline` (on) · `Space` · `Comma` · 20 pt spacer · button with 2×2 grid glyph 12: `Split into 3 clips`.

States: separator selection (Newline selected). Feedback: sound + haptic (named in notes, not drawn).

### Implementation notes (not UI)
- Improves: `Today collecting three fields means three clips and three pastes (screenshot 04 list) or the context-menu paste stack.`
- Reuses: `Pasteboard monitor changeCount , the menu-bar badge slot (GC-25), ClipPeek text editor for the merged clip.`
- Needs (code check): `Detect a second ⌘C within ~600 ms on the same source app; store part boundaries (new column, e.g. clip.parts ) so Split works; sound + haptic opt-out. No merge code exists today.`
- Inspired by: `Alfred Merging (“Purr” sound), LaunchBar ClipMerge (stapler sound, file sets), ClipBook ⌘CC merge and split.` Sources: `https://www.alfredapp.com/help/features/clipboard/ · https://obdev.at/resources/launchbar/help/ClipboardHistory.html · https://mac.softpedia.com/get/Utilities/ClipBook.shtml`

---

## 3. Card GC-V6-3 — `Copy-time action HUD` (realises **GC-V6-3**)

Position (28, 648). Header: `GC-V6-3` (new), `PROPOSAL`, `new`, `impact M`, `effort M`.

Mockup:
1. Menu bar strip; status item at (520, 3): hook only.
2. Source context card (not Gancho UI) at (24, 56), 300 × 150, radius 10, white, ring 1 `#DCDCDF`, padding 12: mono 12 `--accent: #008080;` (the value highlighted `#CDE8F7`), `--radius: 10px;`, then 11 `any app · you just pressed ⌘C`.
3. **Colour HUD** (glass) at (300, 40), 340 × 112:
   - Swatch (14, 14) 34 × 34, radius 9, `#008080` (the copied value).
   - (60, 12) 13/700: `Colour · #008080` (value is sample).
   - (60, 31) 11 `#55555A`: `saved · HUD hides in 2 s`
   - Buttons at (14, 66), gap 6: green `Add to Colors` · `Copy as rgb()` · `esc` (a11y label `Dismiss`).
4. **One-time-code HUD** (glass) at (300, 176), 340 × 96:
   - Tile 34, radius 9, bg `#FCE3E2`, lock glyph 16 `#D70015`.
   - (60, 12) 13/700: `One-time code · ••• •••`
   - (60, 31) 11 `#55555A`: `masked · never synced`
   - At (60, 58), gap 6: green button `Forget in 60 s` · 11 `#55555A` `default 10 min`.
5. Rule text at (24, 300), width 616, 11 `#3A3A3F`: `Shown only for high-confidence Tier 0 kinds (colour, address, tracking number, one-time code, URL). One switch per kind in Settings › Capture. Never shown in Private mode or while sharing the screen.` (This sentence is drawn inside the mockup but is a rule, not HUD copy.)

States: auto-hide after 2 s; dismiss with esc. Kinds drawn: colour, one-time code. Not drawn: address, tracking number, URL HUDs; hover-pauses-timer.

### Implementation notes (not UI)
- Improves: `Detection (Tier 0, <5 ms) only pays off when the panel is opened later (screenshot 20 pipeline; screenshot 07 Convert color hidden under More actions).`
- Reuses: `ClipContentKind classifier, DevActions per kind (Convert color, Parse URL…), sensitive lifetime (Retention › Sensitive items), ScreenShareDetector to suppress it.`
- Needs (code check): `A non-activating HUD window anchored to the status item; per-kind opt-out keys; a confidence threshold so it never fires on plain text.`
- Inspired by: `Samsung One UI 8 Smart Clipboard (reported), Windows Click to Do, CleanShot X post-capture overlay.` Sources: `https://www.sammyfans.com/2025/06/23/samsungs-one-ui-8-to-introduce-smart-clipboard-feature-but-theres-a-catch/ · https://support.microsoft.com/windows/ai/ai-features/click-to-do-do-more-with-what-s-on-your-screen · https://cleanshot.com/features`

---

## 4. Card GC-10 — `Paste stack with a visible cursor` (realises **GC-10**, extended)

Position (1220, 648). Header: `GC-10` (purple/extends), `PROPOSAL`, `extends`, `impact H`, `effort M`.

Mockup:
1. Menu bar strip; status item at (520, 3): hook + text `3/5` (11, white).
2. **Floating stack strip** (glass) at (300, 40), 340 × 236, padding 12:
   - Header (13/700, gap 8, margin-bottom 8): copy glyph 14 · `Paste stack · 3 of 5` · right-aligned 10/500 `#55555A` `ends after 2 min idle`.
   - Five rows, 30 high, radius 8, padding 0 10, gap 10, 12 pt; leading index column 34 wide, centred:
     1. done: `✓` · `Ana Restrepo` — both `#8E8E93`
     2. done: `✓` · `Cra. 43A #1-50` — `#8E8E93`
     3. **next**: bg `#E3F4E6`; `NEXT` (10/800 `#1D7A34`) · `Envigado` `#1D1D1F`
     4. pending: `4` · `055422`
     5. pending: `5` · `+57 300 000 0000`
     (all row text is sample)
3. Key legend at (24, 56), width 250, 12 / line-height 1.7, `#3A3A3F`:
   - `⌘` `V` `paste next`
   - `⌥` `⌘` `→` `skip one`
   - `⌥` `⌘` `←` `step back`
   - `⌥` `⌘` `⌫` `reset`
   - (margin-top 10, 11 `#55555A`) `A new copy ends the run. The strip floats near the menu bar and never takes focus.`

States: done / next / pending rows; run end by 2 min idle or a new copy.

### Implementation notes (not UI)
- Improves: `Today the stack is a context-menu item and a 9 pt footer strip (PasteStackStrip); the position in the run is invisible.`
- Reuses: `PasteStackStrip, the “Paste from stack” global shortcut (screenshot 10), PanelSelectionContextBar “Add to stack”.`
- Needs (code check): `Expose the stack index to the status item and a floating strip; skip / back / reset actions; idle timeout.`
- Inspired by: `Raycast Paste Sequentially + Reset Paste Sequence, Paste ⌘⇧C stack window.` Sources: `https://manual.raycast.com/clipboard-history · https://www.macstories.net/reviews/paste-the-clipboard-management-utility-gets-an-elegant-new-design-on-the-mac/`

---

## 5. Card GC-25 — `Capture state in the glyph, modifier clicks, screen-share mode` (realises **GC-25**, extended)

Position (28, 1146). Header: `GC-25` (purple/extends), `PROPOSAL`, `extends`, `impact M`, `effort S`.

Mockup:
1. **Glyph strip**: (20, 20), 620 × 96, white, radius 12, five columns 112 wide (space-around). Each: glyph tile 36 × 26, radius 7, bg `#3E74AF` (menu-bar stand-in), white hook 15 (stroke 2.2); badge 10 × 10 circle at right −3 / bottom −3 with 2 pt white ring; label 12/700 (margin-top 6); sub 10.5 `#55555A`.

   | Label | Sub | Badge |
   |---|---|---|
   | `Capturing` | `template hook` | none |
   | `Ignore next` | `one copy skipped` | `#5856D6` |
   | `Paused` | `⌥-click` | `#FF9F0A` |
   | `Private` | `timer in menu` | `#5E5CE6` |
   | `Sharing` | `previews hidden` | `#D70015` |

2. Modifier legend at (20, 132), 12 `#3A3A3F`, gap 18: `⌥` `click · pause / resume` · `⌥` `⇧` `click · ignore next copy` · `click · menu`.
3. Panel frame at (20, 168), 620 × 210:
   - Search bar `Search your clipboard`.
   - **Screen-share banner**: left/right 10, top 50, 52 high, radius 10, bg `#FCE8E7`, text `#7A1A14` 12, padding 0 12, gap 10. Eye glyph 16 `#D70015`. Line 1: bold `Screen share detected` + ` · previews hidden, capture paused`. Line 2 (11): `Zoom is sharing. Rows show kinds only.` (app name is sample). Trailing button `Show anyway`.
   - Masked rows (top 112 / 160): code tile · `•••` (letter-spacing .2em, `#55555A`) · `⌘1`; link tile · `•••` · `⌘2`. No title, no meta/time — kind tile only.

States: five glyph states; sharing banner with override.

### Implementation notes (not UI)
- Improves: `Screenshot 21: the menu says “Gancho: capturing” but the glyph never changes for ignore-next or sharing; screenshot 13 hides auto-pause behind Settings.`
- Reuses: `ScreenShareDetector (process-based, no permission), Ignore next copy and Private mode commands, the template hook glyph.`
- Needs (code check): `Badge rendering on the status item; ⌥-click / ⌥⇧-click handling. Keep the code’s rule: no NSWindow.sharingType hiding (broke external displays, Maccy #1136) — hide previews instead.`
- Inspired by: `Maccy modifier clicks, Paste “Show during screen sharing”, PastePal Control Center toggle.` Sources: `https://github.com/p0deje/Maccy · https://pasteapp.io/updates · https://apps.apple.com/app/id1503446680`

---

## 6. Card GC-V6-4 — `Notch shelf: drop onto boards and actions` (realises **GC-V6-4**)

Position (1220, 1146). Header: `GC-V6-4` (new), `PROPOSAL`, `new`, `impact M`, `effort L`.

Mockup (desktop context: wallpaper gradient `#5D7FA8 → #9DB3CC`, menu bar 26 high `rgba(0,0,0,.18)`, notch 160 × 30 at (250, 0), bottom radii 14, `#000`):
1. **Shelf** hanging from the notch: (110, 30), 440 × 230, bottom radii 22, bg `#1C1C1E`, shadow `0 18px 40px rgba(0,0,0,.35)`, padding 14; two columns, gap 12.
   - Left column (flex, gap 6): heading `DROP ON A BOARD` (10.5/800, letter-spacing .06em, `#C7C7CC`); board rows 30 high, radius 8, padding 0 10, gap 8, bg `#2C2C2E`, white 12; 10 pt colour dot; right count 11 `#C7C7CC`:
     - dot `#E8912D` `Seed board 1` `12` (sample)
     - dot `#E8912D` `Seed board 2` `4` (sample)
     - dot `#3D8F96` `Seed board 3` `9` (sample)
   - Right column, 196 wide: heading `OR AN ACTION` (margin-bottom 6); 2 × 2 grid of 92 × 70 tiles, gap 8, radius 10, bg `#3A3A3C`, glyph 18 white (stroke 2) above label 11/600 white, gap 6:
     - `Extract text` (viewfinder-with-lines glyph)
     - `Resize` (photo glyph)
     - `Strip location` (shield glyph)
     - `New board` (plus glyph)
2. Dragged item: 120 × 80 at (300, 280), white, radius 8, rotated −4°, shadow `0 10px 24px rgba(0,0,0,.3)`, photo glyph 26 `#C77700`.
3. Caption at (20, 372), width 620, 11, white: `Drag anything toward the notch (or the menu-bar hook on Macs without one). ⌥-drag out copies, ⌘-drag moves.`

States not drawn: hover/target highlight on a board row or action tile, drop success, Mac without notch.

### Implementation notes (not UI)
- Improves: `Boards can only be filled from the panel or the Library context menu (screenshots 04, 22); there is no drop target at all (no onDrop in the code).`
- Reuses: `Boards and BoardIdentityMark colours, ClipDragProvider (drag-out), screen-text OCR (Extract text), the image clip pipeline.`
- Needs (code check): `Notch geometry ( NSScreen.safeAreaInsets / auxiliary areas — not used today), a global drag-session monitor, drop handling and the image actions (resize, strip EXIF) — new code.`
- Inspired by: `Dropover (shake, notch drop, Instant Actions), Yoink edge shelf, Dropzone action grid, Unclutter top-edge drawer.` Sources: `https://dropoverapp.com/ · https://eternalstorms.at/yoink/mac/ · https://aptonic.com/blog/dropzone-4-versus-dropzone-3-should-i-upgrade · https://unclutterapp.com/`

---

## 7. Card GC-09 — `Masked everywhere, revealed by holding a key` (realises **GC-09**, extended)

Position (28, 1644). Header: `GC-09` (purple/extends), `PROPOSAL`, `extends`, `impact H`, `effort M`.

Mockup: panel frame at (20, 18), 620 × 360:
1. Search bar `Search your clipboard`.
2. Section header at top 46: `TODAY` … `3 CLIPS` (sample; only two rows drawn).
3. Row 1, **selected**, top 68: secret tile · `Stripe key` / mono `sk_live_••••••••4Q2v` · meta `expires in 0:45` in `#9A5A00` · `⌘1` (sample).
4. Row 2, top 118: code tile · `Example` / mono `let greeting = "Hello"` · `2 min` · `⌘2` (sample).
5. **Secret peek card**: left/right 10, top 178, 170 high, radius 12, white, inset ring 1 `#F2C7C4`, padding 14:
   - Header (gap 8): chip `secret` (bg `#FCE3E2`, text/lock glyph `#B3141B`, glyph 11) · bold `Stripe key` · right 11 `#9A5A00` `expires in 0:45`.
   - Value (margin-top 14), mono 15, letter-spacing .06em: `sk_live_` + masked block (16-char width, bg `#E4E4E6`, radius 4, text transparent) + `4Q2v`.
   - Lifetime bar (margin-top 12): 6 high, radius 3, track `#F2F2F5`, fill 38 % `#34C759`; fill pulses opacity 1 → .55 → 1 over 1.6 s only when Reduce Motion is off.
   - Action row (margin-top 10, 12 pt, gap 8): `Hold ⌥ to reveal` (with key cap `⌥`) · right-aligned buttons `Keep 10 more min` · `Delete now` (text `#B3141B`).
   - Rule line (margin-top 8, 11 `#55555A`): `Never in widgets, the keyboard preview, Spotlight or MCP results.`

States: masked (drawn); revealed while ⌥ held (described, not drawn); expiry countdown.

### Implementation notes (not UI)
- Improves: `Secrets are masked in rows, but the Mac peek has no reveal or expiry control (OCR reveal only, PeekImageText) and the same rule is not stated for widgets, keyboard and MCP.`
- Reuses: `isSensitive , expiresAt , SensitivePasteboardTypes (concealed / transient / auto-generated), sensitive lifetime 5/10/30 min, the MCP sensitive veto (screenshot 19).`
- Needs (code check): `Hold-to-reveal gesture and a “keep longer” action capped by the retention limit. On iOS the app cannot read other apps’ sensitivity flags, so its own detection decides.`
- Inspired by: `Android EXTRA_IS_SENSITIVE hides keyboard previews; Alfred ignores concealed data. Counter-example: Spotlight may store third-party passwords.` Sources: `https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling · https://www.alfredapp.com/help/features/clipboard/ · https://eshop.macsales.com/blog/98115-spotlight-gets-supercharged-in-macos-tahoe-your-complete-guide-to-getting-more-out-of-the-default-mac-launcher/`

---

## Coverage

| Board element | ID(s) |
|---|---|
| Board header tag, title, intro paragraph | context only |
| Footer disclaimer | context only |
| Card 1: Up next slot, list, footer hint | GC-V6-1 |
| Card 1 text column | GC-V6-1 (notes) |
| Card 2: menu-bar count badge | GC-V6-2 (uses GC-25 badge slot) |
| Card 2: Merged HUD, merged peek, separator chips, Split | GC-V6-2 |
| Card 3: source CSS snippet | context only |
| Card 3: colour HUD, one-time-code HUD, rule text | GC-V6-3 (OTP lifetime touches GC-09 sensitive lifetime) |
| Card 4: `3/5` status item, floating strip, key legend | GC-10 (extends; also PanelStates, Panel pin 4, MenuBarDark stack badge) |
| Card 5: five-glyph strip, modifier legend | GC-25 (extends; also MenuBarDark pin 2) |
| Card 5: screen-share banner + masked rows | GC-25 |
| Card 6: wallpaper, notch, dragged file | context only |
| Card 6: shelf boards, action grid, caption | GC-V6-4 |
| Card 7: masked row with countdown, secret peek, hold-to-reveal, keep/delete, rule line | GC-09 (extends; also PanelStates, Panel pin 7) |
| Numbered pins | none on this board |

---

## Feasibility

Shared finding — **feature flags:** no feature-flag system exists. Gates in code are (a) Codable preference structs with `decodeIfPresent` defaults (`CapturePreferences` key `capture-preferences`, `Packages/GanchoKit/Sources/ClipboardCore/CapturePreferences.swift:31`; `IntelligencePreferences` key `intelligence-preferences`, `.../IntelligencePreferences.swift:57`), (b) plain `UserDefaults`/`@AppStorage` booleans (e.g. `auto-pause-screen-share`, `spotlightIndexing`, ambient tint in `PanelView.swift:112`), and (c) `#if DEBUG` launch arguments (`AppModel.swift:401–421`, e.g. `-disable-screen-share-auto-pause`). Unfinished features can ship dark as an off-by-default preference not surfaced in Settings, flipped by a DEBUG-only launch argument for UI tests.

Shared finding — **menu-bar process split:** production paints the status item in `Apps/GanchoMenuBarHelper/main.swift` (paint-only, content-free); `StatusItemController.swift` is the in-process fallback. State crosses via `GanchoMenuBarBridge` written by `GanchoMenuBarStatusPublisher` (`Apps/GanchoMac/GanchoMacApp.swift:370`, 1 s poll, publishes only when `MonitorStatus` changes). Anything shown on the glyph (badges, `3/5`) must be content-free state added to that bridge and rendered in both processes.

### GC-V6-1 — Up next (feature, new)
- **What changes:** an optional slot above the list predicting one clip for the frontmost app, with reason text and `⌘↩`; footer hint; a toggle in Intelligence (off by default).
- **Exists:** frontmost target at paste time (`AppModel.currentReuseTargetBundleID()`, `Apps/GanchoMac/AppModel.swift:1033`; `PasteBackWorkflow.deliver(intendedTarget:recordReuse:)`, `Packages/GanchoKit/Sources/GanchoAppCore/PasteBackWorkflow.swift:79`); `clip.lastUsedAt`, `clip.uses` (migration v13, `GanchoDatabaseMigrator.swift:259–261`); `clip_app_stats(bundleID, day, captures, pastes)` (`GanchoDatabaseMigrator.swift:385`) — per destination app per day, **no clip id**, content-free by design (`PrivateActivityReceipt.swift:154`). `ReuseController.recordPaste` (`GanchoAppCore/ReuseController.swift:114`). `IntelligencePreferences` for the toggle.
- **New:** migration v27 `paste_event(clipID TEXT, targetBundleID TEXT, pastedAt DATETIME)` (+ index `(targetBundleID, pastedAt DESC)`), pruned on a rolling window and on clip delete (FK cascade or trigger), never synced, excluded from export; heuristic ranker (same target + recency + frequency) as a pure type in `GanchoAppCore` with Swift Testing; Foundation Models ranking behind `#available(macOS 26, *)`; new `IntelligencePreferences.upNext` (default false — note existing intelligence toggles default **true**); slot view in `PanelView`; `⌘↩` handler (today `⌘↩` falls through to normal paste, `PanelView.swift:586–603`); new strings EN+ES.
- **Privacy:** paste log links clip ids to target apps — content-free but behavioural; must exclude sensitive clips (`isSensitive`/`prefersMaskedPreview`), stay local, and be cleared by "clear history". The reason line names the app and a count — no content. Up next must hide when previews are hidden (private mode / screen share).
- **Perf:** ranking on every panel open — keep to one indexed query bounded by recent window; no model call on the open path (precompute on paste).
- **Deps:** GC-V6-8 (iPhone keyboard Up next reuses the ranking via app group); GC-25 previews-hidden rule.
- **Verify:** unit tests for ranker and migration (`DatabaseMigrationTests` identifier list); UI test with seeded paste events asserting `up-next-slot` (new id) and `⌘↩` pastes it; snapshot vs card 1.
- **BLOCKED:** the footer says `Settings › Intelligence`, but Intelligence is a separate window opened from Settings › Capture (`CaptureSettingsTab.swift:20–23`), not a Settings pane — which path should the hint name?

### GC-V6-2 — Double-copy merge (feature, new)
- **What changes:** a second ⌘C within ~600 ms from the same source app appends to the previous clip with a separator; HUD + count badge + sound/haptic; peek shows parts, separator chips and `Split into N clips`.
- **Exists:** `MacPasteboardMonitor` polls `changeCount` with `AdaptivePollingPolicy` — active 250 ms, idle 1500 ms after 30 s (`ClipboardCore/AdaptivePollingPolicy.swift:29–32`); source app is captured; ClipPeek text editor. No merge code, no `NSSound`/`NSHapticFeedbackManager` anywhere.
- **New:** detection in the ingestion path (changeCount delta ≥ 2 in one tick, or two ticks within window, same `sourceAppBundleID`); schema column `clip.parts` (JSON offsets) — migration v27/v28 and `ClipRecordMapper` (sync) update so parts survive sync; merge writes must mark `needsUpload`; split creates N clips; separator preference; sound + haptic opt-out preference; HUD window (shared with GC-V6-3); badge via bridge (GC-25).
- **Privacy:** merging must run after the sensitive-type veto and the secret detector on the **merged** text (a merged clip containing a secret becomes sensitive/expiring); never merge into a sensitive or concealed capture.
- **Perf:** 600 ms window vs 250 ms active poll gives coarse timing; at idle (1.5 s poll) detection fails — would need to force active mode after a copy. Do not shorten the global poll.
- **Deps:** GC-25 (badge slot), GC-V6-3 (HUD window).
- **Verify:** unit tests on a pure merge/split model (boundaries, separators, sensitive re-check); monitor test with a fake `PasteboardReading`; UI test for Split; snapshot vs card 2.
- **BLOCKED:** "⌘C twice" on the *same* selection vs a *new* selection: Alfred-style merge appends a new selection copied twice quickly — confirm the trigger is "same content copied twice within 600 ms appends to the previous clip", and whether merge is on or off by default.

### GC-V6-3 — Copy-time action HUD (feature, new)
- **What changes:** after a high-confidence capture of colour / address / tracking number / one-time code / URL, a 2 s non-activating HUD with 1–3 actions; per-kind switches in Settings › Capture; suppressed in private mode and while sharing.
- **Exists:** `RuleClassifier.classify` returns a single `ClipContentKind` with no confidence score (`GanchoAI/RuleClassifier.swift:22`; data-detector kinds only when the match covers the whole string); kinds `color`, `address`, `trackingNumber`, `url` exist (`GanchoKit/ClipContentKind.swift`); DevActions (`GanchoAI/DevActions.swift`); nonactivating `NSPanel` pattern in `PanelController.swift:348`; `ToastPresenter.swift`; `ScreenShareDetector`; Settings › Capture tab (`CaptureSettingsTab.swift`).
- **New:** HUD window (nonactivating panel anchored to the status item — the helper owns the item in production, so the main app must get its frame or anchor top-right); a `oneTimeCode` detection (no such kind today); confidence/threshold API; per-kind prefs in `CapturePreferences`; actions `Add to Colors` (no "Colors" board exists — only Favorites is a system board), `Copy as rgb()`; per-clip short lifetime (`Forget in 60 s` is below the 5-min minimum of the sensitive picker, `RetentionSettingsTab.swift:30–37`).
- **Privacy:** OTPs from password managers / Messages autofill carry Concealed/Transient/AutoGenerated types and are **never stored** (`SensitivePasteboardTypes.captureVeto`, `ClipboardCore/SensitivePasteboardTypes.swift:18`) — the HUD must never appear for vetoed copies and must never say `saved` for them. Never show content of sensitive kinds in the HUD; no HUD while sharing (detector) or in private mode.
- **Perf:** classification already runs at capture; HUD creation must reuse one window, not allocate per copy.
- **Deps:** GC-25 (screen-share state), GC-09 (sensitive lifetime), GC-V6-2 (shared HUD).
- **Verify:** unit tests on a pure "should show HUD" policy (kind, confidence, private, sharing, per-kind prefs); UI test with seeded capture; snapshot vs card 3.
- **BLOCKED:** (1) Is a one-time code that Gancho *does* store (no veto markers) allowed a 60 s lifetime below the 5-min floor? (2) What is "Colors" in `Add to Colors` — a new system board? (3) Copy says `Colour` (UK) while the app uses "Color" (`Convert color`) — which spelling for EN?

### GC-10 — Paste stack with a visible cursor (feature, extends)
- **What changes:** stack keeps done items and a cursor (`3 of 5`); status item shows `3/5`; floating non-focus strip near the menu bar; paste next / skip / back / reset; 2-min idle end; a new copy ends the run.
- **Exists:** `PasteStack` FIFO value type — `popFirst` consumes entries, so no history/cursor (`GanchoAppCore/PasteStack.swift:15–72`; session-only, never persists/syncs); `AppModel.pasteNextFromStack` (`AppModel.swift:1327`); global shortcut `.pasteFromStack` (no default, `GlobalShortcuts.swift:17`, recorder in `GeneralSettingsTab.swift:60`); footer `PasteStackStrip` (9 pt, `PasteStackStrip.swift:31`); `⌥⌘↩` enqueues from the panel (`PanelView.swift:595`); `PanelSelectionContextBar`.
- **New:** cursor model (entries + index, done/next/pending, skip/back/reset, idle timer, end-on-new-copy hook from the monitor); floating strip window; bridge field for `index/count` and helper rendering; three/four new global hotkeys.
- **Platform:** global shortcuts use KeyboardShortcuts (Carbon hotkeys); there are no event taps or global key monitors in the code. `⌘V paste next` means hijacking ⌘V system-wide while a run is active (register/unregister a Carbon hotkey for ⌘V, then synthesize the paste) — fragile and affects every app.
- **Privacy:** strip shows clip text near the menu bar — must use masked display for sensitive items and hide previews while sharing/private.
- **Deps:** GC-25 (badge/text on glyph), Panel board dock `Stack ⌥⌘⏎`, PanelStates GC-10 card, MenuBarDark stack badge, GC-V6-8 (Live Activity stack cursor).
- **Verify:** Swift Testing on the cursor model (skip/back/reset/idle/new-copy); UI test strip a11y id (e.g. `paste-stack-strip` exists today); snapshot vs card 4.
- **BLOCKED:** (1) Should ⌘V really be captured globally during a run, or stay on the user's "Paste from stack" shortcut? (2) `⌥⌘⌫` is Finder's "Delete Immediately" and `⌥⌘←/→` switch tabs in common browsers — confirm these defaults. (3) Glyph shows `3/5` text here but a count badge `2` on MenuBarDark — which?

### GC-25 — Capture state glyph, modifier clicks, screen-share mode (feature, extends)
- **What changes:** keep the hook, add a coloured badge per state; ⌥-click pause/resume, ⌥⇧-click ignore next copy, click opens menu; during a detected share the panel hides previews (rows show kind only) with a banner naming the app and `Show anyway`.
- **Exists:** `MenuBarStatusIcon` swaps the whole glyph for SF Symbols in paused/stopped/denied (`GanchoMenuBarCommand.swift:191–204`), hook drawn as an 18 pt template (`:221`); `StatusItemPresentation` maps `MonitorStatus` (`StatusItemController.swift:247–269`) — note `.pausedByUser` is private mode; ignore-next is a private bool in the monitor (`MacPasteboardMonitor.swift:92`, not observable); `item.menu = menu` so every click opens the menu (`StatusItemController.swift:68`, helper `main.swift:32`); `ScreenShareDetector` returns only a Bool (`ClipboardCore/ScreenShareDetector.swift`), 3 s timer (`CaptureLifecycleController.swift:96`); screen share already pauses capture and shows footer copy `Paused while screen sharing` (`PanelStatusFooter.swift:118`); `previewsHidden` exists in row/card components but is wired only to private mode (`PanelView.swift:439,1303,1313`, `LibraryView+Browsing.swift:146`).
- **New:** badge compositing (template image cannot carry colour — compose a non-template image per appearance or overlay a layer on `NSStatusBarButton`); bridge fields for ignore-next/sharing/private; expose ignore-next state; replace `item.menu` with a button action reading `NSApp.currentEvent?.modifierFlags` (both processes); `previewsHidden = privateMode || (sharing && !showAnyway)`; detector returns which app (helper → app name map); banner copy + `Show anyway`.
- **Privacy:** keeps the no-`sharingType` rule; `Show anyway` must be per-share-session and reset when sharing ends.
- **Perf:** status publisher already polls 1 s; adding fields is negligible.
- **Deps:** GC-V5-1 (menu shortcut), GC-24 (menu mini-panel), GC-06 (footer chip colours), GC-V6-2 / GC-10 (badge slot).
- **Verify:** unit test on presentation mapping (state → badge); UI test seeding share state via a DEBUG argument, asserting masked rows and banner; snapshot vs card 5 and MenuBarDark.
- **BLOCKED:** badge sets disagree — Novel: ignore-next `#5856D6`, paused `#FF9F0A`, private `#5E5CE6`, sharing `#D70015`, 10 pt badge; MenuBarDark: paused amber "sharing or manual", private indigo, denied red, syncing, stack count, 12 pt badge, no ignore-next. Which set and size?

### GC-V6-4 — Notch shelf (feature, new)
- **What changes:** dragging anything toward the notch (or the hook on Macs without one) drops down a dark shelf with boards (counts) and actions Extract text / Resize / Strip location / New board; ⌥-drag out copies, ⌘-drag moves.
- **Exists:** drag-out only (`Apps/GanchoMac/ClipDragProvider.swift`, `ClipDragSource`; `PanelController.swift:297` multi-file session); OCR (`GanchoAI/ImageTextExtractor.swift`); boards API `createBoard` / `setBoardMembership` (`AppModel.swift:1866,1963`); `BoardIdentityMark`. No drop destination anywhere (no `onDrop`/`dropDestination`/`registerForDraggedTypes`); no `safeAreaInsets`/`auxiliaryTopLeftArea`; no resize or GPS/EXIF strip code.
- **New:** notch geometry via `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (macOS 12+, no `#available` needed at 15.4); a drop-sensing surface (a thin transparent window at the top edge registered for dragged types is cheaper than a global `NSEvent` mouse-drag monitor); shelf window; ingest of dropped items through the normal capture pipeline (sensitive veto + detector); image actions via ImageIO (`CGImageDestination` without GPS keys).
- **Privacy:** dropped content becomes stored clips — must pass the same denylist/secret detection; never read the drag pasteboard until a drop is accepted.
- **Perf:** an always-on global drag monitor fires on every mouse-drag event system-wide — avoid; multi-display notch detection on screen changes.
- **Deps:** boards/sync (membership changes must mark `needsUpload`), screen OCR.
- **Verify:** unit tests for geometry calc and EXIF strip; UI test dropping a file onto a board row; snapshot vs card 6.
- **BLOCKED:** effort L and no shelf on iPad/iPhone — confirm Mac-only and whether "drag anything" includes files from Finder (file references) or only images/text.

### GC-09 — Masked everywhere, hold to reveal (feature, extends)
- **What changes:** Mac peek gets a masked value, live countdown and lifetime bar, hold-⌥ reveal, `Keep 10 more min`, `Delete now`; rule line that secrets never reach widgets, keyboard, Spotlight, MCP.
- **Exists:** `isSensitive`, `expiresAt` (migration v1); `ClipSafePresentation.requiresMasking` (`GanchoKit/WidgetClips.swift:11`); stored masked preview `●●●● 4Q2v` (bullets + last 4, `GanchoAI/SensitiveDataDetector.swift:262`); peek expiry label in warning colour under 600 s (`ClipPeek.swift:381–389`); Mac reveal only for OCR (`PeekImageText.swift:16`, `ManualOCRReview.swift`); iOS tap-`Reveal` (`Apps/GanchoiOS/ClipDetailView.swift:95–97,307`, no Face ID/`LAContext`); keyboard excludes sensitive (`KeyboardClips.swift:16`), MCP filters them (`MCPToolRunner.swift:116–151`), Spotlight excludes (`LibrarySpotlightService.swift:60`); widgets **mask** (`•••`) rather than omit; sensitive lifetime 5/10/30 min, "shorten but not extend" (`RetentionSettingsTab.swift:30–43`).
- **New:** hold-⌥ reveal (flagsChanged monitor scoped to the panel; reads full content on demand, re-masks on release/blur); countdown + bar; `Keep 10 more min` (updates `expiresAt`); `Delete now`; prefix-preserving mask (`sk_live_…4Q2v`) is a change to `SensitiveMasking`.
- **Privacy:** reveal must never write content to logs; reveal must be blocked while sharing/private (GC-25); prefix display leaks key type.
- **Deps:** GC-25 (previews hidden), GC-20 (retention dial + forget), PanelStates/Panel pin 7 versions.
- **Verify:** unit tests on lifetime extension cap; UI test: hold ⌥ (a11y id e.g. `secret-reveal`), keep-longer updates countdown; snapshot vs card 7.
- **BLOCKED:** (1) Reveal model: Novel draws `Hold ⌥ to reveal`, PanelStates draws `Reveal for 10 s` and Panel pin 7 says "Reveal 10 s"; catalog agrees with hold-⌥ — which? (2) `⌥↩` is Plain paste, so holding ⌥ to paste plain would reveal the secret — acceptable? (3) `Keep 10 more min` "capped by the retention limit" contradicts the Retention copy "you can shorten but not extend" — cap at what? (4) Masked format: boards draw `sk_live_••••4Q2v`; code stores `●●●● 4Q2v` (Panel pin 7 says it is "already the stored masked preview", which is not true). (5) "Never in widgets": widgets show masked rows today — omit or keep masked?

---

## Owner notes

- Pick state: GC-09, GC-10, GC-25, GC-V6-1, GC-V6-2, GC-V6-3, GC-V6-4 are all `pick`, no pick note.
- No owner comment thread targets this board. General rules apply: compare every proposal with the current UI and propose only what beats it; code wins over v2 boards; each piece of data appears once per screen; annotations are not UI.
