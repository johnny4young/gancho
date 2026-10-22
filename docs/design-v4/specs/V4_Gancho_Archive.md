# V4_Gancho_Archive — spec

- **Board:** `V4_Gancho_Archive.dc.html` (catalog id `GC-43`)
- **Canvas:** 1600 × 1760 pt, background `#ECEDF0`, radius 12, padding 24 (top/bottom) × 28 (sides), vertical gap 14.
- **What it shows:** an inventory of every idea from the v1 drafts, v2 boards, GC3 (v3) pages and three external design notes, with its status today: in v4 (names the board), shipped (names the code), dropped (gives the reason), plus a "Shipped · pass 2026-10-17" table and a "Discarded in triage" table. **This board is not UI.** Nothing on it is built as drawn; it is a ledger.
- **Related Current boards:** none directly (it references every v4 board).
- **Implementable rule:** the only Archive entries that may lead to implementation are the ones marked **→ v4 board** below; they are built from that board's spec, never from this one. `shipped`, `dropped`, `skipped` and `not adopted` entries are closed.

## 1. Board layout (as drawn, for completeness)

1. **Header row** (flex, gap 12): id pill `GC-43` (green variant: bg `#34C759`, text `#0B2A14`, 22 pt high, radius 7, 11 pt / 800 mono); title `Archive · what the old versions contained and where it lives now` (22 pt / 800, tracking −.02em); subtitle (13 pt, `#5B5B61`, max 860 wide) `This board replaces the v1 drafts, the v2 boards, the GC3 pages and the three separate design artifacts. If an idea is not here, it was never proposed.`; right-aligned `Gancho · v4 · 2026-10-17`.
2. **Counter row** (gap 8): `68 ideas inventoried` (grey tag), `31 in v4` (green pill `#E3F5E8`/`#1F7A3A`), `27 shipped` (grey pill `#E5E5EA`/`#1D1D1F`), `11 dropped` (red pill `#FDECEC`/`#C8231B`), `0 open` (amber pill `#FFF1DB`/`#7A4B00`); then the note: `Every v1, v2 and v3 board and the three external design notes were read against main @ 486201d (v0.10.2); the pass of 2026-10-17 re-checked v4 against 23 Mac screenshots and main @ a251a658 (section at the bottom). “In v4” names the board; “shipped” names the code; “dropped” gives the reason.`
3. **Main inventory card** (white, radius 14, two-column grid gap 18): two tables, columns `Idea` 40% · `Source` 18% · `Status · where it lives now` 42%. Table text 11 pt; header 10 pt / 700 uppercase `#5B5B61`; group rows 10 pt / 800 uppercase on `#F2F2F5`; status pill 18 pt high, 10.5 pt / 700; reason text `#5B5B61`.
4. **Shipped card** (white, radius 12, padding 12 × 14): pill `shipped`, heading `Shipped · pass 2026-10-17 (23 Mac screenshots + main @ a251a658)` (14 pt / 800), note `Items moved out of the catalog, or whose shipped part is recorded here while the rest stays in v4.`; table `Item` 120 · `Idea` 330 · `Evidence` · `Status` 400, 12 pt.
5. **Skipped card**: red pill `skipped`, heading `Discarded in triage · Oct 18, 2026`, note `Removed from its proposal board and from the catalog by the owner’s Design Picks decision.`; table `Item` 120 · `Idea` 420 · `Reason` 330 · `Came from`.

## 2. Inventory — every entry

Status and reason are verbatim from the board. "Where now" = the v4 board or code. **→ v4** marks the entries that may be implemented (via that board's spec). Code paths for shipped entries are verified in §4.

### 2.1 v1 · GanchoPanel / GanchoEmpty / GanchoPhone

| # | Idea (verbatim) | Source | Status | Reason / where (verbatim) | Where now |
|---|---|---|---|---|---|
| 1 | Search modes as a visible group (Text · Fuzzy · Regex · Meaning) | v1 GanchoPanel | in v4 | `Panel · pills inside the field (GC-V4-1)` | **→ v4** V4_Gancho_Novel2 (GC-V4-1; board text says Panel) |
| 2 | Masked secret row with its lifetime (“kept 10 min”) | v1 GanchoPanel | in v4 | `Panel · PanelStates (GC-09)` | **→ v4** V4_Gancho_PanelStates (GC-09) |
| 3 | “Title generated on this Mac · bound to this content” | v1 GanchoPanel | shipped | `content-bound titles; v4 peek header says “written on-device”` | code (V1); peek header copy **→ v4** Peek |
| 4 | Add to stack ⌥⌘⏎ with a visible Stack · 2 counter | v1 GanchoPanel | in v4 | `Panel dock + footer badge (GC-10)` | **→ v4** Panel (GC-10) |
| 5 | Footer lists the keys for the current state | v1 GanchoPanel | shipped | `PanelStatusFooter hints + ⌘/ cheat-sheet` | code (V2) |
| 6 | Panel size preset shown in the footer (“Standard”) | v1 GanchoPanel | dropped | `presets live in General and the ⌘/ sheet; the footer keeps capture · sync · stack` | — |
| 7 | Empty panel: title, one line, one action | v1 GanchoEmpty | in v4 | `PanelStates · three keys + importer (GC-05)` | **→ v4** PanelStates (GC-05) |
| 8 | “Copy a sample to try” button | v1 GanchoEmpty | dropped | `onboarding step 4 captures a real first copy instead` | — (step 4 itself is GC-35, **→ v4** Onboarding) |
| 9 | No results offers Fuzzy / By meaning / All boards with counts | v1 GanchoEmpty | in v4 | `PanelStates (GC-08)` | **→ v4** PanelStates (GC-08) |
| 10 | Board empty state (“Nothing in Work yet · Pin from history”) | v1 GanchoEmpty | shipped | `three honest empty states on iPhone; Library saved-filter empty copy` | code (V3) |
| 11 | iPhone “Copied on your Mac · 1 min ago” banner with Copy | v1 GanchoPhone | shipped | `Live Activity “Ready to paste” after a sync + device provenance on rows (GC-V4-8)` | code (V4, **partial — see flag**); rows provenance **→ v4** iPhone (GC-V4-8) |
| 12 | Secret row “clears in 8 min” on iPhone | v1 GanchoPhone | in v4 | `iPhone (GC-V4-9)` | **→ v4** V4_Gancho_iPhone (GC-V4-9) |
| 13 | Swipe Board · Pin on iPhone cards | v1 GanchoPhone | shipped | `swipeActions leading/trailing` | code (V5) |

### 2.2 v2 · GanchoPanelV2 / GanchoPhoneV2 / GanchoLibraryV2

| # | Idea | Source | Status | Reason / where | Where now |
|---|---|---|---|---|---|
| 14 | Keys drawn on every verb, content as a card with a kind edge | v2 PanelV2 | shipped | `action dock + hero peek; kept in v4` | code (V6) |
| 15 | “Paste into Figma” names the target app | v2 PanelV2 | in v4 | `Panel (GC-V4-2)` | **→ v4** Panel (GC-V4-2) |
| 16 | Colour row with Teal · rgb · HSL; colour hero with formats | v2 PanelV2 · v3 GC-04 | in v4 | `Peek · colour hero with contrast check (GC-V4-14); Convert color dev action already outputs the formats` | **→ v4** Peek (GC-V4-14); Convert color exists (V7) |
| 17 | Link insight chips: decoded · https · “no trackers” | v2 PanelV2 | shipped | `ContentNormalizer strips utm/fbclid at capture; v4 hero keeps decoded · https · port` | code (V8) |
| 18 | Smart paste as a markdown link ⇧⏎ | v2 PanelV2 | in v4 | `PanelStates · was/will diff (GC-12)` | **→ v4** PanelStates (GC-12) |
| 19 | Delete ⌫ and More ⌘. in the dock | v2 PanelV2 | shipped | `context menu and keys; the dock keeps five verbs` | code (V9, **partial — see flag**) |
| 20 | Concealed copy as a transient row (“Hidden · from 1Password · expires in 30 s”) | v2 PanelV2 · LibraryV2 | dropped | `concealed copies never get a row; they count in the receipt and the Privacy status tile (GC-19)` | — (privacy rule; tile is GC-19 **→ v4** Settings) |
| 21 | Floating orb + floating cards on iPhone | v2 PhoneV2 | dropped | `the orb duplicated UIPasteControl; cards hid the native list and swipes` | — |
| 22 | Board chips with counts on iPhone | v2 PhoneV2 | in v4 | `iPhone (GC-V4-8)` | **→ v4** iPhone (GC-V4-8) |
| 23 | Library search ⌘F · Grid / List · New board | v2 LibraryV2 | in v4 | `Library (GC-V4-5)` | **→ v4** Library (GC-V4-5) |
| 24 | Library kind filter chips and Newest sort | v2 LibraryV2 | in v4 | `Library toolbar (GC-V4-13)` | **→ v4** Library (GC-V4-13) |
| 25 | “Sensed, not stored” scope in the Library sidebar | v2 LibraryV2 | dropped | `nothing to list: concealed copies leave no clip; the count lives in Privacy` | — |
| 26 | Pro card as a meter of boards and snippets | v2 LibraryV2 | in v4 | `Library (GC-V4-7)` | **→ v4** Library (GC-V4-7) |

### 2.3 v3 · GC3 boards

| # | Idea | Source | Status | Reason / where | Where now |
|---|---|---|---|---|---|
| 27 | GC-01 Direction A · list + stage | GC3_PanelDirections | in v4 | `Panel` | **→ v4** Panel (GC-01) |
| 28 | **GC-02** Direction B · single column | GC3_PanelDirections | dropped | `panel minimum is 720 pt; Compact preset already shrinks the stage` | — (reason verified: V10) |
| 29 | **GC-03** Direction C · filmstrip at the screen edge | GC3_PanelDirections | dropped | `⌘G gallery covers visual browsing inside the window` | — (gallery exists: V15) |
| 30 | GC-04 Dark surfaces and ambient rule | GC3_PanelDirections | in v4 | `MenuBarDark` | **→ v4** MenuBarDark (GC-04) |
| 31 | GC-05 · 07 · 08 · 09 · 10 · 12 panel states | GC3_PanelStates | in v4 | `PanelStates` | **→ v4** PanelStates |
| 32 | GC-06 Paused banner names the cause + Resume | GC3_PanelStates | shipped | `capture notice banner (paused · private · denied · screen share · storage)` | code (V11) |
| 33 | GC-11 One searchable Transform | GC3_PanelStates | in v4 | `Peek` | **→ v4** Peek (GC-11) |
| 34 | **GC-13 · GC-14** OCR regions, per-line copy, secret hold-back | GC3_OCRAndImages | shipped | `PeekImageText (PR #140 / #150); kept on Peek` | code (V12) |
| 35 | **GC-15** Translate the recognised text | GC3_OCRAndImages | shipped | `PeekImageText translation state (entity chips, PR #150)` | code (V13) |
| 36 | GC-16 Dominant colours + eyedropper | GC3_OCRAndImages | in v4 | `Peek` | **→ v4** Peek (GC-16) |
| 37 | GC-17 · 19 · 20 · 21 settings status-first, concealed card, retention timeline, Verify group | GC3_PrivacySettings | in v4 | `Settings` | **→ v4** Settings |
| 38 | **GC-18** Ignored apps with identity and suggestions | GC3_PrivacySettings | shipped | `DenylistSettingsSection: icon, bundle id, Add app menu, built-in exclusions` | code (V14) |
| 39 | **GC-22** iCloud sync per board | GC3_PrivacySettings | dropped | `sync is one Pro toggle on the private CloudKit database; per-board scope needs schema work first` | — (reason verified: V16) |
| 40 | GC-23 · 24 · 25 ambient rule, mini-panel menu, hook badges | GC3_Ambient | in v4 | `MenuBarDark` | **→ v4** MenuBarDark |
| 41 | GC-26 · 27 · 28 iPhone home, detail, boards | GC3_iOSFlows | in v4 | `iPhone · iPhoneFlows` | **→ v4** iPhone, iPhoneFlows |
| 42 | GC-29 Share extension shows what will be saved | GC3_iOSFlows | in v4 | `iPhoneSurfaces (GC-V4-15)` | **→ v4** iPhoneSurfaces (GC-V4-15) |
| 43 | **GC-30** Keyboard with board chips | GC3_iOSFlows | shipped | `KeyboardView boardRow; v4 adds the inserted mark (GC-V4-19)` | code (V17); inserted mark **→ v4** iPhoneSurfaces (GC-V4-19) |
| 44 | GC-31 Widgets small / medium / large + Lock Screen control | GC3_iOSFlows | in v4 | `small, medium, control shipped; large on iPhoneSurfaces (GC-V4-16)` | code (V18) + **→ v4** iPhoneSurfaces (GC-V4-16) |
| 45 | **GC-32** Live Activity with actions | GC3_iOSFlows | in v4 | `shipped without actions; actions on iPhoneSurfaces (GC-V4-17)` | code (V19) + **→ v4** iPhoneSurfaces (GC-V4-17) |
| 46 | GC-33 · 34 iPad split view, drag-out | GC3_iPad | in v4 | `iPad` | **→ v4** iPad |
| 47 | GC-35 · 36 onboarding Mac and iPhone | GC3_Onboarding | in v4 | `Onboarding` | **→ v4** Onboarding |
| 48 | GC-37 · 38 · 39 · 41 · 42 motion storyboard and tokens | GC3_Motion | in v4 | `Motion (GC-V4-21…24); GC-V4-20 skipped in triage Oct 18` | **→ v4** Motion (GC-V4-22…24; GC-V4-21 shipped, GC-V4-20 skipped) |
| 49 | **GC-40** Swipe actions on iPhone cards | GC3_Motion | shipped | `swipeActions + context menu` | code (V5) |
| 50 | **GC-43** Catalog | GC3_Catalog | in v4 | `v4_catalog + this Archive` | this board + the v4 catalog (documentation, nothing to build) |

### 2.4 External artifacts

| # | Idea | Source | Status | Reason / where | Where now |
|---|---|---|---|---|---|
| 51 | Diagnosis: five bands, 30 pt tiles, peek as a menu, nested glass, one colour, no motion | Rediseño del panel | shipped | `one toolbar, 36 pt kind tiles, hero + dock, list and peek in one material (v0.9–0.10)` | code (V20) |
| 52 | Direction A “Vidrio tranquilo” · hero per kind · dock with keys | Rediseño del panel | shipped | `ClipPeek hero + PeekActionButton dock; v4 Panel builds on it` | code (V6) |
| 53 | Selection bar that slides between rows · rolling counters · paste bounce | Rediseño del panel | in v4 | `Motion (GC-V4-21 · 22); numericText and symbol bounce already in code` | slide = shipped (GC-V4-21, V24); paste press **→ v4** Motion (GC-V4-22, pick = maybe) |
| 54 | Direction B “Escenario” · MeshGradient ambient tint | Rediseño del panel | shipped | `Ambient color toggle (PanelAmbientTint); v4 restricts it to the peek (GC-23)` | code (V21); restriction **→ v4** MenuBarDark (GC-23) |
| 55 | Direction C “Galería viva” · ⌘G grid | Rediseño del panel | shipped | `⌘G gallery (PanelGalleryCard)` | code (V15) |
| 56 | Vertical date scrubber beside the gallery | Rediseño del panel | dropped | `the gallery sits inside a 540 pt panel; date headers do the job` | — |
| 57 | No remote favicons or link metadata; macOS 15.4 fallback; Return order fixed; test ids kept | Rediseño del panel | shipped | `constraints still hold; v4 hero is typographic and local` | code (V22) — standing constraint for every v4 board |
| 58 | iOS A · status chip + Paste in the floating cluster | Pasteboard y Settings Capture | shipped | `PasteboardStatusRow + bottom bar UIPasteControl; v4 turns the row into a card (GC-26)` | code (V23); card **→ v4** iPhone (GC-26) |
| 59 | iOS B · compact card above the list | Pasteboard y Settings Capture | dropped | `A shipped; B kept only as the rejected path` | — |
| 60 | Settings window wide enough for seven tabs · sidebar alternative | Pasteboard y Settings Capture | shipped | `SettingsView 760 × 500 with a 210 pt sidebar` | code (V25) |
| 61 | One “Add app” menu: running app ▸ · Applications… · bundle id… with live validation | Pasteboard y Settings Capture | shipped | `DenylistSettingsSection; redrawn on Settings · Capture` | code (V14); redraw **→ v4** Settings |
| 62 | Built-in exclusions collapsed with count, grouped, toggles, Restore defaults | Pasteboard y Settings Capture | shipped | `SourceAppDenylist suggestions by category; redrawn on Settings · Capture` | code (V14); redraw **→ v4** Settings |
| 63 | Option A · text in image inside the peek, with states | Texto en la imagen | shipped | `PR #140; Peek board keeps it` | code (V12) |
| 64 | Option B · anchored review sheet | Texto en la imagen | dropped | `A shipped; B was the rejected path` | — |
| 65 | Entity chips: Open host · Send email · Translate inline | Texto en la imagen | shipped | `PR #150` | code (V13) |
| 66 | Typography: .body 13 pt via Dynamic Type for recognised text | Texto en la imagen | shipped | `PR #140` | code (V26, wording flag) |
| 67 | Raise chips from 10 to 11 pt | Texto en la imagen | in v4 | `decided 2026-10-17: 11 pt (.subheadline) · Panel (GC-V5-6)` | **→ v4** Panel (GC-V5-6) |
| 68 | iOS parity for text in image | Texto en la imagen | in v4 | `iPhoneSurfaces (GC-V4-18)` | **→ v4** iPhoneSurfaces (GC-V4-18) |

### 2.5 Shipped · pass 2026-10-17

| Item | Idea | Evidence (verbatim) | Status (verbatim) | Where now |
|---|---|---|---|---|
| **GC-15** | Translate text recognised in images | `PeekImageText entity chips: Translate (installed pairs), Open host, Email; never offered for a secret` | shipped · `dropped from the catalog · was already listed as shipped above` | code (V13) |
| **GC-V4-21** | Selection bar slides, stage swaps on the code curves | `ClipCard SharedSelectionGeometry (matchedGeometryEffect), ClipPeek GanchoMotion.replace, PanelResultsView numericText` | shipped · `dropped from the catalog` | code (V24) |
| GC-24 (part) | Status menu header + five recents | `StatusItemController.rebuildMenu: state line with dot, five recents with kind glyph, paste on click · screenshot 21` | shipped · `item kept for ⌘1–5, tiles, count + front app, stack row` | code (V27); rest **→ v4** MenuBarDark (GC-24) |
| GC-V4-3 (part) | Board colour dots and app icon in the rail | `boardChip BoardIdentityMark, sourceAppMenu icon · screenshots 04–09` | shipped · `item kept for the count on the active scope` | code (V28); count **→ v4** Panel (GC-V4-3) |
| GC-V4-7 (part) | Library sidebar dots and Free counters | `LibraryView+Sidebar 3/3 · 2/20, BoardIdentityMark · screenshot 22` | shipped · `item kept for snippet keywords and the Pro meter` | code (V29); rest **→ v4** Library (GC-V4-7) |
| GC-V4-11 (part) | iPhone answer card with sources | `CaptureView.answerCard (Sources, up to four)` | shipped · `item kept for Related by meaning` | code (V30); rest **→ v4** iPhone (GC-V4-11) |
| GC-35 (base) | Live first copy, live Accessibility status, ends in the real panel | `OnboardingView steps 1–3 · screenshots 01–03` | shipped · `item kept for the order, privacy promise and three shortcuts` | code (V31); rest **→ v4** Onboarding (GC-35) |

### 2.6 Discarded in triage · Oct 18, 2026

| Item | Idea | Reason (verbatim) | Came from | Status |
|---|---|---|---|---|
| **GC-V4-20** | Panel arrives from the hook under the 100 ms budget | `Owner chose Skip in Design Picks` | `V4_Gancho_Motion · panel-arrival storyboard` | skip (catalog: `board = V4_Gancho_Archive.dc.html`, `pick = skip`, no note). Do not implement. |

### 2.7 Not on this board, recorded here by instruction — "not adopted"

| Item | Status | Reason (verbatim, from V4_Gancho_Brand) | Where now |
|---|---|---|---|
| Old v4 brand glyph | not adopted | `Not adopted: the 24-grid hook with a separate barb stroke drawn earlier on the v4 Onboarding, Menu bar and iPhone surfaces boards (owner keeps the current icon, Oct 19). Those boards now use this mark.` | Real mark = `Resources/Brand/gancho-mark.svg`, `gancho-mark-green.svg`, `gancho-appicon.svg`; rollout is GC-V7-1 **→ v4** V4_Gancho_Brand (owner decisions 1–2). The three `"paperclip"` spots still exist: `Apps/GanchoMac/OnboardingView.swift:58`, `Apps/GanchoWidgets/RecentClipsWidget.swift:89`, `Apps/GanchoMac/WrappedView.swift:14`. |

### Implementation notes (not UI)

- Board sub-heading, verbatim: `If an idea is not here, it was never proposed.`
- Counter row, verbatim: `68 ideas inventoried` · `31 in v4` · `27 shipped` · `11 dropped` · `0 open`.

## 3. Coverage

| Board element | Covered by |
|---|---|
| Header (GC-43 pill, title, subtitle, date) | GC-43 · context only |
| Counter row + note | context only (count mismatch, see §5) |
| v1 group (13 rows) | §2.1; in-v4 rows → GC-V4-1, GC-09, GC-10, GC-05, GC-08, GC-V4-9 |
| v2 group (13 rows) | §2.2; in-v4 rows → GC-V4-2, GC-V4-14, GC-12, GC-V4-8, GC-V4-5, GC-V4-13, GC-V4-7 |
| v3 group (24 rows across both tables) | §2.3; in-v4 rows → GC-01, GC-04, GC-05…12, GC-11, GC-16, GC-17/19/20/21, GC-23/24/25, GC-26/27/28, GC-V4-15, GC-V4-16, GC-V4-17, GC-33/34, GC-35/36, GC-V4-22…24 |
| External artifacts group (18 rows) | §2.4; in-v4 rows → GC-V4-21/22, GC-V5-6, GC-V4-18 |
| Shipped · pass 2026-10-17 card (7 rows) | §2.5 |
| Discarded in triage card (1 row) | GC-V4-20 (skip) |
| Old brand glyph (not on this board) | §2.7, GC-V7-1 |

No numbered pins on this board.

## 4. Verification of shipped claims

Checked by reading code on `design-v4/fase-0-plan` @ a251a65 (same tree as main @ a251a658). ✅ = found; ⚠️ = partly found or wording no longer accurate.

| V | Claim (row) | Code evidence | Result |
|---|---|---|---|
| V1 | Content-bound titles (#3) | `Packages/GanchoKit/Sources/GanchoAppCore/EnrichmentService.swift:27-28,76-83` (`ContentBoundTitleStoring.updateTitleIfEmptyAndCurrent(… expectedText:)`) | ✅ (`written on-device` peek header is v4 copy, not in code) |
| V2 | PanelStatusFooter hints + ⌘/ cheat-sheet (#5) | `Apps/GanchoMac/PanelStatusFooter.swift:10`; `Apps/GanchoMac/PanelShortcutsOverlay.swift:25-54`; `PanelView.swift:615` (`/`) | ✅ |
| V3 | Three honest iPhone empty states; Library saved-filter empty copy (#10) | `Apps/GanchoiOS/CaptureView.swift:335-363` (query / filter / `Nothing captured yet.`); `Apps/GanchoMac/LibraryView+Browsing.swift:123` (`No clips match this filter.`) | ✅ |
| V4 | Live Activity “Ready to paste” after a sync + device provenance on rows (#11) | `Apps/GanchoWidgets/ClipLiveActivity.swift:33,64`; shown from `Apps/GanchoiOS/IOSAppModel.swift:702` (copy) and `:1243` (local capture) with a sync badge; provenance only in `Apps/GanchoiOS/ClipDetailView.swift:354` | ⚠️ Activity is triggered by a local copy/capture, not by a clip arriving via sync; device name appears in detail, **not on rows** (that is GC-V4-8, still open) |
| V5 | iPhone swipe Board · Pin; GC-40 swipe + context menu (#13, #49) | `Apps/GanchoiOS/CaptureShell.swift:197` (trailing: Delete, Pin), `:205` (leading: Copy, Board), `:217` contextMenu; keyboard `Apps/GanchoKeyboard/KeyboardView.swift:248,256` | ✅ |
| V6 | Action dock + hero peek (#14, #52) | `Apps/GanchoMac/ClipPeek.swift:587-589`; `Apps/GanchoMac/PeekActionButton.swift:20` | ✅ |
| V7 | Convert color dev action (#16) | `Packages/GanchoKit/Sources/GanchoAI/DevActions.swift:22,71`; `Apps/GanchoMac/DevActionIntent.swift:28,42` | ✅ |
| V8 | ContentNormalizer strips utm/fbclid (#17) | `Packages/GanchoKit/Sources/GanchoKit/ContentNormalizer.swift:11-12`; used at `GanchoAppCore/ClipItemFactory.swift:68,79` | ✅ |
| V9 | Delete ⌫ and More ⌘. — “context menu and keys” (#19) | Delete: `PanelView.swift:1321-1367` (context menu), `PanelSelectionContextBar.swift:37`; More: `ClipPeek.swift:569` (`moreActionsToggle`, Dev Actions chip) | ⚠️ No ⌫ or ⌘. key binding found in `Apps/GanchoMac` (no `onKeyPress` for delete/period, none listed in `PanelShortcutsOverlay`). Context menu part ✅, "keys" part not found |
| V10 | GC-02 reason: panel minimum 720 pt; Compact preset | `Apps/GanchoMac/PanelView.swift:300` (`minWidth: 720`); `GanchoDesign/PanelDisplayPreferences.swift:33` (compact 760 × 480) | ✅ |
| V11 | GC-06 capture notice banner (#32) | `GanchoAppCore/PanelCapturePresentation.swift:19-25` (`storageEphemeral, privateMode, denied, screenShare, paused`); `PanelStatusFooter.swift:67`; `PanelView.swift:675` | ✅ |
| V12 | GC-13/14 OCR regions, per-line copy, secret hold-back; Option A (#34, #63) | `Apps/GanchoMac/PeekImageText.swift:13,49` (regions), `:27` (`copiedLine`), `:31,233` (masked, `Contains a secret`); `ClipPeek.swift:127,469` | ✅ |
| V13 | GC-15 Translate; entity chips Open host · Email · Translate, never for a secret (#35, #65, §2.5) | `PeekImageText.swift:405-440` (`Open …`, `Email …`, `Translate`, `Translating…`; doc at :410-411 says none for a secret); availability `ClipPeek+SmartPaste.swift:7-29` | ✅ |
| V14 | GC-18 + Add app menu + built-in exclusions (#38, #61, #62) | `Apps/GanchoMac/DenylistSettingsSection.swift:45-67` (icon, bundle id caption), `:77` `Running app`, `:87` `From Applications…`, `:89` `By bundle identifier…`, `:104-127` live validation, `:159` DisclosureGroup, `:160-167` by category, `:172` `Restore default exclusions`, `:184` count, `:218` toggles | ✅ |
| V15 | ⌘G gallery; GC-03 reason (#29, #55) | `Apps/GanchoMac/PanelGalleryCard.swift:8`; `PanelView.swift:1311`; `PanelShortcutsOverlay.swift:49` | ✅ |
| V16 | GC-22 reason: one Pro toggle, private CloudKit DB | `GanchoSync/CKSyncEngineAdapter.swift:236,474` (`privateCloudDatabase`); `ProSettingsTab.swift:35`; no per-board sync field | ✅ |
| V17 | GC-30 KeyboardView boardRow (#43) | `Apps/GanchoKeyboard/KeyboardView.swift:43,59-75` | ✅ |
| V18 | GC-31 small, medium, control shipped (#44) | `Apps/GanchoWidgets/RecentClipsWidget.swift:16` (`.systemSmall, .systemMedium`); `Apps/GanchoWidgets/SaveClipboardControl.swift:9` | ✅ (large absent, as stated) |
| V19 | GC-32 Live Activity without actions (#45) | `ClipLiveActivity.swift` has no `Button`/intent | ✅ |
| V20 | 36 pt kind tiles, one toolbar, list + peek one material (#51) | `GanchoDesign/Components.swift:141` (`baseTileSize = 36`); `PanelView.swift:718` (`panelToolbar`), `:243` (one surface) | ✅ |
| V21 | PanelAmbientTint toggle (#54) | `PanelView.swift:130,432-464` | ✅ |
| V22 | No remote favicons / link metadata (#57) | `GanchoDesign/Components.swift:83,175`; no `LPMetadataProvider`/`LinkPresentation` in Apps or Packages sources | ✅ |
| V23 | PasteboardStatusRow + bottom bar UIPasteControl (#58) | `Apps/GanchoiOS/PasteboardStatusRow.swift:10`; `CaptureShell.swift:146,304`; `CaptureView.swift:454-462` | ✅ |
| V24 | GC-V4-21 selection slide, stage swap, numericText; symbol bounce (#53, §2.5) | `GanchoDesign/Components.swift:337,452,459` (`SharedSelectionGeometry`, `matchedGeometryEffect`); `ClipPeek.swift:123,147,150` (`GanchoMotion.replace`); `PanelResultsView.swift:169`; `PeekActionButton.swift:67` (`.symbolEffect(.bounce…)`) | ✅ |
| V25 | SettingsView 760 × 500, 210 pt sidebar, seven tabs (#60) | `Apps/GanchoMac/SettingsView.swift:30,113,70` | ✅ |
| V26 | `.body` 13 pt via Dynamic Type for recognised text (#66) | `PeekImageText.swift:275,347` (`.panelFont(.body, …)`) | ⚠️ `.body` is there, but through `panelFont`/panel type scale, not Dynamic Type (`dynamicTypeSize` is a no-op on macOS; replaced in PR #178). Wording is stale; behaviour exists |
| V27 | GC-24 part: state line with dot, five recents with kind glyph, paste on click | `Apps/GanchoMac/StatusItemController.swift:147-185` (`statusDot()`, `recentItems.prefix(5)`, `clip.kind.symbolName`, `pasteRecentItem`) | ✅ |
| V28 | GC-V4-3 part: board dots + app icon in rail | `PanelView.swift:1022` (`BoardIdentityMark`), `:811` (`sourceAppMenu`) | ✅ |
| V29 | GC-V4-7 part: sidebar dots, Free counters 3/3 · 2/20 | `Apps/GanchoMac/LibraryView+Sidebar.swift:109,166-177`; limits `GanchoKit/Pinboards.swift:51` (3), `GanchoKit/SnippetLibrary.swift:7` (20) | ✅ |
| V30 | GC-V4-11 part: iPhone answer card with sources | `Apps/GanchoiOS/CaptureView.swift:125,138` | ✅ (did not count the "up to four" cap) |
| V31 | GC-35 base: live first copy, live Accessibility status, ends in real panel | `Apps/GanchoMac/OnboardingView.swift:22-25` (3 steps), `:63-71` (live recents), `:14,135` (`AXIsProcessTrusted`), `:36-40` (`Open Gancho panel`) | ✅ |
| — | GC-V4-20 (skipped) not in code | `ganchoPanelDidShow` exists (`PanelController.swift:158,518`, used by `PanelView.swift:215`, `ClipPeek.swift:268`) for the existing entrance; no hook-anchored .98 scale | ✅ consistent with skip |

## 5. Owner notes and open points

- Pick note: GC-V4-20 `pick = skip`, no note. GC-V4-22 (named in row 53) has `pick = maybe`, note: `no entiendo la utilidad de esto, pero siento que no es necesario` — row 53's "paste bounce" stays a maybe on V4_Gancho_Motion, not a commitment.
- Owner decision 1 (keep current icon) is what turns the old 24-grid glyph into `not adopted` (§2.7).
- **Count mismatch:** the header says `27 shipped`, the table has 26 `shipped` pills (31 + 26 + 11 = 68). Either the header is off by one or one row (likely GC-31 "small, medium, control shipped", tagged `in v4`) was counted as shipped. Open question; this spec does not pick.
- **⚠️ V4:** row 11 says "after a sync"; code shows the Live Activity after a local copy/capture only. Row 11's "device provenance on rows" is not shipped (it is GC-V4-8, still open).
- **⚠️ V9:** row 19 says "context menu and keys"; no ⌫ / ⌘. bindings found.
- **⚠️ V26:** "via Dynamic Type" is outdated wording; the panel type scale does it.
- Row 8's reason points to onboarding "step 4", which is the v4 proposal (GC-35); the code has 3 steps today.
- Row 1 says GC-V4-1 is "in v4 Panel"; the catalog lists GC-V4-1 on `V4_Gancho_Novel2.dc.html`. Build it from the catalog's board.
