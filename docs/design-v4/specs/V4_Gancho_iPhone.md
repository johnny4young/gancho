# V4_Gancho_iPhone — spec

- **Board:** `V4_Gancho_iPhone.dc.html` — canvas title "Gancho v4 · iPhone Home, current vs v4".
- **Canvas:** 1700 × 1100 pt, background `#ECEDF0`, radius 12, padding 24 (top/bottom) × 28 (sides), vertical gap 14.
- **Shows:** the iPhone Home (capture) screen of v0.10.2 redrawn from code, then two v4 frames (a link sensed with the reuse banner; searching with visible filters, answer card and Related by meaning), plus an audit column (kept vs changed) and a PASS strip.
- **Related Current board:** `GanchoPhone_Current` (board rail All clips · Favorites · New board…, "Sensed, not read" row, `Today`, row context menu Copy · Pin · Delete, search + Paste bar).
- **Code home:** `Apps/GanchoiOS` (`CaptureView`, `CaptureShell`, `PasteboardStatusRow`, `HistoryFilterMenu`, `ReuseSuggestionBanner`, `IOSAppModel`) plus the shared row `ClipCard` in `Packages/GanchoKit/Sources/GanchoDesign/Components.swift`.
- **Units:** board px = pt (phones are drawn 1× at 390 × 844).
- **Dark mode:** not drawn. The board CSS defines dark values only as classes (phone `#000`, group `#1C1C1E`, secondary text `#A1A1A6`, home indicator `#F2F2F7`); use the system semantic colors, which already resolve both.

---

## 0. Header strip (annotation, not UI)

Left to right, height 22, gap 12:

- ID chip `GC-26` (green: bg `#34C759`, text `#0B2A14`, 11/800 mono, radius 7, padding 0 9).
- ID chip `GC-27` (dark: bg `#1D1D1F`, text `#FFFFFF`).
- Title 22/800, letter-spacing −0.02em: `iPhone Home · the current screen is the baseline, v4 is its next step`
- Subtitle 13 `#5B5B61`, max width 860: `Left: v0.10.2 redrawn from CaptureView, CaptureShell, PasteboardStatusRow. Middle and right: v4 with a link sensed, and while searching. Everything the current screen does is kept; the numbered notes are the only changes.` (`CaptureView`, `CaptureShell`, `PasteboardStatusRow` in mono).
- Right-aligned, 13 `#5B5B61`: `Gancho · iOS 26 · v4 · 390 × 844`

Below: one row, gap 28, four columns: Frame A (390), Frame B (390), Frame C (390), Audit (380). Each column has a label line above the phone (gap 8).

---

## Shared phone anatomy (all three frames)

Used by A, B and C unless the frame section says otherwise.

| Element | Spec |
|---|---|
| Phone shell | 390 × 844, bg `#F2F2F7` (systemGroupedBackground), radius 44, border 1 `rgba(29,29,31,.14)`, shadow 0 20 50 `rgba(0,0,0,.18)`. Body text `#1D1D1F`, 15. |
| Status bar | Height 54, content bottom-aligned, padding 0 30 4 34, 15/700. Left: time. Right (gap 5, 12): `●●●●` (signal, letter-spacing 1), 13 pt network glyph, battery 24 × 11 (border 1.5, radius 3, fill 17 wide). System chrome — not app UI. |
| Nav row | Padding 2 16 0, space-between. Left: Settings button 44 × 44 circle, bg `rgba(255,255,255,.82)`, inset 1 white .6 + shadow 0 1 2 `rgba(0,0,0,.08)`, gear glyph 20 `#1F7A3A`, aria `Settings`. Right: grouped capsule 44 high, radius 22, same glass, padding 0 4, two buttons 44 × 36: `Filters` (circle with three decreasing lines = `line.3.horizontal.decrease.circle`), `Boards` (stacked rectangles = `rectangle.stack`), glyphs 20 `#1F7A3A`. |
| Large title | `Gancho`, 34/800, letter-spacing −0.02em, padding 10 16 8. |
| Board rail | Horizontal, gap 8, padding 0 16, bottom padding 12, clipped. Chip: height 32, padding 0 12, radius 999, bg `rgba(120,120,128,.16)` (≈ `.quaternary` fill), 14/500, glyph gap 5, glyph 12. Active chip (`aria-pressed=true`): bg `#34C759` (accent), text `#0B2A14`, 600, leading checkmark glyph. "New" chip text `#5B5B61` with a `+` glyph. Favorites glyph: star, `#FF9F0A`. |
| List area | Padding 0 16, vertical gap 10 between blocks. |
| Section header | 13, `#5B5B61`, uppercase, letter-spacing .02em, padding 0 16, title left, count right (v4 frames only). |
| Group (inset grouped section) | Bg `#FFFFFF`, radius 12, separators 1 `rgba(60,60,67,.14)` between rows. |
| Clip row | Min height 60, padding 8 14, gap 12. Tile 36 × 36, radius 8, 15/800. Text column (gap 2): title 15/600 one line ellipsis; preview 13 `#5B5B61` one line ellipsis (code previews mono). Trailing column (right-aligned, gap 4): source line 11 `#6E6E73`; marker row (gap 4). |
| Bottom bar | Overlaid at bottom, padding 10 16 34, gap 10, gradient from transparent to `rgba(242,242,247,.92)` at 36%. Search field: flex, height 48, padding 0 16, radius 999, bg `rgba(255,255,255,.86)` + inset white .7 + shadow 0 1 2 `rgba(0,0,0,.08)`, magnifier 16 `#5B5B61`, text 16, placeholder `Search your clipboard` (`#8A8A8F`), aria `Search your clipboard`. Paste: 112 × 48, radius 999, bg `#34C759`, text `#0B2A14` 16/600, clipboard glyph 16, gap 7, label ` Paste`. Disabled Paste: bg `#A8D7B4`, text `#2D4F38`. |
| Home indicator | 134 × 5, radius 3, `#1D1D1F` at .85, bottom 8. System chrome. |

Kind tiles drawn (shared `ClipCard` tile, `GanchoTokens.Palette.kindTint`):

| Kind | Tile |
|---|---|
| code | bg `#5856D6` at 16%, glyph `</>` 15 `#5856D6` |
| color | fill = the colour itself (`#008080`), inset hairline `rgba(0,0,0,.12)` |
| link | gradient 160° `#5BC4F0` → `#32ADE6`, host monogram letter 15/800 `#0A2B3A` |
| image | thumbnail (sample: `#52BCCF` with an 18 pt `#F39B3A` circle) |
| secret | bg `rgba(255,59,48,.16)`, lock glyph 15 `#C8231B` |
| file (PDF) | bg `#007AFF` at 16%, document glyph `#007AFF` |
| text | bg `#8E8E93` at 16%, "A" glyph `#4B4B50` |

---

## Frame A — `NOW` · `Current · v0.10.2 (from code)` · `pasteboard empty`

Realises: context only (baseline). Matches `GanchoPhone_Current`.

Label line: dark ID chip `NOW`, then `Current · v0.10.2 (from code)` (13/800), small `pasteboard empty` (12/600 `#5B5B61`).

Top to bottom:

1. Status bar time `7:08`.
2. Nav row (Settings · Filters/Boards).
3. Large title `Gancho`.
4. Board rail: `All clips` (active, checkmark), `Favorites` (star `#FF9F0A`), `New board…` (`+`, grey).
5. Pasteboard status row (padding 6 4, gap 8, 14/500):
   - Pill: height 22, padding 0 9, radius 999, 11/600, bg `rgba(52,199,89,.14)`, text `#1F7A3A`, half-shield glyph 11, text `Sensed, not read`.
   - Text (flex): `Pasteboard is empty`.
   - Info button: 18 pt circled "i", `#8E8E93`, aria `How Gancho senses your clipboard`.
6. Section header `Today` (padding-top 8, no count).
7. Group with five rows (all sample):
   - `Example · Swift` / mono `let greeting = "Hello"` (`let` `#A33EA3`, `"Hello"` `#2E7D32`) / `Xcode · now`.
   - `Ocean` / mono `#008080` / `Figma · now`.
   - Link tile `E` / `Synthetic link` / `https://www.example.com:8443/a%2Fb?q=a%26b#se…` / `Safari · 7 min` + marker: cloud-with-down-arrow glyph 12 `#6E6E73` (today's `icloud.and.arrow.down` for the `universal-clipboard` tag).
   - Image tile / `Synthetic landscape` / `PNG · 1200 × 800` / `Vitrine · now` + filled pin glyph 11 `#6E6E73`.
   - Secret tile / title `•••` / preview `•••` / no source line, no markers.
8. Bottom bar: empty search field, Paste **disabled**.

---

## Frame B — `V4` · `v4 · Home` · `a link sensed · reuse banner`

Realises: GC-26 (status card), GC-V4-8 (counts + device), GC-V4-9 (secret row). Shows the kept reuse banner.

Label line: green ID chip `V4`, `v4 · Home`, small `a link sensed · reuse banner`.

Top to bottom:

1. Status bar time `9:41`.
2. Nav row: unchanged.
3. Large title `Gancho`.
4. Board rail (GC-V4-8):
   - `All clips · 128` — active (accent bg, checkmark). `128` (sample) is the active scope's count.
   - `Favorites` (star `#FF9F0A`), no count.
   - `Work` — leading 10 × 10 square, radius 3, `#2E70D1` (board identity mark), no count.
   - `Brand` — 10 × 10 square `#F08C08`, no count.
   - `New` — `+` glyph, grey `#5B5B61`. (Frame A draws `New board…`; see Owner notes / questions.)
5. **Status card** (GC-26), full list width:
   - Container: padding 10 12, gap 12, radius 14, bg `rgba(52,199,89,.12)`, border 1 `rgba(52,199,89,.25)`.
   - Leading tile 36 × 36, radius 8, bg `#32ADE6` at 16%, link glyph 15 `#32ADE6` (the sensed kind's tile).
   - Text column (flex, gap 3):
     - `Link on your clipboard` — 15/600.
     - 12, `#5B5B61`, line height 1.3: half-shield glyph 10, then ` Sensed, not read — nothing is saved until you tap Paste`.
   - Trailing pointer (column, centered, gap 2, `#1F7A3A`, 10/700): down-arrow glyph 16, then `Paste`. It points at the Paste control in the bottom bar.
   - No info button is drawn on the card.
6. Section header `Pinned` … `1` (count right).
7. Group, one row: image tile / `Synthetic landscape` / `PNG · 1200 × 800` / source line = laptop glyph 10 + ` Mac` + ` · Vitrine · now` (glyph gap 3) / pin marker 11 `#6E6E73`.
8. Section header `Today` … `5` (only four rows are visible above the banner; sample).
9. Group:
   - `Example · Swift` / `let greeting = "Hello"` / laptop glyph + ` Mac` + ` · Xcode · now`.
   - `Ocean` / `#008080` / laptop glyph + ` Mac` + ` · Figma · now`.
   - Link `E` / `Synthetic link` / `https://www.example.com:8443/a%2Fb?q=a%26b#se…` / `Safari · 7 min` — **no** cloud marker (it was on Frame A).
   - Secret row (GC-V4-9): secret tile / title `Stripe key · masked` / preview `sk_live_•••••••••• 4Q2v` (sample) / source `Terminal · 2 min` / expiry pill: height 18, padding 0 6, radius 999, bg `rgba(255,159,10,.18)`, text `#7A4B00` 10.5/600, timer glyph 9, text ` 9:41` (sample remaining time).
10. Reuse banner (kept): overlaid, left/right 12, bottom 98 (sits above the bottom bar); padding 10 12; gap 10; radius 12; bg `rgba(255,255,255,.95)`; shadow 0 4 14 `rgba(0,0,0,.14)`; 14/500.
    - Sparkles glyph 16 `#1F7A3A`.
    - `Add to Work?` (flex).
    - Button `Add`: height 30, padding 0 12, radius 8, bg `#34C759`, text `#0B2A14` 13/600.
    - Dismiss: circled × 20 `#8E8E93`, aria `Dismiss`.
11. Bottom bar: empty search field, Paste **enabled**.

---

## Frame C — `V4` · `v4 · Searching` · `filters visible · answer · related`

Realises: GC-V4-10 (filter chips), GC-V4-11 (Related by meaning; answer card kept and restyled).

Top to bottom:

1. Status bar `9:41`.
2. Nav row: the `Filters` button is drawn **active**: glyph `#1D1D1F`, bg `rgba(52,199,89,.25)`, radius 18. `Boards` and `Settings` unchanged.
3. Collapsed title: `Gancho`, 22/800, letter-spacing −0.02em, padding 8 16 4 (scrolled/searching nav-bar title).
4. Chip row in the rail position (bottom padding 10). The board chips are not drawn here:
   - `Links` filter chip: rail chip metrics, bg `#1D1D1F`, text `#FFFFFF`, leading link glyph 12, trailing × glyph 11 (stroke 2.6). Pressed.
   - `Safari` filter chip: same dark style, leading 10 × 10 radius 3 app mark (gradient 135° `#4FC3F7` → `#1565C0`), trailing × 11. Pressed.
   - `Clear filters`: rail "New" style (default fill, text `#5B5B61`), no glyph.
5. Answer card (GC-V4-11, already shipping, restyled):
   - Container: group, bg `rgba(52,199,89,.1)`, border 1 `rgba(52,199,89,.22)`, radius 12; inner padding 10 12, gap 6.
   - Header (13/700, `#1F7A3A`, gap 6): sparkles glyph 13, ` Answer`, spacer, dismiss circled × 18 `#8E8E93` aria `Dismiss`.
   - Body 14, line height 1.35 (sample): `The Q3 invoice (in_1Q4ab2) is due on 30 October; the PDF you copied on Monday is the signed version.`
   - Caption 11 `#5B5B61`: `Sources · tap to copy`
   - Sources (13, gap 4; each glyph 12, gap 6), sample:
     - link glyph `#32ADE6` + `dashboard.stripe.com/invoices/in_1Q4ab2`
     - document glyph `#007AFF` + `invoice-q3.pdf`
   - Footer 11 `#5B5B61`, gap 4: shield glyph 10 + ` Answered on this iPhone · nothing sent`
6. Section header `Results` … `3`.
7. Group (sample):
   - Link `S` / `Stripe · invoice in_1Q4ab2` / `https://dashboard.stripe.com/invoices/in_1Q4ab2` / `Safari · 11 d`
   - Link `B` / `Invoice portal` / `https://billing.example.com/q3` / `Safari · 14 d`
   - Link `D` / `Zephyr invoice tracker` / `https://docs.example.com/invoices` / `Safari · 1 mo`
8. Section header `Related by meaning` … `2`.
9. Group (sample):
   - File tile / `invoice-q3.pdf` / `PDF · 212 KB` / `Files · 2 d`
   - Text tile / `Invoice Q3 — payment terms` / `Please find attached the invoice for Q3…` / `Mail · 9 d`
10. Bottom bar: search field value `invoice` + clear button (circled × 18 `#6E6E73`, aria `Clear search`); Paste **enabled**.

No "Ask gancho" row, no loading state and no meaning-search status line are drawn.

---

## Audit column — `Audit` · `kept vs changed` (annotation, not UI)

380 wide, 844 high, gap 10. Two white cards (padding 12 14, radius 14, border `rgba(0,0,0,.06)`, gap 8).

### Implementation notes (not UI)

Card 1, tag `Kept from the current app` (green tag), check-mark bullets, verbatim:

- "Bottom glass bar: search + the system Paste control (UIPasteControl — the only banner-free save path, within thumb reach)"
- "Board rail with identity marks; long-press to customise, rename, delete"
- "“Sensed, not read” chip + info popover; the row never reads content"
- "Swipe: Copy · Board (leading), Delete · Pin (trailing); long-press menu with preview"
- "Pinned first, then Today / Yesterday / This month…"
- "Tap → peek sheet at medium detent, drag up for everything else"
- "Reuse banner (Add to board / Save as snippet) above the bar"
- "Pull to refresh = iCloud sync; sync row only when transient or actionable"
- "Three honest empty states; Ask gancho row while typing"

Card 2, tag `What v4 changes` (dark tag), numbered notes, verbatim:

1. "**Status row → status card.** The sensed kind gets its tile and the card points at the Paste control it belongs to; after a save it reads **Saved · Open** for 4 s (the code already matches the pasteboard change counter). Same `detectPatterns` hints, no read."
2. "**Counts and provenance.** Active scope shows its count; section headers show theirs; synced clips show the device name (`sourceDeviceName` is stored but today only the detail shows it; the row has a bare cloud glyph)."
3. "**Secrets keep their mask and their clock.** Masked tail (the stored masked preview) plus the existing expiry badge, so the row says what it is and how long it stays."
4. "**Filters you can see and clear.** Type and app filters live inside the ⊜ menu today; v4 mirrors them as chips with × under the rail whenever one is active (Clear filters exists only inside the empty state now)."
5. "**Search = results + answer + meaning.** Ask gancho becomes a card with sources you can tap to copy (the row and `askClipboard` exist); a **Related by meaning** section reuses the Mac's hybrid retrieval on the iPhone's local index."
6. "**Dropped from v2, on purpose.** The floating orb duplicated the Paste control and could not avoid the paste banner; white floating cards and the top chips hid the native list, swipe actions and Dynamic Type. The current native list is the better base."

## PASS strip (annotation, not UI)

White card, radius 12, padding 14 18, 3 pt left bar `#34C759`. Chip `PASS 2026-10-17`, heading "Checked against the iOS code (no new iPhone screenshots)". Two notes, verbatim:

- `GC-V4-11` — "Narrowed: the answer card with up to four tap-to-open Sources already ships (CaptureView.answerCard). What is left is the Related by meaning section under the results."
- `Current` — "GanchoPhone_Current kept: board rail (All clips · Favorites · New board…), “Sensed, not read” row, searchable list and Paste control match CaptureView / PasteboardStatusRow. Only the star glyph was redrawn as SVG."

No numbered pins sit on the phones; the numbers 1–6 exist only in the audit card.

---

## Coverage

| Board element | Covered by |
|---|---|
| Header strip (chips `GC-26`, `GC-27`, title, subtitle) | Context only. `GC-27` belongs to `V4_Gancho_iPhoneFlows` and nothing of it is drawn here |
| Frame A — Current v0.10.2 | Context only (baseline, matches `GanchoPhone_Current`) |
| Frame B — nav row, title, Paste bar | Kept, no change |
| Frame B — `All clips · 128` rail count | GC-V4-8 |
| Frame B — `Work`/`Brand` identity marks | Kept, no change (board identity marks already ship) |
| Frame B — `New` chip label | Kept (open question: label shortened?) |
| Frame B — status card | GC-26 |
| Frame B — `Pinned 1`, `Today 5` header counts | GC-V4-8 |
| Frame B — ` Mac` device on rows | GC-V4-8 |
| Frame B — link row loses cloud glyph | GC-V4-8 (open question) |
| Frame B — `Stripe key · masked` row + expiry pill | GC-V4-9 |
| Frame B — reuse banner `Add to Work?` | Kept, no change |
| Frame C — Filters button active tint | GC-V4-10 |
| Frame C — collapsed `Gancho` title | Kept (system nav-bar behaviour while searching) |
| Frame C — `Links ×`, `Safari ×`, `Clear filters` | GC-V4-10 |
| Frame C — answer card (body, sources, dismiss) | Kept (ships); restyle + footer + `Sources · tap to copy` under GC-V4-11 |
| Frame C — `Results 3` header | GC-V4-8 (count) + GC-V4-11 (header title `Results`, today `History`) |
| Frame C — `Related by meaning 2` section | GC-V4-11 |
| Frame C — search value + clear button | Kept, no change (system `.searchable`) |
| Audit card "Kept" bullets 1–9 | Kept, no change |
| Audit note 1 | GC-26 |
| Audit note 2 | GC-V4-8 |
| Audit note 3 | GC-V4-9 |
| Audit note 4 | GC-V4-10 |
| Audit note 5 | GC-V4-11 |
| Audit note 6 | Context only (v2 orb, floating cards, top chips dropped) |
| PASS strip — GC-V4-11 note | GC-V4-11 (scope narrowed) |
| PASS strip — Current note | Context only |

---

## Feasibility

Line numbers are on `main` at `a251a65`.

### GC-26 — iPhone pasteboard row becomes a status card (UI)

**What changes**
- Replace the one-line `PasteboardStatusRow` (pill + title + info button) with the Frame B card: tile for the sensed kind, title, the privacy line `Sensed, not read — nothing is saved until you tap Paste`, and a non-interactive `↓ Paste` pointer to the bottom-bar Paste control.
- After a durable save the card shows `Saved · Open` for 4 s. `Open` opens the saved clip.

**Code**
- `Apps/GanchoiOS/PasteboardStatusRow.swift`: whole view. `chip` 47–64 (note/Saved/Sensed states), `infoButton` 72–100 (popover copy), `alreadyCaptured` 134–137, `senseTitle` 140–146 (titles `Pasteboard is empty`, `Link on your clipboard`, `Search text on your clipboard`, `Number on your clipboard`, `Something on your clipboard`).
- `Apps/GanchoiOS/CaptureShell.swift:301-312` `PasteboardSection`: clear row background, 4 pt insets. The card needs its own background and corner radius.
- `Apps/GanchoiOS/IOSAppModel.swift`: `lastCapturedChangeCount` 44, `saveNote` 48, `flashNote` 1045–1058, `handleIntentionalReads` 1150–1186 (sets `lastCapturedChangeCount` only after a durable write, notes `Saved` / `Already in your history` / failures).
- `Apps/GanchoiOS/IOSAppModel+UITestSeeds.swift:99-113`: note lifetime is **2 s** (`-ui-test-save-note-lifetime` overrides it in DEBUG).
- `Packages/GanchoKit/Sources/ClipboardCore/IntentionalPasteboardSource.swift:15-58`: `ContentHints` = `hasContent`, `probableWebURL`, `probableWebSearch`, `number`, `changeCount` (no read, no banner).
- Tile colours: `GanchoTokens.Palette.kindTint` (`Components.swift:103-113`).

**Exists vs new**
- Exists: detect-only hints, the change-count match ("Saved" while the same copy is on the pasteboard), status notes with kinds, the info popover, the 44 pt info target.
- New: card layout and background; a hint-to-tile mapping; the privacy line string; the `↓ Paste` pointer; `Saved · Open` for 4 s, which needs the saved clip's id kept on the model (outcomes are available in `handleIntentionalReads` but not stored); an `Open` action that pushes the detail (reuse the `deepLinkClip` path, `CaptureShell.swift:67-71`); new strings `Sensed, not read — nothing is saved until you tap Paste`, `Open`, `Saved · Open` (EN + ES in `Apps/GanchoiOS/Localizable.xcstrings`).

**Constraints**
- The pointer must not be a button. Only `UIPasteControl` saves without the banner (`CaptureView.swift:445-507`). Mark the pointer `accessibilityHidden`, or fold it into the card's label.
- `Open` needs a 44 pt target.
- Keep the current `ViewThatFits` two-layout fallback (`PasteboardStatusRow.swift:20-39`) so Dynamic Type and Spanish wrap instead of truncating.
- Failure and limit notes must still render in the card with their symbol, tint and `accessibilityValue`.

**Deps**
- GC-36 (`V4_Gancho_Onboarding`, first run explains "Sensed, not read") must use the same copy.
- GC-V4-17 (Live Activity `Open`) should use the same open-clip path.

**Verify**
- Swift Testing: a pure `SensedKind(hints:)` mapping and the 4 s window logic.
- XCUITest: extend `Tests/GanchoiOSUITests/IntentionalCaptureUITests.swift` / `CaptureFlowUITests.swift` (ids `save-note`, `pasteboard-status-title`, `pasteboard-info`, `paste-control`). Add `pasteboard-status-card` and `pasteboard-saved-open`. Assert that `Open` pushes the detail and that the card returns to its idle state after the window.
- Snapshot against Frame B.

**BLOCKED**
1. The info button / popover is not drawn on the card, but the audit says "“Sensed, not read” chip + info popover" is kept. Keep the ⓘ (44 pt) on the card?
2. Tiles for the non-link hints (search text, number, generic, empty) are not drawn. Which glyph and tint for each? Is the card still shown when the pasteboard is empty, or does the empty state stay as today's one-line row?
3. After the 4 s `Saved · Open`, does the card go back to the current persistent "Saved" state (same change count) or to idle?
4. Images: `hasImages` is folded into `hasContent`, so "Image on your clipboard" would need a new metadata flag. Is it in scope?

### GC-V4-8 — iPhone counts and device provenance on rows (UI)

**What changes**
- The active rail chip shows its count (`All clips · 128`).
- Section headers show a right-aligned count (`Pinned 1`, `Today 5`, `Results 3`, `Related by meaning 2`).
- Rows of clips captured on another device show a device glyph and name before `App · time`.

**Code**
- `Apps/GanchoiOS/CaptureView.swift`: `boardRail` 228–281 and `railChip` 283–310 (label + checkmark/identity mark); sections 44–57 use plain `Section(sectionTitle(...))` (search results go under `History`); `sectionTitle`/`bucketTitle` 206–223.
- Counts: `IOSAppModel.clipCount()` 429–432 and `clipCount(in:)` 435–438 exist, and are used by `BoardsHomeView.swift:293-295`. Sections come from `HistoryListViewModel.sections` (`Packages/GanchoKit/Sources/GanchoAppCore/HistoryListViewModel.swift:24, 159-162`). The Mac precedent `Apps/GanchoMac/PanelResultsView.swift:143-170` shows `"\(count) clips"` with a numeric transition.
- Provenance: `ClipCard.sourceTimeLine` (`Components.swift`, the "Safari · 12 minutes ago" block near the end of `ClipCard`) and the `universal-clipboard` marker in `trailingMeta` (`icloud.and.arrow.down`, label `From another device`).

**Provenance — confirmed**
- `ClipItem.sourceDeviceName` (`Packages/GanchoKit/Sources/GanchoKit/ClipItem.swift:24`).
- Projected in `ClipRow.swift:43/61/84/109`.
- Synced by `GanchoSync/ClipRecordMapper.swift:50,97`.
- Part of the dedupe index (`GanchoDatabaseMigrator.swift:337-349`).
- Written at capture by `Apps/GanchoShared/PlatformDeviceProvenance.swift:13-23`: macOS `Host.current().localizedName`, iOS `UIDevice.current.name`. Callers: `IOSAppModel.swift:1225`, `AppModel.swift:727`, `SharedCapture.swift:40`.
- Shipped in PR #93 (merge `520d944`) and refactored in PR #190 (`d90575f`).
- Today it is shown only in the detail: `ClipDetailView.swift:354-355` (`desktopcomputer` chip).

**Exists vs new**
- Exists: stored, synced device name; total and board counts.
- New: count on the active chip only; a custom section header with a count (localized number formatting; VoiceOver "Today, 5 clips"); a device glyph + name on rows when `sourceDeviceName` ≠ this device's name (inject the current name through the environment; the row must not call UIKit in the package); a count refresh after capture, delete, sync and board change.
- `ClipCard` is shared with the Mac panel, the Library and the iPad split view, so the device line needs an opt-in parameter.

**Deps**
- GC-28 (iPhoneFlows boards with counts) must use the same count source.
- The GC-V4-11 `Results` header.

**Verify**
- Swift Testing: a pure "show device?" predicate (nil/empty/equal/different) and header-count derivation.
- XCUITest: a seeded clip with a foreign `sourceDeviceName`, asserting the row label.
- Snapshot against Frame B.

**BLOCKED**
1. Device label: the board draws `Mac` with a laptop glyph, but the stored value is the full Mac name (for example "Johnny's MacBook Pro"). Show the stored name (truncated) or a device class (`Mac` / `iPhone` / `iPad`)? A class needs a new stored field or a heuristic.
2. Section counts on iOS: the recent list paginates (`loadMoreIfNeeded`), so a loaded-rows count (the Mac approach) can undercount the last loaded bucket. Accept that, or add per-bucket SQL counts?
3. Frame B drops the cloud glyph from the `Synthetic link` row without adding a device. That glyph marks the `universal-clipboard` tag (Handoff), not iCloud sync. Remove it, or keep it beside the device name?
4. The count is drawn bare (`128`, `5`) while the Mac shows `N clips`. Confirm bare numbers on iPhone.

### GC-V4-9 — iPhone secret rows show mask and expiry (UI + privacy)

**What changes**
- Masked rows show a title, the stored masked preview (instead of `•••` / `•••`), the source and time, and the expiry as a pill (bg `rgba(255,159,10,.18)`, text `#7A4B00`, timer glyph, `mm:ss`).

**Code**
- `Packages/GanchoKit/Sources/GanchoDesign/Components.swift` (`ClipCard`):
  - `init` sets `previewsHidden = previewsHidden || ClipSafePresentation.requiresMasking(item)`, which collapses "private mode" and "masked kind" into one flag.
  - `previewText` renders `•••`.
  - `sourceTimeLine` is hidden when `previewsHidden`.
  - The expiry badge in `trailingMeta` is a `TimelineView` with `Text(expiresAt, style: .timer)`, warning-tinted text with no pill, shown only when < 1 h left (`showsExpiryCountdown`).
  - `Text.clipRowDescription` near line 443.
- Stored mask: `SensitiveMasking.maskedPreview` (`Packages/GanchoKit/Sources/GanchoAI/SensitiveDataDetector.swift:258-264`) gives `●●●● ` + last 4 non-whitespace characters, or `●●●●` for multiline or ≤ 8 characters. It is applied in `SensitiveIngestionPolicy.decorate` (267–289, default lifetime 600 s) and `ClipItemFactory.swift:98`.

**Privacy rule (must hold)**
- Lock-screen and widget surfaces keep `•••` with no title. They read `ClipSafePresentation.displayText` / `WidgetClips.entries` (`Packages/GanchoKit/Sources/GanchoKit/WidgetClips.swift:5-89`), `ClipActivityController.swift:26-32` and `Apps/GanchoWidgets/ClipLiveActivity.swift:111`. Do **not** change `ClipSafePresentation`; change only the in-app row.
- The stored preview is already masked, so no secret reaches the row. No masked preview in logs or telemetry either.

**Exists vs new**
- Exists: the stored masked preview, the expiry date, the countdown.
- New: separate the private-mode flag from the masked-kind flag in `ClipCard` (an opt-in parameter, because the Mac panel, Library and iPad use the same row); render the stored preview; show the source line for masked rows (metadata; `WidgetClipEntry` already treats it as safe); restyle the badge as a pill.

**Verify**
- Extend `Packages/GanchoKit/Tests/GanchoDesignTests/ClipCardPrivacyTests.swift` and `ClipCardExpiryTests.swift`.
- Add a test that `WidgetClips.entries` and `ClipSafePresentation.displayText` still return `•••` for secrets.
- XCUITest with a seeded secret clip.
- Snapshot against Frame B.

**Side finding:** the row's existing `Expires soon` label is not in `Apps/GanchoiOS/Localizable.xcstrings` or the Mac catalog; check that `LocalizationTests` scans package sources.

**BLOCKED**
1. Title `Stripe key · masked`: sensitive clips have an empty title (the `EnrichmentPlan` refuses sensitive clips), and the detector `Category` is not persisted on `ClipItem`. Persist the category (schema + CloudKit field) or use a generic kind label (for example `Secret · masked`)?
2. Mask format: the board draws `sk_live_•••••••••• 4Q2v`, but the stored format is `●●●● 4Q2v` with no prefix. The board's own note says "the stored masked preview". Confirm the stored format, so no masking change.
3. Should the macOS panel and Library also show the masked tail and source, or only iOS?
4. Should the pill show always, or only inside the current < 1 h window? (Secrets default to 10 min, so they always qualify.)

### GC-V4-10 — Visible filter chips under the board rail (UI)

**What changes**
- When a type or app filter is active, show dismissible chips (`Links ×`, `Safari ×`) plus `Clear filters`, and give the toolbar Filters button an active tint. The ⊜ menu stays.

**Code**
- `Apps/GanchoiOS/HistoryFilterMenu.swift:8-59`: menu with `Apps` (`All apps`, per-app rows with counts, `app.dashed`) and the `Filter by type` picker (`All types`, kinds), id `history-filter-menu`, label `Filters`.
- `Apps/GanchoiOS/CaptureView.swift`: `hasActiveFilter` 320–323, `clearFilters` 325–329 (it also resets the **board**), `emptyState` 335–364 (`Clear filters` appears only here today).
- State: `HistoryListViewModel.kindFilter` / `selectedSourceAppBundleID` (28–42).
- Toolbar placement: `CaptureShell.swift:148-153`.

**Exists vs new**
- Exists: the filters, clear logic and app names (`SourceApp.fallbackName`).
- New: a chip row, a per-chip remove action, a top-level `Clear filters` chip, and the active tint on the Filters button.
- Chips are drawn 32 pt high, so the hit area must reach 44 pt. Tap the whole chip to remove it; × is the visual affordance.
- Accessibility labels (for example "Remove Links filter").
- ids: `filter-chip-kind`, `filter-chip-app`, `filter-clear`.
- iOS has no app icon, so the drawn coloured Safari mark has no source; use a glyph.
- The kind chip label must come from the localized kind name.

**Deps**
- GC-V4-1 (Novel2: filter tokens inside the field) may supersede this on the Mac; keep the semantics aligned.

**Verify**
- Extend `Tests/GanchoiOSUITests/SourceAppFilterUITests.swift`: chip appears, tap removes it, `Clear filters` clears both.
- Swift Testing for the "active filters → chips" mapping.
- Snapshot against Frame C.

**BLOCKED**
1. Frame C draws the chips **in place of** the board rail (no board chips visible), but note 4 and the catalog say "under the rail". Which one?
2. Should the chip-row `Clear filters` keep today's behaviour of also resetting the selected board?
3. The active chip style is dark `#1D1D1F` / white, not the accent used by the rail. Confirm, since the same row mixes it with the accent-active board chip.

### GC-V4-11 — iPhone search with answer and related by meaning (feature)

**What changes**
- Below the conventional results (header renamed `History` → `Results`, with a count), add a `Related by meaning` section with semantic neighbours on the iPhone's local index.
- Restyle the answer card: green tint, caption `Sources · tap to copy`, footer `Answered on this iPhone · nothing sent`.

**Code (exists)**
- `CaptureView.askRow` 119–136 and `answerCard` 138–176: up to 4 sources; a tap **copies** (`copyToPasteboard`, line 159); id `ask-answer`.
- `IOSAppModel.askClipboard` 787–802.
- Shared retrieval: `MeaningRetrieval`, `MeaningSearchState`, `MeaningSearchSource` (`Packages/GanchoKit/Sources/GanchoAppCore/MeaningSearchState.swift:6-109`) and `HybridSearchResult` (`GanchoAppCore/HybridRetrieval.swift:4`), which dedupes related against conventional results.
- Mac adapter `Apps/GanchoMac/AppModel+MeaningSearch.swift`; Mac wiring `PanelSearchModel.swift:419-443`; Mac section `PanelResultsView.swift:126-138` (id `meaning-related-heading`).
- iOS store `grdbForEngines` (`IOSAppModel.swift:187`); toggle `intelligence.semanticSearch` (`IntelligenceView.swift:69-72`).

**New**
- `IOSAppModel` conforms to `MeaningSearchSource`.
- `HistoryListViewModel` owns a `MeaningSearchState`, started after each `search()` with a non-empty query, and is invalidated on query or filter change.
- The `Related by meaning` section, plus `Results` with a count.
- Strings to add to the iOS catalog (EN + ES): `Results`, `Related by meaning`, `Sources · tap to copy`, `Answered on this iPhone · nothing sent`.
- Sensitive clips are already excluded by semantic search (`SemanticSearch.swift:59,185`).

**Gaps**
- iOS embeds only clips it enriches itself (Pro, non-sensitive; `IOSAppModel.enrich` 1253+), and embeddings are device-local.
- There is no iOS indexer for clips synced from the Mac, so coverage of synced history will be low.

**Deps**
- Pro and Intelligence gating (GC-V4-12 settings shows Intelligence status).
- GC-V4-8 for header counts.

**Verify**
- Swift Testing in `Packages/GanchoKit/Tests/GanchoAppCoreTests/HistoryListViewModelTests.swift` (related state cleared on query change, dedupe) and `MeaningSearchStateTests.swift`.
- iOS XCUITest with a DEBUG seed like the Mac's `-ui-test-related-results`.
- Snapshot against Frame C.

**BLOCKED**
1. The Mac requires an explicit `By meaning` toggle; the iPhone frame draws none. Run automatically whenever `semanticSearch` is on?
2. Loading, incomplete-index and unavailable states are not drawn. Reuse the Mac status copy, or stay silent?
3. Backfill embeddings for synced clips on iPhone? That is new work, without which the section is mostly empty.
4. Conflict: the PASS strip says "tap-to-open Sources", but the board and the code copy on tap. The code + board wording is assumed to be correct.

### GC-27 — iPhone clip detail with Copy as the primary

Not realised on this board. Only the header chip appears; the item's board is `V4_Gancho_iPhoneFlows`. The related kept bullet "Tap → peek sheet at medium detent" already ships (`ClipDetailView.swift:276`, `presentationDetents([.medium, .large])`).

### Kept items, verified in code (no work)

- Paste control `UIPasteControl`: `CaptureView.swift:445-507`, framed 112 × **44** in `CaptureShell.swift:181`. The board draws it 48 high; keep the code value.
- Swipe and context actions: `CaptureShell.swift:190-267`.
- Reuse banner: `ReuseSuggestionBanner.swift` (material bg, radius 10, 44 pt Add and Dismiss targets; the board draws Add 30 high, keep the code).
- Pull to refresh = `forceSync` (`CaptureView.swift:92`); sync row only when transient (`371-389`).
- Three empty states: `CaptureView.swift:335-364`.
- Board rail long-press `Customize board…` / `Rename board…` / `Delete board`: `CaptureView.swift:246-260`.
- Dynamic Type: `ClipCard` uses `@ScaledMetric` tile sizing and `panelFont`, which keeps the iOS Dynamic Type styles (`PanelTypography.swift:13`). New card, chips and headers must use text styles, not fixed sizes. The pt sizes above are the board's default-size values.

---

## Owner notes

- Pick notes: GC-26, GC-V4-8, GC-V4-9, GC-V4-10 and GC-V4-11 are all `pick` with no note. GC-27 is `pick` with no note (its board is iPhoneFlows).
- There are no owner comment threads on this board.
- Owner rules that apply:
  - Compare each proposal with the current UI and only propose what beats it; code wins over v2 boards and site screenshots.
  - Each piece of data appears once per screen. The `Mac` device and the source app must not repeat in the same row; the answer-card sources and the `Related by meaning` rows may show the same clip, so confirm that this does not count as duplicated data.
  - Annotations (audit column, PASS strip, numbered notes, header chips) are not UI.
- Owner-confirmed decision 3 (iPhone spacing) covers the share sheet and the large widget only, not this board.
- Label drift: Frame B draws the rail's last chip as `New`; code and Frame A use `New board…`. Not called out as a change; keep `New board…` unless the owner says otherwise.
