# V4_Gancho_iPhoneFlows — spec

- **Board:** `V4_Gancho_iPhoneFlows.dc.html` (HTML `<title>`: `Gancho iPhone flows v4`)
- **Canvas:** 2240 × 1150 pt, radius 12, background `#ECEDF0`, padding 24 (top/bottom) × 28 (sides), vertical gap 14.
- **Shows:** the current iPhone clip detail (from `ClipDetailView`) next to its v4 evolution, then the v4 Boards, Settings and Privacy Center sheets opened from the iPhone home. Five 390 × 844 phones in one row.
- **Realises:** GC-27 (detail), GC-28 (boards sheet), GC-V4-12 (Settings, labelled `V4` on the board), GC-21 (iPhone half of the Privacy Center Verify group; the Mac half lives on `V4_Gancho_Settings`).
- **Related Current boards:** `GanchoPhone_Current` (home screen only: rail `✓ All clips` / `Favorites` / `+ New board…`, `Sensed, not read` / `Pasteboard is empty`, `Today`, row menu `Copy` `Pin` `Delete`, `Paste`). The first phone on this board is itself a redraw of the current detail.
- **Code target:** `Apps/GanchoiOS` (plus shared `Packages/GanchoKit`).

Annotations (`v4 · …` labels, ID chips, numbered notes) are not UI; they are recorded under "Implementation notes".

---

## 0. Board header (context only)

Row, gap 12, vertically centred:
- ID chips (22 h, padding 0 9, radius 7, 11 pt weight 800, mono, tracking .04em): `GC-27` green (`#34C759` fill, `#0B2A14` text), `GC-28` dark (`#1D1D1F` / `#FFFFFF`), `GC-21` dark.
- Title `iPhone screens · detail, boards, settings, privacy` — 22 pt / 800 / tracking −.02em.
- Subtitle (13 pt, `#5B5B61`, max 860 wide): `The current detail (left, from ClipDetailView) beside its v4 evolution, then the sheets the home opens. The system has been evolving: v4 keeps each sheet's structure and tightens what the eye lands on first.`
- Right-aligned: `Gancho · iOS 26 · v4 · 390 × 844`.

## Shared phone chrome (all five phones)

Drawn identically behind every sheet; it is today's home and is **not** changed by this board.
- Phone: 390 × 844, radius 44, background `#F2F2F7`, border 1 px `rgba(29,29,31,.14)`, shadow `0 20 50 rgba(0,0,0,.18)`. Light mode only (no dark variant drawn).
- Status bar: 54 h, padding 0 30 4 34, 15 pt / 700: `9:41`, right `●●●●` + cloud glyph 13 + battery.
- Nav row (padding 2 16 0): left circular button 44 × 44, fill `rgba(255,255,255,.82)`, icon `#1F7A3A` gear 20, aria-label `Settings`; right capsule group 44 h radius 22 with two 44 × 36 buttons, aria-labels `Filters`, `Boards`.
- Large title `Gancho` 34 pt / 800, padding 10 16 8.
- Rail (padding 0 16, gap 8): chips 32 h, padding 0 12, radius 999, 14 pt / 500, fill `rgba(120,120,128,.16)`; `All clips` (checkmark 12) selected → `#34C759` fill, `#0B2A14` text, weight 600; `Favorites` (star 12) unselected.
- Home indicator 134 × 5, radius 3, `#1D1D1F` at 85%, 8 from bottom.

Shared sheet tokens:
- Sheet: background `#F2F2F7`, top corners 28, shadow `0 -10 40 rgba(0,0,0,.25)`; grabber 36 × 5 radius 3 `#C7C7CC`, 8 from top.
- Sheet title bar: padding 10 16 8; title 17 pt / 700 left; `Done` right, 17 pt / 600, `#1F7A3A`.
- List: padding 0 16, gap 8, padding-top 4.
- Group (`grp`): white, radius 12, 1 px separators `rgba(60,60,67,.14)`.
- Group header (`gh`): 13 pt, `#5B5B61`, UPPERCASE, tracking .02em, padding 0 16; a right-side element when drawn is not uppercased.
- Row (`ios-row`): min-height 44, padding 10 16, gap 12, 16 pt; leading slot 28 wide, glyph 20, `#1F7A3A`; subtitle 13 pt `#5B5B61`, line-height 1.3; chevron 14 `#C7C7CC`.
- Group footer: 13 pt `#5B5B61`, line-height 1.35, padding 6 16 0.
- Switch: 51 × 31; on `#34C759`, off `#E9E9EB`; knob 27.
- Colour notes: `#34C759` = brand green / `GanchoTokens.Palette.accent` default on iOS; `#1F7A3A` = darker accent ink for text on light surfaces (the accent-ink token proposed by GC-V5-2 / B-GC-02); `#FF9F0A` = warning / Favorites hue; `#FF3B30` = danger; `#C8231B` = destructive text.

---

## 1. `NOW` · `Current · detail peek` (`large detent`) — context only

Label row: chip `NOW` (dark), `Current · detail peek`, small `large detent`.

Sheet top at 60 pt. Mirrors today's `ClipDetailView` (verified against code):
1. Title bar: `Link` · `Done`.
2. Header `Title`; group row: `Untitled` (`#5B5B61`) · button `Edit` (16 pt, `#1F7A3A`, wand glyph 14; code uses SF `pencil`).
3. Action row (3 equal columns, gap 10, padding 4 16 8): box 46 h radius 10; labels 12 pt `#5B5B61`, gap 6. `Copy` (primary: `#34C759` box, `#0B2A14` glyph) · `Share` · `Pin` (neutral `rgba(120,120,128,.16)`, glyph `#1D1D1F` 20).
4. Group: `https://www.example.com:8443/a%2Fb?q=a%26b#section-2` (sample), 16 pt, line-height 1.35, padding 12 16, break-all.
5. Chip row (26 h, padding 0 12, 12 pt / 500, `#3A3A3F`): `Link` (link 11) · `Safari` (app glyph 11) · `Mac` (laptop 11).
6. Group row: sparkles 16 `#1F7A3A` · `Add to Work?` · `Add` (`#1F7A3A`) · dismiss ⊗ 20 `#C7C7CC`.
7. Header `Boards`; group row `+ Add to board` (`#1F7A3A`).
8. Group row `Save as snippet` (text glyph 16, `#1F7A3A`).
9. Header `Smart Actions` + right `on-device` (`#8E8E93`, not uppercased); group rows: `Parse URL` (`#1F7A3A`), `URL-decode` (`#1F7A3A`), `Transform` (glyph 16) + chevron, `Summarize` (sparkles 16), `Fix grammar` (sparkles 16).

---

## 2. `GC-27` · `v4 · detail peek` (`Copy is the primary`) — realises GC-27

Label row: chip `GC-27` (green), `v4 · detail peek`, small `Copy is the primary`. Sheet top at 60 pt (large detent). Top to bottom:

1. **Provenance row + Done** (padding 4 16 0, gap 6, wraps):
   - Kind pill: 20 h, padding 0 8, radius 999, 11 pt / 700, gap 4; fill `rgba(50,173,230,.16)` (URL kind tint `#32ADE6` at 16%), text `#0B5C80`; link glyph 11; text `Link`.
   - Chips 22 h, 11 pt (`mch`, `#3A3A3F` on `rgba(120,120,128,.16)`): `Safari` (app glyph 11) · `Mac` (laptop 11) · `7 min` (clock 11) — all (sample).
   - Spacer, then `Done` 17 pt / 600 `#1F7A3A`. No separate sheet title bar; no `Link` nav title.
2. **Title row** (padding 8 16 4, gap 8): `Synthetic link` (sample) 20 pt / 800, tracking −.01em; icon button (wand/pencil glyph 14, `#1F7A3A`), aria-label `Edit title`. Tap to edit in place.
3. **Link hero card** (margin 4 16 0, padding 12 14, radius 14, white, border 1 px `rgba(0,0,0,.06)`, clipped): 4 pt left bar `#32ADE6` full height.
   - Host `example.com` 22 pt / 800, tracking −.01em.
   - URL `https://www.example.com:8443/a%2Fb?q=a%26b#section-2` — mono 12 pt, `#5B5B61`, line-height 1.45, break-all, 4 below host.
   - Insight chips (8 below, gap 4; 22 h, 11 pt): `decoded · /a/b?q=a&b` · `https`.
4. **Copy** (padding 10 16 0): full-width button 50 h, radius 14, `#34C759` fill, `#0B2A14` text 17 pt / 700, gap 8, clipboard glyph 18, label `Copy`.
5. **Secondary action row** (4 equal columns, gap 10, padding 8 16 8): neutral boxes 46 h radius 10, glyph 20 `#1D1D1F`, labels 12 pt `#5B5B61`: `Share` (share) · `Pin` (pin) · `Board` (tray stack) · `Snippet` (text glyph).
6. **Header** (padding-top 4): `Smart actions` (uppercased by style) + right `on-device` with shield glyph 10, `#5B5B61`, not uppercased.
7. **Smart-action chip group** (wrap, padding 6 16 0, gap 6; chips 30 h, 13 pt, padding 0 12, radius 999):
   - Neutral (`rgba(120,120,128,.16)`, `#3A3A3F`): `Parse URL` · `Markdown link` · `URL-decode` · `Transform ▾`.
   - Intelligence (fill `rgba(52,199,89,.14)`, text + sparkles 11 `#1F7A3A`): `Summarize` · `Fix grammar` · `Redact PII` · `Translate ▾`.
8. **Header** `Boards` (padding-top 10).
9. **Board chips** (wrap, padding 6 16 0, gap 6; 30 h, 13 pt):
   - Member chip `Work` with 10 × 10 radius 3 swatch `#2E70D1` (`BoardIdentityColor.blue`) (sample).
   - Button chip `+ Add` (plus 12, text `#1F7A3A`).
   - Suggestion chip: fill `rgba(52,199,89,.12)`, text `#1F7A3A`, sparkles 11, `Add to Brand? ` + bold `Add` (sample board name).

States drawn: only the link clip at the large detent. Not drawn (kept per pin 1): masked clip with Reveal/Hide, image tap-to-zoom cover, medium detent, editing title, result box, thinking state, Pinned state.

## 3. `GC-28` · `v4 · Boards` (`identity · counts · limit`) — realises GC-28

Label row: chip `GC-28` (green), `v4 · Boards`, small `identity · counts · limit`. Sheet top at 104 pt (shorter sheet than the others).

1. Title bar `Boards` · `Done`.
2. Group (rows min-height 52; leading 28-wide slot; trailing count `#5B5B61`, tabular digits):
   - tray glyph 18 `#5B5B61` · `All clips` · `128` (sample).
   - star glyph 18 `#FF9F0A` · `Favorites` · `9` (sample).
3. Header `Boards` with right-side `2 of 3 · Free` (not uppercased; sample count, limit from code — see Feasibility).
4. Group:
   - Swatch 14 × 14 radius 3 `#2E70D1` · `Work` / sub `Synced · Mac + iPhone` · `12` (sample).
   - Row shown mid-swipe (content offset −168 pt) revealing three 56-wide actions, left→right: palette glyph on `#5E5CE6` (indigo, Appearance), wand/pencil glyph on `#007AFF` (blue, Rename), trash glyph on `#FF3B30` (Delete). White glyphs 18. Row content: swatch `#F08C08` (`BoardIdentityColor.orange`) · `Brand` / sub `Synced` · `9` (sample).
   - Row min-height 48, `#1F7A3A`: `+ New board`.
5. Footer: `Tap a board to scope the history. Swipe for appearance, rename and delete; the Favorites board is built in. A third board is the last one on Free — Gancho Pro unlocks more.`
6. Header `Snippets` (padding-top 10).
7. Group (rows min-height 52, text glyph 18 `#5B5B61`, chevron):
   - `;sig` / sub `Email signature` (sample).
   - `;addr` / sub `Office address` (sample).
   Primary line is the keyword, subtitle is the snippet title.

## 4. `V4` · `v4 · Settings` (`status subtitles · capture paths`) — realises GC-V4-12

Label row: chip `V4` (green), `v4 · Settings`, small `status subtitles · capture paths`. Sheet top at 60 pt.

1. Title bar `Settings` · `Done`.
2. Group (chevron on each):
   - star 20 `#FF9F0A` · `Gancho Pro` / `Free · 2 of 3 boards, 2 of 20 snippets`.
   - sparkles 20 `#1F7A3A` · `Intelligence` / `Titles, meaning, screenshots on · Smart paste off`.
   - lock 20 `#1F7A3A` · `Privacy Center` / `0 analytics requests · 1 secret masked`.
   (Counts and on/off states are sample; the 3 and 20 are code limits.)
3. Header `Language`; group row (empty leading slot): `Language` · value `System` `#5B5B61` · chevron.
4. Header `Capture on iPhone`; group of five:
   - clipboard 20 · `Paste button` / `Saves what is on the clipboard — iOS asks nothing, shows no banner` (no trailing).
   - share 20 · `Share sheet` / `Send text, links or images from any app` · trailing `On` (13 pt `#5B5B61`).
   - bolt 20 · `Shortcuts & Action Button` / `Example Shortcuts gallery` · chevron.
   - keyboard 20 · `Gancho keyboard` / `Settings → General → Keyboards → Add` · tag `Not added` (20 h, radius 999, 11 pt / 700, fill `rgba(255,159,10,.18)`, text `#7A4B00`) · chevron.
   - grid 20 · `Widget` / `Recent clips + Save, from the Home Screen` (no trailing).
5. Footer: `Gancho never reads your pasteboard in the background. Capture happens only when you act.`
6. Header `Your history` (padding-top 8); group:
   - `Show snippets and pins in Spotlight` · switch on (role switch, aria-checked true).
   - arrow-down 20 `#1F7A3A` · `Back up history…`.
   - arrow-up 20 `#1F7A3A` · `Restore from backup…`.
7. Footer: `Backups are .ganchoarchive files on your device — never uploaded.`

## 5. `GC-21` · `v4 · Privacy Center` (`verify group first`) — realises GC-21 (iPhone)

Label row: chip `GC-21` (green), `v4 · Privacy Center`, small `verify group first`. Sheet top at 60 pt.

1. Title bar `Privacy Center` · `Done`.
2. Hero card: padding 14 16, radius 14, gradient 160° `#5FD57F` → `#34C759`, gap 4.
   - Row: shield glyph 26 (white) left; `0` right, 34 pt / 800 (white).
   - `Clipboard-content analytics requests` 16 pt / 700, `#04210D`.
   - `Optional diagnostics contain anonymous counts and broad buckets only.` 12 pt, `#04210D` at 85%.
3. Header `Verify, don’t trust` (curly apostrophe); group:
   - lock 20 `#1F7A3A` · `Encrypted at rest` / `SQLCipher · key in your Keychain` · trailing text button `Verify` 14 pt / 600 `#1F7A3A`.
   - cloud 20 `#1F7A3A` · `iCloud sync` / `Private database · Mac + iPhone · 2 min ago` (sample) · chevron.
   - eye-slash 20 `#1F7A3A` · `Secrets masked now` · `1` (`#5B5B61`, sample).
4. Header `Private activity receipt`; group (rows min-height 44, 15 pt, values `#5B5B61` tabular, all sample): `Items reused` `41` · `Copies captured` `128` · `Captures skipped` `12` · `Protected copies skipped` `7` · `Sensitive items self-expired` `3` · `Clear activity receipt` (`#C8231B`).
5. Footer: `Stored only on this iPhone for a rolling 13 months. Per-app totals never sync, export, or enter diagnostics.`
6. Header `Optional diagnostics` (padding-top 8); row `Share anonymous usage diagnostics` · switch off.
7. Header `Recent issues` (padding-top 8); row `No issues recorded.`

Not drawn but kept per pin 4: per-app activity table, the unreadable-clips section (only when count > 0).

---

## Implementation notes (not UI)

Label strips: `NOW Current · detail peek large detent`, `GC-27 v4 · detail peek Copy is the primary`, `GC-28 v4 · Boards identity · counts · limit`, `V4 v4 · Settings status subtitles · capture paths`, `GC-21 v4 · Privacy Center verify group first`.

Numbered notes (verbatim):
1. **Detail (GC-27):** “provenance pills replace the Title section and the chips row; the title is tapped to edit in place (`ClipTitleEditor` keeps draft/cancel/save); the link hero mirrors the Mac peek; Copy is the one full-width primary because iOS cannot paste into another app; Share · Pin · Board · Snippet are one row; dev actions, Transform, Smart paste and Translate become one chip group with the same identifiers (`smart-paste-*-action`, `transform-menu`); masked clips keep Reveal/Hide; images keep the tap-to-zoom cover.”
2. **Boards (GC-28):** “identity colour, live counts and sync state per row; Free limit shown as “2 of 3” before it is hit (the Mac Library already does); swipe keeps appearance · rename · delete; snippets listed with their keywords, as the keyboard extension already shows them.”
3. **Settings:** “every row the app has today stays; the three top rows gain a status subtitle so Pro, Intelligence and Privacy read at a glance; “Capture on iPhone” turns the explainer paragraph into the five real paths with their state (keyboard not added, share sheet on).”
4. **Privacy Center:** “the hero, receipt, per-app table, diagnostics and issues stay; a “Verify” group puts encryption, sync and masked count first (GC-21), and the unreadable-clips section appears only when the count is non-zero, as in v0.10.2.”

---

## Coverage

| Board element | Covered by |
|---|---|
| Header row (chips, title, subtitle, size) | context only |
| Shared phone chrome (status bar, nav buttons, `Gancho`, rail) | kept, no change (home is GC-26 / V4_Gancho_iPhone) |
| Phone 1 `NOW` current detail | context only (baseline for GC-27) |
| Phone 2 provenance row + Done | GC-27 |
| Phone 2 title row with edit | GC-27 |
| Phone 2 link hero + insight chips | GC-27 (insight chips shared with the Mac link hero on V4_Gancho_Panel) |
| Phone 2 full-width Copy | GC-27 |
| Phone 2 Share · Pin · Board · Snippet row | GC-27 |
| Phone 2 Smart actions chip group | GC-27 |
| Phone 2 Boards chips + suggestion | GC-27 |
| Phone 3 smart rows (All clips, Favorites) with counts | GC-28 (counts exist today) |
| Phone 3 `Boards` header `2 of 3 · Free` | GC-28 |
| Phone 3 board rows: swatch, sync subtitle, count | GC-28 |
| Phone 3 swipe actions (appearance, rename, delete) | GC-28 — kept, no change (shipped) |
| Phone 3 `New board` + footer | GC-28 |
| Phone 3 Snippets group | GC-28 |
| Phone 4 three status subtitles | GC-V4-12 |
| Phone 4 Language row | GC-V4-12 — kept, no change (picker) |
| Phone 4 Capture on iPhone (5 paths) + footer | GC-V4-12 |
| Phone 4 Your history group + footer | GC-V4-12 — kept, no change |
| Phone 5 hero | GC-21 — kept (text colour follows GC-V5-2) |
| Phone 5 Verify group | GC-21 |
| Phone 5 receipt, diagnostics, issues | GC-21 — kept (reordered below Verify) |
| Pin 1 | GC-27 |
| Pin 2 | GC-28 |
| Pin 3 | GC-V4-12 |
| Pin 4 | GC-21 |

---

## Feasibility

### GC-27 — iPhone clip detail with Copy as the primary (UI)

**Changes.** Restructure `ClipDetailView` top to bottom: provenance pill row (kind pill, source app, device, age) with Done → inline title → link hero (URL clips) or existing content section → full-width Copy → Share · Pin · Board · Snippet row → Smart actions as wrapping chips → Boards as chips with `+ Add` and the auto-board suggestion as a chip.

**Code.**
- `Apps/GanchoiOS/ClipDetailView.swift` — `actionRow` 135-158 (3-column, Copy primary; Copy dismisses at 138-139), `body` 188-278 (order: title, actionRow, content/editor, meta chips, boards, snippet section 205-212, smart actions; `.navigationTitle(kind)` 215), `contentSection` 290-336 (image tap-to-zoom 292-306, Reveal/Hide 307-333), `metaChipsSection` 339-362 (kind/Masked/app/device chips), `boardsSection` 366-419 (suggestion row with ⊗ dismiss 367-391, `board-suggestion`; member chips 394-411; `detail-add-to-board` 417), `smartActionsSection` 430-527 (dev actions, `transform-menu` 456, `smart-paste-\(id)-action` 479, `smart-paste-menu` 498, `translation-target-*` 490, `intelligence-result-text` 512).
- `Apps/GanchoiOS/ClipTitleEditor.swift` — wraps itself in `Section("Title")` (line 23); ids `detail-title`, `detail-edit-title` (label `Edit title` already, line 54), `detail-title-field`, `detail-save-title`, `detail-cancel-title`. Needs a section-less inline variant; the draft/cancel/save logic stays.
- `Apps/GanchoiOS/CaptureShell.swift:106-117` — peek is a `NavigationStack` with a toolbar `Done`; v4 moves Done into the pill row (or keeps the toolbar and hides the title — decide in implementation).
- Same view is reused by `Apps/GanchoiOS/IPadSplitView.swift:93-102` (iPad detail pane, capped 680) and `Apps/GanchoiOS/CaptureView.swift:438` (pushed detail): the change lands on iPad too.
- Link hero: `ClipLinkParts` is shared in `Packages/GanchoKit/Sources/GanchoDesign/Components.swift:84-98`; Mac renders it in `Apps/GanchoMac/ClipPeek.swift:520-536` (host + original URL only). Kind tint `.url` = `#32ADE6` (`Components.swift:106`); `TypeBadge` `.pill` style at `Components.swift:45`. Age text: Mac uses `.reference(to: item.createdAt, maxFieldCount: 1)` (`Components.swift:384-393`).
- Dev actions for URL: `Packages/GanchoKit/Sources/GanchoAI/DevActions.swift:65-69` = Parse URL, URL-encode, URL-decode, Base64 encode. Smart Paste: `SmartPasteService.swift:15-35` = Summarize, Fix grammar, Make formal, Make friendly, Key points, Redact PII. Transform list: `PasteTransform.swift`.

**Exists vs new.**
- Exists: Copy-primary logic, Share/Pin, Save-as-snippet, move sheet, suggestion, all actions and identifiers, title editing, image zoom, masking, `ClipLinkParts`, URL tint, age formatter.
- New: pill row layout, section-less title, iOS link hero, full-width Copy, 4-column secondary row with `Board` and `Snippet`, chip-group layout for actions (a FlowLayout; the Mac peek already has one for its Dev Actions chips), chip-form Boards section, insight chips `decoded · …` / `https` (not in the Mac `linkHero` today either), `Markdown link` action (absent from `DevActions`), new strings (`Smart actions`, `Snippet`, `Markdown link`, `decoded · …`) in `Apps/GanchoiOS/Localizable.xcstrings` EN+ES.

**Deps.** GC-V5-2 (accent ink `#1F7A3A` for green text); the V4_Gancho_Panel link-hero insight chips (share one helper); GC-33 (iPad uses the same view); GC-V4-18 (image detail “Text in image” lives in the same view); GC-V5-6 chip sizing is Mac-only.

**Verify.** Existing iOS UI tests must keep passing with ids unchanged: `Tests/GanchoiOSUITests/ClipTitleEditingUITests.swift`, `ClipTextEditingUITests.swift`, `TranslationCapabilityUITests.swift`, `CaptureFlowUITests.swift`. Add a UI test that the large-detent detail of a seeded URL shows the hero host, a single primary Copy, and the four secondary buttons. Unit test the insight-chip derivation (decoded path, scheme) next to `ClipLinkPartsTests`. Simulator screenshot vs phone 2.

**BLOCKED:**
- `Markdown link` is drawn but no such action exists, and the URL actions `URL-encode` / `Base64 encode` are not drawn. Add a new Markdown-link action, or is the chip list sample text?
- The suggestion chip has no dismiss (today’s row has ⊗ with `Dismiss`). How is a suggestion declined in v4?
- `Board` (action row) and `+ Add` (Boards chips) both open the same move sheet. Keep both, or drop one?
- `Snippet` for non-text or masked clips: today the snippet button is hidden (`isTextLike && !requiresMasking`). In the 4-column row, should it be hidden or disabled? And what does it show when the clip is already a snippet?

### GC-28 — Boards with identity, counts and Free limit (UI + small data)

**Changes.** In `BoardsHomeView`: header `Boards` gains `n of 3 · Free` on Free; each user board row gains a sync subtitle; footer copy; new `Snippets` group listing snippets as keyword + title.

**Free limits (code constants).**
- Boards: `PinLimits.freeMaxPinboards = 3` — `Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift:51`; gate `canCreatePinboard` line 57-59. Favorites does not count: `BoardsController.swift:110-117` filters `!$0.isSystem`.
- Snippets: `SnippetLimits.freeMaxSnippets = 20` — `Packages/GanchoKit/Sources/GanchoKit/SnippetLibrary.swift:7`.
- Pins: `PinLimits.freeMaxPins = 15` — `Pinboards.swift:50` (not drawn).
- Pressure helper: `FreeTierLimits.pressure` — `UserTier.swift:55-66`. Mac precedent: `Apps/GanchoMac/LibraryView+Sidebar.swift:166-178` shows `used/limit` only when `tier != .pro`.
- The footer’s “A third board” must be built from `freeMaxPinboards`, not hard-coded.

**Code.** `Apps/GanchoiOS/BoardsHomeView.swift` — counts via `reload()` 291-297 (`model.clipCount()` / `clipCount(in:)`, `IOSAppModel.swift:429-438`); `boardLabel` 270-279; `BoardDot` → `BoardIdentityMark` (colour exists); swipe actions 222-243 (Delete, Rename `.blue`, Appearance `.indigo`, already in the drawn order); `New board` 148-154 (`boards-home-new`); row ids `boards-home-<uuid>`. Snippets: `GRDBClipboardStore.snippets()` (`SnippetLibrary.swift:44`), `ClipItem.keyword` (`ClipItem.swift:32`). Tier: `IOSAppModel.tier` (line 98). Board sync state: the `pinboard` table has `needsUpload` / `syncSystemFields` (`SyncLocalStore.swift:645-671`), but `Pinboard` (`Pinboards.swift:9-38`) does not expose them.

**Exists vs new.** Exists: identity colour, live counts, swipe actions, Favorites built in, limit constants. New: Free header count, per-board sync subtitle (needs `Pinboard` or a query to expose sync state), Snippets group plus its navigation target, footer string, strings in the catalog.

**Deps.** GC-33 (iPad sidebar shows the same Free limit); GC-V4-7 (Mac Library Pro meter, same constants); GC-V4-12 (Pro subtitle uses the same counts).

**Verify.** Unit test a pure formatter (`used`, `limit`, `isPro`) → `2 of 3 · Free` / hidden for Pro, using `PinLimits.freeMaxPinboards` (do not hard-code 3 in the test). UI test with `-seed-sample-boards -use-temp-durable-store` (`IOSAppModel+UITestSeeds.swift:116-121`, seeds exactly `freeMaxPinboards` boards) asserting the header text. Screenshot vs phone 3.

**BLOCKED:**
- Per-board `Synced · Mac + iPhone`: there is no per-board record of which devices hold it. Derive it from clip `sourceDeviceName`, drop the device list, or show only `Synced` / pending?
- Sync is Pro-only (`SyncEnablement.swift:7-13`) but the board shows `Free` and `Synced` together. What does the subtitle say on Free (hidden? `On this iPhone`?)
- The note says the keyboard extension “already shows” snippet keywords. `Apps/GanchoKeyboard/KeyboardModel.swift` and `KeyboardView.swift` have no snippet or keyword code. The claim is wrong; confirm the Snippets group is new work. Where does a snippet row’s chevron go (the clip detail? an iOS snippet editor that does not exist)?
- Are snippets with no keyword listed? What is the primary line then?

### GC-V4-12 — iPhone Settings with status and capture paths (UI + feature)

**Changes.** Add subtitles to `Gancho Pro`, `Intelligence`, `Privacy Center`; replace the explainer paragraph and the `Shortcuts` section with a five-row `Capture on iPhone` group plus a shorter footer; Language becomes a value row.

**Code.** `Apps/GanchoiOS/IOSSettingsView.swift` — top group 23-42 (`open-pro`, `open-intelligence`, `open-privacy-center`; Privacy glyph is `lock.shield`), Language picker 43-50 (`language-picker`; `AppLanguage.system.displayName == "System"`), explainer 51-57, Shortcuts link 58-62 (`https://gancho.app/shortcuts`), history 63-98 (Spotlight footnote 69-77 not drawn). Data: `model.tier` (`IOSAppModel.swift:98`), boards/snippets counts (as GC-28; limits `PinLimits.freeMaxPinboards = 3`, `SnippetLimits.freeMaxSnippets = 20`), `model.intelligence` (`IntelligencePreferences`: `intelligentTitles`, `semanticSearch`, `searchableScreenshots`, `smartPaste` — `Packages/GanchoKit/Sources/ClipboardCore/IntelligencePreferences.swift:10+`), secrets via `full.sensitiveCount()` (used at `IOSPrivacyCenterView.swift:256`), analytics `0` is the constant hero value (`IOSPrivacyCenterView.swift:31`).

**Exists vs new.** Exists: every row’s destination, all data for the Pro, Intelligence and Privacy subtitles, the Shortcuts URL. New: subtitle composition (pure formatter), five capture rows, keyboard/share-sheet state detection (no code exists; the only keyboard state is `hasFullAccess` inside the extension), footer string.

**Deps.** GC-28 (shared count formatter), GC-21 (Privacy subtitle uses the same masked count), GC-36 (onboarding lists the same capture paths: `IOSOnboardingView.swift:43-47`).

**Verify.** Unit tests for the subtitle formatter (Free vs Pro; all-on vs mixed toggles). UI test that `open-pro`, `open-intelligence`, `open-privacy-center` still navigate and show their subtitles. Screenshot vs phone 4.

**BLOCKED:**
- `Gancho keyboard · Not added`: iOS has no public API that tells the container app whether a custom keyboard is installed. Show a static instruction row, infer it (for example from the extension having ever launched), or drop the state tag?
- `Share sheet · On`: the app cannot read share-extension visibility. Is `On` a static label?
- Copy: the board says `Settings → General → Keyboards → Add`; the iOS path (and the keyboard’s own text) is `Settings → General → Keyboard → Keyboards`. Which string ships?
- What does the Pro subtitle say on Pro? Does Intelligence show anything different when Apple Intelligence is unavailable?
- Where do the `Paste button` and `Widget` rows lead (no chevron drawn)? Are they plain info rows?
- Spotlight footnote (`Only snippets and pinned clips reach the system index…`) is not drawn. Keep it (pin 3 says every row stays) or drop it?

### GC-21 — Privacy Center opens with a Verify group (iPhone half) (UI + feature)

**Changes.** Insert `Verify, don’t trust` (encryption + Verify, iCloud sync + last-sync age, secrets masked) right after the hero; keep receipt, per-app table, diagnostics, issues below; the unreadable section stays conditional; rename `Secrets masked` → `Secrets masked now`.

**Code.** `Apps/GanchoiOS/IOSPrivacyCenterView.swift` — hero 26-44 (white text on `Palette.success.gradient`), receipt 46-75 (footnote 61-66 includes “Protected copies are included in skipped captures.”; Clear 67-71), per-app 77-106, `On this iPhone now` 108-111 (`Secrets masked`, `Items synchronized`), unreadable 113-152, `Capture on iPhone` 154-161, diagnostics 163-188, issues 190-220, `refresh()` 252-260. Sync: `IOSAppModel.syncStatus` (line 95) with `SyncStatus.upToDate(at: Date?)` (`Packages/GanchoKit/Sources/GanchoKit/SyncEngine.swift:6-13`); enablement `SyncEnablement.swift:7-13` (Pro + iCloud + entitlement). Encryption: production store always opens encrypted (`StoreBootstrap`, asserted in `StoreBootstrapTests.swift:152`); `IOSAppModel.store` falls back to `InMemoryClipboardStore` (`IOSAppModel.swift:920-937`), and nothing exposes “is encrypted” to the view.

**Exists vs new.** Exists: masked count, sync status and date, hero, receipt, diagnostics, issues, unreadable section, ids `ios-private-receipt-*`, `ios-telemetry-consent-toggle`, `ios-privacy-center`. New: Verify section, an encryption-state flag on the model, the Verify action, the sync row’s destination, hero ink `#04210D` (with GC-V5-2), strings.

**Deps.** Mac half on V4_Gancho_Settings (shared copy and Verify behaviour); GC-V5-2 / B-GC-03 (hero contrast; iOS hero has the same white-on-green issue); GC-V4-12 (subtitle).

**Verify.** `Tests/GanchoiOSUITests/PrivacyCenterUITests.swift` (receipt, issues, consent) must pass unchanged; add a UI assertion that the Verify group sits above the receipt. Unit-test the sync-row text from `SyncStatus` (upToDate with/without date, paused, failed, disabled on Free). Screenshot vs phone 5.

**BLOCKED:**
- What does `Verify` do on iPhone (and on Mac)? No verification routine exists in code.
- Catalog text lists “last content read” and “MCP agents” in the Verify group; the iPhone board shows the masked count instead. By precedence the board wins for iPhone. Confirm.
- `iCloud sync` row on Free or with sync off: what does it say? Where does its chevron lead? `Mac + iPhone` needs a device list that is not stored.
- Fate of sections not drawn and not named in pin 4: `Items synchronized`, `Capture on iPhone` (now in Settings), `Successful reuses this session` and the two diagnostics footnotes. Keep or remove?
- The board receipt footnote drops “Protected copies are included in skipped captures.” and puts `Clear activity receipt` above the footnote. Is that intended?
- Presentation: in code the Privacy Center is pushed from Settings (back button), but the board draws it as its own sheet with `Done`. Treat it as drawing shorthand?

### B-GC / SY links
No B-GC bug in the log is assigned to GC-27, GC-28, GC-V4-12 or GC-21. The board’s green ink (`#1F7A3A`) and dark hero text (`#04210D`) are the iPhone form of B-GC-02 / B-GC-03, which are fixed under GC-V5-2 (V4_Gancho_Settings). No SY item is referenced.

---

## Owner notes

- Picks: GC-27 `pick`, GC-28 `pick`, GC-V4-12 `pick`, GC-21 `pick`. No pick notes.
- No owner comment thread on this board. General rules that apply: compare every proposal with the current UI and only propose what beats it (code wins over v2 boards); each piece of data appears once per screen; annotations are not UI.
- Owner decision 3 (iPhone spacing) covers iPhoneSurfaces only, not this board.
