# V4_Gancho_iPhoneSurfaces — spec

- **Board:** `V4_Gancho_iPhoneSurfaces.dc.html`, canvas **1760 × 1180** (bg `#ECEDF0`, radius 12, padding 24 × 28, column gap 14).
- **What it shows:** the iOS surfaces outside the main app (share extension, widgets, Live Activity, keyboard) audited against code, with the v4 additions drawn, plus the iPhone "Text in image" section (iOS parity of the Mac OCR peek). Light mode only; no dark variants drawn.
- **Related Current board:** `GanchoPhone_Current` (iPhone history list, reference only). The clip-detail chrome around "Text in image" belongs to the iPhone detail spec (`V4_Gancho_iPhone`), not to this board.
- **Catalog items realised:** GC-V4-15, GC-V4-16, GC-V4-17, GC-V4-18, GC-V4-19. Legacy chips on the board: GC-29, GC-30, GC-31, GC-32 (see Coverage). GC-V6-8 (board `V4_Gancho_Novel2`) is **not drawn here** but touches the same surfaces (overlap noted in Feasibility).
- **Device frame:** iPhone 390 × 844 pt, radius 44, bg `#F2F2F7`, border 1 `rgba(29,29,31,.14)`, status bar 54 high (`9:41`, `●●●●`, cloud glyph, battery), home indicator 134 × 5 at bottom 8.

Text colours used throughout: primary ink `#1D1D1F`; secondary `#5B5B61`; tertiary/meta `#6E6E73`; green fill `#34C759` (system green, `GanchoTokens.Palette.accent`) with ink `#0B2A14`; green text ink `#1F7A3A` (accent-ink, see B-GC-02 / GC-V5-2); danger `#C8231B` / `#FF3B30`. Board colours (sample): Work `#2E70D1`, Brand `#F08C08`.

---

## Board header (top row)

Left to right: ID chips `GC-29` (green chip `#34C759`/`#0B2A14`), `GC-30`, `GC-31`, `GC-32` (dark chips `#1D1D1F`/white; all 22 high, radius 7, mono 11/800); title 22/800; subtitle 13 `#5B5B61`; right-aligned meta.

- Title: `iPhone surfaces · share sheet, widgets, Live Activity, keyboard, text in image`
- Subtitle: `The surfaces outside the main app, audited against GanchoShare, GanchoWidgets and GanchoKeyboard: what shipped is labelled, what v4 adds is drawn. Last column: the iOS parity the “Texto en la imagen” design left pending.`
- Meta: `Gancho · iOS 26 · v4 · 390 × 844`

Context only (not UI).

---

## Column 1 — `GC-29` Share extension · Save to Gancho → GC-V4-15

Label row: chip `GC-29` + `Share extension · Save to Gancho` (13/800) + small `preview · title · board · pin` (12/600 `#5B5B61`).

### Structure (top to bottom)
1. **Host app behind the sheet** (opacity .55; padding 8 16 0, gap 6): Safari address bar 36 high, radius 12, white, lock glyph 11 + `example.com` (13, `#5B5B61`) (sample); three placeholder lines 12 high radius 4, widths 70 % / 88 % / 60 %.
2. **Sheet** from y = 250 to bottom (≈ 594 high), bg `#F2F2F7`, top radius 28, shadow `0 -10 40 rgba(0,0,0,.25)`.
   - Grabber 36 × 5, radius 3, `#C7C7CC`, top margin 8.
   - Title bar (padding 12 16 8, 17/700): left `Cancel` (17, regular, `#1F7A3A`); centre `Save to Gancho`; right 52 pt spacer.
   - **Preview card** (margin 4 16 0; padding 12 × 14; radius 14; white; border 1 `rgba(0,0,0,.06)`; gap 12): tile 36 × 36 radius 8, gradient 160° `#5BC4F0 → #32ADE6`, letter `E` (15/800, `#0A2B3A`); text column gap 3:
     - `Example Domain` (15/700) (sample)
     - `https://www.example.com/a/b?q=a&b` (mono 12, `#5B5B61`, one line, tail ellipsis) (sample)
     - `link · from Safari` (11, `#6E6E73`) (kind + source app; sample values)
   - Group header `Title` (13, `#5B5B61`, uppercase via text-case → renders `TITLE`, letter-spacing .02em; padding 12 top, 0 bottom, 16 sides).
   - Group (margin 0 16; white; radius 12): one row min 44 pt, padding 10 × 16: text field (16 pt, a11y label `Title`, value `Example Domain` (sample)) + trailing `written on-device` (12, `#6E6E73`).
   - Group header `Add to board` (same style, renders `ADD TO BOARD`) — **padding 16 pt above, 8 pt below, 16 sides** (owner decision 3, drawn exactly).
   - Board chips (wrap; padding 0 16; gap 6). Chip: height 30, radius 999, padding 0 12, gap 4, font 13:
     - `Work` — selected: fill `#34C759`, ink `#0B2A14`, 600, check glyph 11 (stroke 2.6) replaces the colour swatch. (sample board)
     - `Brand` — unselected: fill `rgba(120,120,128,.16)`, ink `#3A3A3F`, 500, 10 × 10 swatch radius 3 `#F08C08`. (sample board)
     - `New board` — unselected fill, ink `#1F7A3A`, plus glyph 12.
   - Group (margin 12 16 0; white; radius 12): row 44 pt: leading pin glyph 20 in a 28 pt column, `#1F7A3A`; `Pin it` (16); trailing switch 51 × 31 **off** (`#E9E9EB`, knob 27 white). Drawn a11y label on the switch: `Toggle` (generic — see Feasibility).
   - Primary button (padding 16 16 0): full width × 50, radius 14, fill `#34C759`, ink `#0B2A14`, 17/700, gap 8, down-arrow glyph 18: `Save to Gancho`.
   - Footer (13, `#5B5B61`, line-height 1.35, padding 10 16 0): `Saved on this iPhone · Work syncs with your Mac. Nothing is sent anywhere else.` (`Work` is the selected board — sample.)

### States
Drawn: Work selected, Brand unselected, Pin off. Not drawn: no-board, new-board entry, multi-select, image/text previews, error, saving/progress, dark mode, haptics.

---

## Column 2 — `GC-31` Widgets · small, medium, large, control → GC-V4-16

Label: chip `GC-31` + `Widgets · small, medium, large, control` + small `large is new`. Column width 360, gap 12.

Common widget shell (`.wg`): radius 22, white, border 1 `rgba(0,0,0,.08)`, shadow `0 10 30 rgba(0,0,0,.12)`, padding 12, vertical gap 6. Header 11/700, gap 6, brand mark (template, 12 pt; the real `Resources/Brand` mark, not `paperclip`). Row: height 22, gap 7, text 11.5 one line ellipsis, meta 10 `#6E6E73`; leading 36 pt tile drawn at scale 0.9. Save button: height 30 (medium 26), radius 10, fill `#34C759`, ink `#0B2A14`, 12/700, down-arrow glyph 12, pinned to bottom.

### 2a. Small (tag `Shipped · small`) — kept
158 × 158. Header `Recent`. Rows: `example.com` · `7 min`; `let greeting = "Hello"` · `now` (code tile `#5856D6` on 16 % tint). Button `Save clipboard`. (sample rows)

### 2b. Explanatory text (tag `Shipped · medium` placed beside small)
`Small: 2 rows + Save. Medium: 3 rows + sync age. Both exist (RecentClipsWidget, maxRows); masked clips show a lock and no preview, concealed copies never appear.` → implementation note.

### 2c. Medium (tag `Shipped · medium`) — kept
338 × 158. Header `Recent clips` + right `synced 2 min` (10/500 `#5B5B61`, cloud-check glyph 10). Rows (row gap 6):
- `example.com` · `Safari · 7 min`
- `let greeting = "Hello"` · `Mac · now`
- `Ocean · #008080` · `Mac · now` (colour tile `#008080`)
Button `Save clipboard` (26 high). (sample rows)

### 2d. Large (tag `v4 · large`) — new
**338 × 354** (system large size, unchanged per owner).
1. Header: mark + `Gancho`; right `synced 2 min` (as medium).
2. Board chips row — **margin 4 above / 6 below plus the 6 pt stack gap ⇒ 10 pt from header to chips, 12 pt from chips to first row** (owner decision 3: breathing room above and below). Chips gap 5; chip 18 high, padding 0 7, radius 999, fill `rgba(29,29,31,.07)`, 10.5/600 `#3A3A3F`:
   - `All` selected (fill `#34C759`, ink `#0B2A14`, check 9)
   - `Work` (8 × 8 swatch r3 `#2E70D1`) · `Brand` (swatch `#F08C08`) (sample boards)
3. Six rows, **row gap 8 pt** (vs 6 in medium — owner decision 3: rows further apart):
   - `example.com` · `Safari · 7 min`
   - `let greeting = "Hello"` · `Mac · now`
   - `Ocean · #008080` · `Mac · now`
   - `Synthetic landscape` · `Mac · now` (image tile `#52BCCF` + orange circle)
   - `Meeting notes` · `Portavoz · 2 min` (text tile, grey)
   - `Secret · masked` · `Terminal · 9:41 left` (lock tile, fill `rgba(255,59,48,.16)`, glyph `#C8231B`) — masked row with remaining-lifetime countdown
4. Bottom (pushed down, gap 6, two equal buttons, 30 high): `Save clipboard` (green, glyph) and `Open Gancho` (fill `rgba(29,29,31,.08)`, ink `#1D1D1F`, no glyph).

Fit check: 12 + ~14 header + 10 + 18 chips + 12 + 6 × 22 + 5 × 8 + 6 + 30 + 12 ≈ 286 ≤ 354 → the spare ≈ 68 pt sits above the buttons. Size stays 338 × 354.

### 2e. Lock Screen · Control Center — kept
Card padding 10, radius 12, white, border `rgba(0,0,0,.06)`: 60 pt circle `rgba(29,29,31,.85)` with white down-arrow 24; text 11.5: bold `Lock Screen · Control Center` / `“Save Clipboard” control (SaveClipboardControl) — shipped`. Context only (code uses `tray.and.arrow.down.fill`; code wins).

---

## Column 3 top — `GC-32` Live Activity · Ready to paste → GC-V4-17

Card (padding 14, radius 14, white, gap 8). Label: chip `GC-32` + `Live Activity · Ready to paste` + small `actions added`.

1. **Compact Dynamic Island (shipped, context):** pill 200 × 36, radius 18, black, padding 0 12, gap 8, 12 pt: GanchoMark tile 20, `Ready to paste`, cloud-check 12 `#7EE69A`. Caption: `Dynamic Island, compact — shipped (ClipLiveActivity)`.
2. **Expanded (v4):** 360 wide, radius 28, black, padding 12 × 16, gap 8, white text.
   - Row: GanchoMark tile 24; kind `link` (11, `#A1A1A6`, link glyph 11); right `Synced` (11, `#7EE69A`, cloud-check 11).
   - `Ready to paste` (10.5/700, `#A1A1A6`).
   - Preview `example.com/a/b?q=a&b` (14, lh 1.3) (sample).
   - Actions (gap 8, top +2): `Copy again` — flex 1, 32 high, radius 10, fill `#30D158`, ink `#04210D`, 13/700, doc glyph 13; `Open in Gancho` — flex 1, 32 high, radius 10, fill `rgba(255,255,255,.14)`, white, 13/600.
3. Caption → implementation note (below).

Lock-screen banner variant is not drawn separately.

## Column 3 bottom — `GC-30` Keyboard extension → GC-V4-19

Card as above. Label: chip `GC-30` + `Keyboard extension` + small `shipped · inserted mark added`.

Keyboard surface 360 wide, radius 14, bg `#D1D3D9`, padding 8, gap 6:
1. Chips (gap 5, height 22): `All` (selected green), `Favorites` (star 9), `Work` (`#2E70D1`), `Brand` (`#F08C08`).
2. Rows (40 high, padding 0 10, radius 9, gap 8, 12.5 pt; tile 36 scaled .72 ≈ 26):
   - **Inserted state:** bg `rgba(52,199,89,.14)`; `gancho.app/docs`; `Safari · 2 min` (10, `#5B5B61`); pill `inserted` (18 high, fill `#34C759`, ink `#0B2A14`, 10.5/600, check 9).
   - Normal (white): `hola@gancho.app` · `Mail · today`
   - Normal: `Calle Mayor 12, 28013 Madrid` · `Maps · yesterday` (all sample)
3. Key row (gap 5): five keys, flex 1 × 34, radius 7, white except Save (`#34C759`/`#0B2A14`). A11y labels as drawn: `Next keyboard` (globe), `Save clipboard` (down-arrow), `Show all` (list), `Size` (A glyph), `Delete` (×).

Only the `inserted` pill + row tint are new; the rest is drawn as "shipped" and is kept as the code has it (see Feasibility conflict note).

---

## Column 4 — `V4` Clip detail · text in image → GC-V4-18

Label: chip `V4` + `Clip detail · text in image` + small `iOS parity, new`.

Phone frame. Behind the sheet (context, from the iPhone board): nav circle 44 `Settings` (gear, `#1F7A3A`), nav group `Filters` / `Boards`; large title `Gancho` (34/800); rail chips `All clips` (selected) and `Favorites` (32 high, 14 pt).

Sheet from y = 60 (≈ 784 high), radius 28 top, grabber.
1. Meta row (padding 4 16 0, gap 6): pill `Image` (20 high, fill `rgba(255,159,10,.18)`, ink `#7A4B00`, 11/700, image glyph); chips 22 high 11 pt: `Preview` (dashed-square glyph), `Mac` (laptop glyph), `10 s` (clock glyph); right `Done` (17/600, `#1F7A3A`). (`Preview`, `Mac`, `10 s` are sample provenance.)
2. Title row (padding 8 16 4): `OCR sample` (20/800, sample) + edit button (wand glyph 14 `#1F7A3A`, a11y `Edit title`).
3. Image (margin 4 16 0): 170 high, radius 12, gradient 135° `#F7F7FA → #E9EAF0`, border 1 `rgba(0,0,0,.08)`. Four numbered regions (left 18; 22 high; radius 5; border 1.5; badge 16 pt circle at −8/−8, white 10/800):
   - `1` top 22, w 150: solid `#34C759`, fill `rgba(52,199,89,.14)`
   - `2` top 60, w 220: solid `#8E8E93`, fill `rgba(0,0,0,.03)`
   - `3` top 98, w 240: solid `#32ADE6`, fill `rgba(50,173,230,.12)` (link line)
   - `4` top 136, w 250: **dashed** `#FF3B30`, fill `rgba(255,59,48,.08)` (secret line)
4. `Copy image` button (padding 10 16 0): full width × 46, radius 14, `#34C759`/`#0B2A14`, 16/700, clipboard glyph 18.
5. Section header (padding-top 12): left `Text in image · 4 lines` (renders uppercase); right `on-device` (no uppercase, shield glyph 10, `#5B5B61`).
6. Group (margin 0 16, white, radius 12, separators `rgba(60,60,67,.14)`); rows min 44, padding 0 12, gap 8: number badge (18 high, mono 10/600, fill `rgba(29,29,31,.08)`), line text mono 13 ellipsis, trailing copy glyph 16 `#1F7A3A` (a11y `Copy line`):
   - `1` `Hola Gancho`
   - `2` `Texto de una imagen`
   - `3` `https://gancho.app/docs` + chip `link`
   - `4` (row tint `rgba(255,59,48,.06)`) `sk_live_••••••••••••••••` in `#C8231B` + chip `contains a secret` + text button `Reveal` (13/700 `#1F7A3A`) instead of the copy glyph. (all line text sample)
7. Footer (13, `#5B5B61`): `Read only when you open this clip; nothing is stored or indexed until you save. Line 4 stays out of Copy all until you reveal it.` (`Line 4` = the held-back line number.)
8. Actions (wrap, padding 8 16 0, gap 6, 30 high, 13 pt): `Copy all · 3` (fill `rgba(52,199,89,.14)`, ink `#1F7A3A`, doc glyph; count excludes the held-back line), `Save text as clip` (doc glyph), `Translate ▾` (globe glyph).

States drawn: one secret held back, unrevealed. Not drawn: recognizing, no text, unavailable, failed, revealed, copied feedback, translation result, region selected/tapped meaning of the green region `1` (not annotated).

---

## Implementation notes (not UI)

Verbatim annotations:
- Widgets: `Small: 2 rows + Save. Medium: 3 rows + sync age. Both exist (RecentClipsWidget, maxRows); masked clips show a lock and no preview, concealed copies never appear.`
- Tags: `Shipped · small`, `Shipped · medium` (×2), `v4 · large`; label smalls `preview · title · board · pin`, `large is new`, `actions added`, `shipped · inserted mark added`, `iOS parity, new`.
- Control: `“Save Clipboard” control (SaveClipboardControl) — shipped`
- Live Activity: `Dynamic Island, compact — shipped (ClipLiveActivity)` and `Shipped: kind, lock for sensitive, sync badge, auto-end after the dismiss window. v4 adds the two actions as Button(intent:) — Copy again puts the clip back on the pasteboard, Open deep-links to it — and ends on the next copy.`
- Keyboard: `Shipped: board chips, Full Access explainer, five 44 pt keys. v4 adds the “inserted” mark on the row you tapped so a long message shows what already went in.`

Numbered pins (bottom row, 4 columns):
1. `Share sheet (GC-29). Today ShareViewController saves on viewDidAppear and dismisses with a success or error haptic — honest, but blind. v4 shows what will be saved, lets you title it, pick a board and pin, and names the privacy boundary under the button. Shortcuts and the Action Button keep the instant path; a “Save instantly from the share sheet” switch in Settings → Capture on iPhone restores today's behaviour.`
2. `Widgets (GC-31). Small and medium are shipped (RecentClipsWidget: 2 / 3 rows, Save button, deep links, masked rule) and the Lock Screen control exists. v4 adds the large family: six rows, board chips that scope the list, sync age, Save and Open. Secrets keep the lock; concealed copies never reach a widget.`
3. `Live Activity (GC-32) and keyboard (GC-30). Both shipped; v4 only adds the two Live Activity actions and the keyboard's “inserted” mark. The keyboard keeps its board chips, the Full Access explainer and the five keys.`
4. `Text in image on iPhone. The Mac peek reads images on demand (ManualImageTextService, ImageTextReading live in the shared packages); iOS has no screen for it yet — the “pending iOS parity” the OCR design left open. v4 gives the iPhone detail the same section: numbered regions, per-line copy, secret hold-back, Copy all · Save · Translate, nothing stored until you save.`

---

## Coverage

| Card / frame / pin | Covered by |
|---|---|
| Board header (IDs, title, subtitle, meta) | context only |
| Col 1 share sheet (host page, sheet, preview, Title, Add to board, chips, Pin it, Save, footer) | GC-V4-15 (legacy GC-29) |
| Col 2a small widget | kept, no change (GC-31 shipped); header mark → owner decision 2 (GC-V7-1) |
| Col 2b widget explanatory text | context only |
| Col 2c medium widget | kept, no change in scope — but board-vs-code mismatch (sync age, source·age meta, full-width Save) → open question |
| Col 2d large widget | GC-V4-16 (legacy GC-31) + owner decision 3 |
| Col 2e Lock Screen · Control Center | kept, no change (`SaveClipboardControl`); GC-V6-8 later changes the control (other board) |
| Col 3 Live Activity compact | kept, no change |
| Col 3 Live Activity expanded + actions | GC-V4-17 (legacy GC-32) |
| Col 3 keyboard chips, rows, keys | kept, no change (legacy GC-30 shipped) |
| Col 3 keyboard `inserted` pill + row tint | GC-V4-19 |
| Col 4 detail chrome (nav, title, meta row, image, Copy image) | context only (iPhone detail board) |
| Col 4 Text in image section (regions, lines, footer, actions) | GC-V4-18 |
| Pin 1 | GC-V4-15 |
| Pin 2 | GC-V4-16 |
| Pin 3 | GC-V4-17, GC-V4-19 |
| Pin 4 | GC-V4-18 |

---

## Feasibility

Extension facts that bind every item below:
- **Data crosses process boundaries only through the App Group** `group.com.johnny4young.gancho` (`SharedInbox.appGroupID`, `Packages/GanchoKit/Sources/ClipboardCore/SharedInbox.swift:19`) plus the shared keychain group `com.johnny4young.gancho.keys`. The widget and keyboard open the encrypted store in the App Group via `IntentStore.open()` (`Apps/GanchoShared/SharedCaptureIntent.swift:9-16`); the share extension never opens the store and only deposits sealed files into `SharedInbox` (drained by `IOSAppModel.drainSharedInbox`, `Apps/GanchoiOS/IOSAppModel.swift:1061`). Preferences shared with extensions live in `SharedCapture.preferences` (App Group `UserDefaults`, `Apps/GanchoShared/SharedCapture.swift:13`).
- **Memory/time limits** (Apple does not publish exact numbers; measure on device with Instruments): share extensions have a tighter memory ceiling than apps and can be killed when backgrounded; keyboards run under a tight ceiling (already respected: 60-row page, 24-thumbnail FIFO, `KeyboardModel.swift:35-38, 83-88`); widget timeline providers get a few seconds and a small memory budget and the system caches timelines; Live Activity content must stay small (ActivityKit payload limit ~4 KB) and auto-dismisses (`visibleFor` 3 min, `ClipActivityController.swift:17`). No model loads in extensions (`ShareViewController.swift:52-55`).
- **Privacy:** secrets never appear in widgets or on the lock screen — masking happens when entries are built (`WidgetClips.entries`, `Packages/GanchoKit/Sources/GanchoKit/WidgetClips.swift:75-89`; Live Activity `preview` already masked, `ClipActivityController.swift:28-33`). Concealed/Transient/AutoGenerated pasteboard types are never stored, so they can never reach a widget. No clipboard content in logs.
- **Localization:** new strings go to `Apps/GanchoWidgets/Localizable.xcstrings`, `Apps/GanchoKeyboard/Localizable.xcstrings`, `Apps/GanchoiOS/Localizable.xcstrings`. `GanchoShare` has **no** String Catalog today and is not in `LocalizationTests.catalogPaths` (`Packages/GanchoKit/Tests/GanchoKitTests/LocalizationTests.swift:15-21`) → adding one (EN + ES) and the path is new work.

### GC-V4-15 — Share sheet shows what will be saved (UI + feature)
- **Changes:** replace the auto-save in `viewDidAppear` with a SwiftUI sheet hosted by `ShareViewController`: preview card, Title field, `Add to board` chips (+ `New board`), `Pin it` switch, `Save to Gancho` button, privacy footer, `Cancel`. Header spacing exactly 16 pt above / 8 pt below `Add to board` (owner decision 3).
- **Code:** `Apps/GanchoShare/ShareViewController.swift:15-31` (auto-save + haptic today), `:42-73` (deposit), `:77-101` (extraction); `SharedInbox.PreparedCapture` (`SharedInbox.swift:63-66`, only `capture` + `kind`); drain `IOSAppModel.swift:1061-1110`; settings `Apps/GanchoiOS/IOSSettingsView.swift:51-57` (`Capture on iPhone` is explanatory text only); target `project.yml:459-501`.
- **Exists:** extraction (image > URL > text), tier-0 classification in-extension, sealed deposit, success/error haptic, App Group + keychain entitlements, `Save to Gancho` display name, board model + colours (`BoardColors`), keyboard's board-chip pattern (`KeyboardView.swift:59-102`).
- **New:** the sheet UI; `PreparedCapture` fields for `title`, `boardIDs`, `newBoardName`, `isPinned` (Codable, optional for old files); drain applying them through the app's normal board-membership/pin paths (membership changes must mark `needsUpload` for sync); a board list readable by the extension (read-only `IntentStore` like the keyboard, or an App Group snapshot written by the app); the `Save instantly from the share sheet` switch in Settings → Capture on iPhone stored in `SharedCapture.preferences` (when on, keep today's path); `GanchoShare` String Catalog + LocalizationTests path; a11y ids (e.g. `share-sheet`, `share-title-field`, `share-board-chip`, `share-pin-toggle`, `share-save-button`); the switch's a11y label should be `Pin it`, not the drawn `Toggle`.
- **Deps:** iPhone Settings "Capture on iPhone" rework on `V4_Gancho_iPhoneFlows` (five paths with state); GC-V5-2 (accent-ink `#1F7A3A` for `Cancel` / `New board`).
- **Verify:** unit tests for `PreparedCapture` round-trip (old files still decode) and drain applying board/pin/title; UI test via a host app share invocation is hard → snapshot test of the SwiftUI sheet compared to the board (light), checking the 16/8 header spacing; manual device test from Safari, Photos, Notes; memory gauge in Xcode during an image share.
- **BLOCKED:**
  1. "written on-device" title: is it the title the sharing app provides (`NSExtensionItem.attributedContentText`/title — no model, no network) or a Foundation Models title? A model load in the share extension risks the memory ceiling, and fetching page metadata would break "Nothing is sent anywhere else".
  2. Board list source: may the share extension open the store read-only (keyboard/widget do), against its own doc comment "must never own the store"? Or should the app publish a board snapshot to the App Group?
  3. Footer copy when sync is off or no board is selected (only the synced-board variant is drawn).
  4. Default of the `Save instantly` switch (board implies off = new sheet).
  5. The drawn `Title` header has 12 pt above / 0 below while `Add to board` is 16/8 — apply the iOS grouped-header spacing to `Title` too?

### GC-V4-16 — Large widget with board chips and sync age (UI + feature)
- **Changes:** add `.systemLarge` to `RecentClipsWidget` with a large layout: header mark + `Gancho` + sync age; board chips (`All` + boards) with 10 pt above / 12 pt below; six rows, 8 pt apart, each with source app · age; masked row shows a lock tile and remaining lifetime; `Save clipboard` + `Open Gancho` at the bottom. Widget size unchanged.
- **Code:** `Apps/GanchoWidgets/RecentClipsWidget.swift:16` (families), `:47-54` (loads 3), `:63` (`maxRows`), `:66-78` (spacing 8 / rows 5), `:87-106` (header: `paperclip` at `:89` → brand mark per owner decision 2; circular save button), `:108-125` (row: kind glyph + text only), `:145` (`gancho://` fallback); `WidgetClipEntry` (`WidgetClips.swift:34-60`, has `sourceAppBundleID`, `createdAt`, no `expiresAt`); `KeyboardClips.query(boardID:)` (`Packages/GanchoKit/Sources/GanchoKit/KeyboardClips.swift`) for board-scoped reads; `SaveClipboardIntent` (`SharedCaptureIntent.swift:22-31`); deep links `gancho://clip/<id>` (`WidgetClips.swift:63`, `IOSAppModel.swift:375-379`).
- **Exists:** small/medium families, masking rule, Save intent, row deep links, App Group store read, board-scoped search, board colours, `GanchoMark` image set in the widget catalog.
- **New:** large family + layout; fetch 6 rows (and board-scoped); chips as interactive `Button(intent:)` writing the selected board id to App Group defaults + reloading the timeline (or a configurable `AppIntentConfiguration`); sync age — the widget has no sync access (CloudKit is confined to GanchoSync), so the app must write a last-synced date to the App Group; `expiresAt` on `WidgetClipEntry` (optional, decodes old caches) for `9:41 left` via `Text(timerInterval:)`; source-app name via `SourceApp.fallbackName` (keyboard does this); `Open Gancho` link; template brand-mark asset for the header (GC-V7-1); new strings EN+ES (`Gancho`, `synced %@`, `Open Gancho`, `Save clipboard`, `%@ left`, `All`).
- **Deps:** GC-V7-1 / owner decision 2 (brand mark replaces `paperclip` at `RecentClipsWidget.swift:89`); GC-V6-8 (Up next / capture state also on iPhone surfaces).
- **Verify:** unit tests for entry building (6-row limit, masked row keeps metadata but never content, `expiresAt` passthrough); WidgetKit preview/snapshot of `.systemLarge` against the board, measuring 10 / 12 / 8 pt; device check that a sensitive clip shows the lock on the Lock Screen / StandBy.
- **BLOCKED:**
  1. Which boards get chips (Favorites? first N user boards? user-chosen)? Only `All`, `Work`, `Brand` are drawn.
  2. Masked row text: the board draws `Secret · masked`; code uses `•••` (`ClipSafePresentation.masked`). Which one?
  3. The board labels small/medium "Shipped" with a full-width `Save clipboard` button, `synced 2 min` and `Source · age` meta, and small's header `Recent`; code has a header circle save button, `Recent clips`, no sync age, no meta. Code wins for "shipped" — should small/medium be restyled to match (not in the catalog item)?
  4. Drawn row tiles (36 pt × 0.9) overflow the 22 pt rows; confirm the tile size (≤ 20 pt) for implementation.

### GC-V4-17 — Live Activity actions: Copy again and Open (UI + feature)
- **Changes:** expanded Dynamic Island gains `Copy again` (puts the clip back on the pasteboard) and `Open in Gancho` (deep link to the clip) as `Button(intent:)`; the activity ends on the next copy.
- **Code:** `Apps/GanchoWidgets/ClipLiveActivity.swift:17-41` (expanded regions), `:42-49` (compact/minimal), `:50` (`widgetURL` = `gancho://`, not the clip), `:57-77` (lock-screen banner); `ClipActivityAttributes.ContentState` (`Packages/GanchoKit/Sources/GanchoKit/ClipActivity.swift:10-26`, no clip id); `ClipActivityController.swift:24-58`; callers `IOSAppModel.swift:702, 1243`.
- **Exists:** activity, masking, sync badge, auto-dismiss after 3 min, replace-on-new-capture (`endAll` before `request`), GanchoMark.
- **New:** `clipID` in `ContentState`; a `LiveActivityIntent` "Copy again" (compiled into app + widget targets, performed in the app process, reads content through `ClipSafeDelivery` and writes `UIPasteboard`); Open via `Link`/`widgetURL` to `gancho://clip/<id>`; actions also on the lock-screen banner (not drawn); kind label (`kindSymbolName` is carried but never rendered today); "ends on the next copy"; strings EN+ES (`Copy again`, `Open in Gancho`).
- **Deps:** GC-V6-8 (Live Activity carries the paste-stack position — same view, plan the layout together).
- **Verify:** unit test for the intent's eligibility (missing/expired/sensitive clip → no copy); device test from the Dynamic Island and the Lock Screen; snapshot of the expanded view.
- **BLOCKED:**
  1. Copy again for a sensitive clip from the Lock Screen: hide it, or require unlock (`authenticationPolicy = .requiresAuthentication`)?
  2. "Ends on the next copy": iOS cannot see copies in other apps in the background (`ClipActivityController.swift:9-11`). Is "next capture/copy inside Gancho, or a changed `UIPasteboard.changeCount` at next foreground" acceptable?
  3. The board draws the text `Synced` and a `link` kind label; code keeps the sync badge icon-only on purpose (no per-state strings). Text labels or icons?
  4. The compact pill draws `Ready to paste` text between leading and trailing; compact regions cannot show centre text. Keep the shipped compact layout?

### GC-V4-18 — Text in image on iPhone (UI + feature)
- **Changes:** the iPhone image-clip detail gets a "Text in image" section: numbered regions over the image, per-line copy, per-line secret hold-back with `Reveal`, `Copy all · N` (excluding held-back lines), `Save text as clip`, `Translate ▾`, `on-device` badge and the transient-data footer. Recognition starts when the clip is opened.
- **Code (reuse):** `ManualImageTextService` (`Packages/GanchoKit/Sources/GanchoAppCore/ManualImageTextService.swift:32-53`), `ImageTextReading` + permission predicate (`Packages/GanchoKit/Sources/GanchoKit/ImageTextReading.swift:11-66`), `ManualOCRSession` (`Packages/GanchoKit/Sources/GanchoAppCore/ManualOCRSession.swift`), `ImageTextExtractor.recognizeLines` with top-left boxes (`Packages/GanchoKit/Sources/GanchoAI/ImageTextExtractor.swift:38-66`, Vision, works on iOS), entities/translation (`GanchoAI/ImageTextEntities.swift`, `TranslationCapabilities.swift`). Mac reference UI: `Apps/GanchoMac/PeekImageText.swift` (regions `:49-108`, section `:115-311`, save `:399-402`), `AppModel+ManualOCR.swift:36-60, 192-205`. iOS target: `Apps/GanchoiOS/ClipDetailView.swift:287-306` (image content), iOS has existing Translate plumbing for text clips (`ClipDetailView.swift:460-498`).
- **Exists:** the whole recognition/permission/session stack in shared packages; on-device translation; save-as-clip via ingestion.
- **New:** iOS views (regions overlay, line list, actions) and an `IOSAppModel` glue like `AppModel+ManualOCR` (`UIPasteboard.changeCount` as clipboard revision); **per-line** secret detection (today `ManualOCRSession.isSensitive` is one flag for the whole result, `:28-29, 85-87`); a no-auto-copy mode (the Mac session copies non-sensitive results automatically, `:86-89` — the iPhone board copies only on tap); Translate while one line is held back (Mac hides Translate and entity chips for any secret, `PeekImageText.swift:405-408`); per-line `link` chip; a11y ids (e.g. `detail-ocr`, `detail-ocr-line-<n>`, `detail-ocr-region-<n>`, `detail-ocr-copy-all`, `detail-ocr-save`, `detail-ocr-translate`, `detail-ocr-reveal`); strings EN+ES (`Text in image · %lld lines`, `on-device`, `Copy all · %lld`, `Save text as clip`, `Translate`, `contains a secret`, `link`, `Reveal`, `Copy image`, footer, plus Mac's empty/failed states).
- **Deps:** `V4_Gancho_iPhone` detail redesign (meta row, title, `Copy image` chrome); B-GC-02 / GC-V5-2 accent-ink.
- **Verify:** unit tests on per-line sensitivity and the `Copy all` count/exclusion; session test that no pasteboard write happens without a tap; UI test with the existing OCR seed (`-seed-…` image clip) asserting 4 lines, line 4 masked, `Copy all · 3`; snapshot against the board.
- **BLOCKED:**
  1. "Nothing is stored or indexed until you save" vs automatic Pro OCR enrichment, which already stores image text (`imageTextInput` returns `.cached(text)` with no regions, `ImageTextReading.swift:45-48`). With enrichment on, the footer is untrue and numbered regions cannot be drawn. Should iOS always re-run recognition for regions, and what should the footer say then?
  2. May Translate run while a line is held back (translating only non-secret lines)? The Mac contract forbids sending a flagged text anywhere.
  3. Auto-start on open vs explicit button (pin 4 says "on demand"; the footer says "Read only when you open this clip").

### GC-V4-19 — Keyboard marks the inserted row (UI + feature)
- **Changes:** after a tap inserts a clip, that row gets a green tint (`rgba(52,199,89,.14)`) and an `inserted` pill until the text field changes.
- **Code:** `Apps/GanchoKeyboard/KeyboardModel.swift:154-178` (`insert`), `KeyboardView.swift:265-287` (row), `:168-211` (compact strip), `KeyboardViewController.swift:8-55` (no `textDidChange` / `documentIdentifier` handling today).
- **Exists:** rows, tap-to-insert, `flashNote`, board chips, Full Access prompt.
- **New:** `insertedIDs` (or one id) on `KeyboardModel`, set only after `onInsert` succeeds; clear when `textDocumentProxy.documentIdentifier` changes (`textDidChange` / `selectionDidChange` override); pill + tint in both expanded and compact layouts; string `inserted` EN+ES; a11y value "Inserted" on the row.
- **Deps:** GC-V6-8 (top row "Up next" and secret countdowns in the keyboard).
- **Verify:** unit test on the model (mark set on insert, cleared on document change, not set for image → pasteboard path); UI test in the iOS keyboard host if available, else manual on device; snapshot against the board.
- **BLOCKED:**
  1. One marked row or every row inserted into the current field? (Catalog: "the tapped row"; pin: "shows what already went in".)
  2. Image clips go to the pasteboard, not into the field — mark them `inserted`, `copied`, or not at all?
  3. The board draws a bottom row of five 34 pt keys (`Next keyboard`, `Save clipboard`, `Show all`, `Size`, `Delete`) under the list and calls them "shipped"; code has a top control bar (globe, search, save, size, delete, 42 × 36) plus a trailing chevron. Code wins for "shipped"; confirm no layout change is intended.

### GC-V6-8 overlap (not drawn here)
GC-V6-8 (`V4_Gancho_Novel2`) changes three surfaces on this board: the keyboard top row (Up next + masked secrets with countdown) — same rows as GC-V4-19; the Control Center control (show/toggle capture state) — replaces the "kept" `SaveClipboardControl` card here; and the Live Activity (paste-stack position) — same expanded view as GC-V4-17. Plan these together so the Live Activity and keyboard layouts are designed once.

---

## Owner notes

- Pick notes: GC-V4-15, -16, -17, -18, -19 are all `pick` with no note; GC-V6-8 `pick`, no note.
- Owner decision 3 (applied, and drawn on this board): share sheet `Add to board` header **16 pt above, 8 pt below** (iOS grouped-list header) — drawn exactly; large widget board chips with air above (10 pt from the header) and below (12 pt to the list), rows further apart (8 pt vs 6 pt in medium), widget size unchanged (338 × 354).
- Owner decision 2: `paperclip` at `RecentClipsWidget.swift:89` becomes the brand mark (the board's widget headers already draw the template mark).
- Owner comment threads on this board (resolved): large widget chips needed air above/below and rows needed more space, size unchanged; share sheet header 16/8.
- General owner rules: compare with current UI and only propose what beats it; code wins over older boards; each piece of data once per screen; annotations are not UI.
