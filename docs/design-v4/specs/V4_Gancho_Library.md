# V4_Gancho_Library — spec

- **Board:** `V4_Gancho_Library.dc.html`
- **Canvas:** 1260 × 1385 (board background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14).
- **Shows:** one macOS window, "v4 · Library window", at 1200 × 892: the shipped two-pane `LibraryView` with a new toolbar (search ⌘F, Grid / List, New board), a scope header with kind chips, sort, Select and sync state, date-grouped cards that carry identity, provenance and hover actions, and a sidebar with saved-filter glyphs and counts, snippet keycaps and a two-ceiling Pro meter. Four numbered notes and a PASS strip below.
- **Light mode only.** The board CSS defines `.dark` variants for chips but no dark frame is drawn.
- **Related Current boards:** `GanchoLibrary_Current` (screenshot 22: sidebar `Boards 3/3`, `All clips 10`, `Pinned`, `Favorites`, `Seed board 1…3`, `Saved filters`, `Library · Snippets 2/20`, snippets with a ↩ glyph, footer `gancho Pro` / `Free limit reached — go unlimited`; main `All clips` / `10 clips` and a flat card grid). `GanchoSnippetEditor_Current` (screenshot 23: snippet editor pane). The v4 board does **not** redraw the snippet editor: it stays as shipped.
- **Catalog IDs realised here (all `pick`, no pick notes):** GC-V4-5, GC-V4-6, GC-V4-7, GC-V4-13. The board text names only GC-V4-6 and GC-V4-7 (PASS strip); GC-V4-5 and GC-V4-13 map by catalog `board` and by the Archive board ("Library search ⌘F · Grid / List · New board … (GC-V4-5)", "Library kind filter chips and Newest sort … (GC-V4-13)").
- **Legacy header IDs GC-17 and GC-28:** see §0 and Coverage. Neither catalog item is realised on this board.

---

## 0. Board header (context only, not UI)

One row, gap 12:
- ID chips: `GC-17` (green `#34C759` / ink `#0B2A14`), `GC-28` (black `#1D1D1F` / white). Chip 22 high, padding 0 9, radius 7, 11 pt mono 800.
- Title (22 pt 800): `Library · search, identity and cards that act`
- Subtitle (13 pt `#5B5B61`, max 860 wide): `v4 of LibraryView (the shipped screenshot is page 1's twin): same split, same sidebar worlds, same click-to-copy; the toolbar gets search and a view toggle, the cards get identity, provenance and hover actions.` (`LibraryView` in mono)
- Right-aligned: `Gancho · macOS · v4 · 1200 × 892`

Frame label (13 pt 800): chip `V4` (green) + `v4 · Library window` + small (12 pt 600 `#5B5B61`) `All clips · grid · 2 of 3 boards on Free`.

**GC-17 / GC-28 clarification.** In the current catalog GC-17 is "Privacy settings with status tiles first" (board `V4_Gancho_Settings`) and GC-28 is "Boards with identity, counts and Free limit" on iPhone (board `V4_Gancho_iPhoneFlows`). The Overview table repeats the same pair for this board (`Library 1260 × 1385 GC-17 GC-28`). Nothing on this board draws Privacy settings, so the GC-17 chip is a stale v3 label. GC-28 is the iPhone sibling of GC-V4-7: its iPhoneFlows note says the Free limit is shown as "2 of 3" before it is hit "(the Mac Library already does)" and lists snippets with their keywords. Treat both chips as context only and build GC-17 and GC-28 from their own boards.

---

## 1. Window "v4 · Library window" — GC-V4-5, GC-V4-6, GC-V4-7, GC-V4-13

Window: 1200 × 892, background `#F5F5F7`, radius 12, border 1 `rgba(0,0,0,.1)`, shadow `0 1 2 rgba(0,0,0,.08), 0 20 46 rgba(0,0,0,.2)`. Below the toolbar: sidebar 252 wide + main pane (flex).

Size note (from pin 1): today the window opens at 900 × 640 with a minimum of 800 × 560. The board uses 1200 × 892 only to show the grid. It does not ask for a new default size.

### 1.1 Toolbar (GC-V4-5)

Height 52, padding 0 16, gap 12, background `#FAFAFB`, bottom border 1 `rgba(0,0,0,.08)`. Left to right:

1. Traffic lights: three 12 pt circles, gap 7 (`#FF5F57`, `#FEBC2E`, `#28C840`). These are system controls.
2. Window title `Library`, 13 pt 700, margin-left 4.
3. Flexible spacer.
4. **Search field** (centred between two equal spacers): 360 × 32, radius 9, background `#FFFFFF`, border 1 `rgba(0,0,0,.1)`, padding 0 10, gap 8.
   - Magnifier glyph 13 pt (stroke 2.4), inherits `#5B5B61`-ish secondary colour.
   - Input 12.5 pt, placeholder `Search clips, boards and snippets`, accessibility label `Search the Library`.
   - Trailing keycap `⌘F` (`.kbd`: 18 high, min-width 18, padding 0 5, radius 5, background `rgba(29,29,31,.08)`, 10.5 pt 700 `#3A3A3F`).
5. Flexible spacer.
6. **View toggle** (segmented, accessibility group label `View`): container padding 2, radius 7, background `rgba(29,29,31,.08)`, gap 1. Segments 20 high, padding 0 10, radius 5, 11.5 pt `#3A3A3F`: `Grid` (selected: background `#FFFFFF`, `#1D1D1F`, 600, shadow `0 1 2 rgba(0,0,0,.14)`) · `List` (unselected).
7. **New board** button: height 30, padding 0 10, radius 10, background `#34C759` (accent), ink `#0B2A14`, 12 pt 700, gap 6, plus glyph 12 pt (stroke 2.6). Label `New board`.

States drawn: Grid selected, search empty. Not drawn: focused search, a search with results or no results, the List layout.

### 1.2 Sidebar (GC-V4-7; structure kept)

Width 252 (matches `idealWidth: 252`), background `#F0F0F3`, right border 1 `rgba(0,0,0,.08)`, padding 12 10 10, row gap 2.

**Section header style** (`.sec`): 10.5 pt 700, uppercase, letter-spacing .06em, `#5B5B61`. Padding 4 8 4 for the first header and 12 8 4 for the rest. An optional count badge sits 6 pt after the label (`#8A8A8F`, 600, no uppercase, no letter-spacing). A trailing `+` icon button (12 pt glyph, stroke 2.4, `#5B5B61`, no chrome) is right-aligned.

**Nav row style** (`.nav`): height 28, padding 0 8, radius 7, gap 8, 13 pt `#1D1D1F`. Leading icon slot 18 wide (icon 14 pt, stroke 2). Trailing count at the right: 11 pt `#5B5B61`, tabular digits. Selected row (`aria-current`): background `#34C759`, text `#0B2A14` 600, count `#0B2A14`, icon `#0B2A14`.

Rows top to bottom:

| # | Element | Icon | Text | Trailing |
|---|---|---|---|---|
| 1 | Header | — | `Boards` | badge `2 / 3`; `+` (a11y `New board`) |
| 2 | Row (selected) | tray | `All clips` | `128` (sample) |
| 3 | Row | pin, `#5B5B61` | `Pinned` | `6` (sample) |
| 4 | Row | star, filled `#FF9F0A` | `Favorites` | `9` (sample) |
| 5 | Row | 12 × 12 swatch, radius 3, `#2E70D1` | `Work` (sample) | `12` |
| 6 | Row | 12 × 12 swatch, radius 3, `#F08C08` | `Brand` (sample) | `9` |
| 7 | Header | — | `Saved filters` | `+` (a11y `New filter`) |
| 8 | Row | filter glyph (circle with three shrinking lines), `#5B5B61` | `Links from Safari, 7 days` (sample) | `23` |
| 9 | Row | filter glyph | `Code · not in a board` (sample) | `5` |
| 10 | Header | — | `Library · Snippets` | badge `2 / 20`; `+` (a11y `New snippet`) |
| 11 | Row | snippet glyph, `#5B5B61` | `Email signature` (sample) | keycap `;sig` |
| 12 | Row | snippet glyph | `Office address` (sample) | keycap `;addr` |
| — | Spacer | | | |
| 13 | Pro card | | see below | |

**Snippet keycap** (`.kn`): height 16, padding 0 4, radius 5, background `rgba(29,29,31,.08)`, 10 pt 600 monospace, `#5B5B61`. The keyword is shown as stored. `;` is part of the sample keyword, not a prefix the UI adds.

**Pro card** (bottom of the sidebar): padding 10 12, radius 10, background `rgba(52,199,89,.12)`, vertical gap 6.
- Title row: 12 pt 700, gap 8. Filled star 13 pt `#FF9F0A`, then `Gancho Pro`.
- Meter: 5 high, radius 3, track `rgba(0,0,0,.08)`. Fill `#34C759` at **66 %**. That matches the fuller ceiling: max(2/3 boards, 2/20 snippets) = 0.667.
- Caption 11 pt `#5B5B61`: `2 of 3 boards · 2 of 20 snippets · Pro removes both ceilings` (numbers are sample values; the ceilings 3 and 20 come from code, see Feasibility).

States drawn: Free tier only, All clips selected. Not drawn: Pro tier (today the badges and footer are hidden for Pro), a ceiling reached, an empty snippets list, a saved filter with 0 matches.

### 1.3 Main pane — scope header (GC-V4-13 chips + sort; header kept)

Main pane padding 14 16, vertical gap 10. One row, gap 10:

1. Scope title `All clips`, 15 pt 800.
2. Count `128 clips` (sample), 12 pt `#5B5B61`.
3. Vertical divider 1 × 16 `rgba(0,0,0,.12)`.
4. **Kind chips** (group, a11y label `Kind`), gap 4. Chip (`.chip`): height 22, radius 999, padding 0 7, background `rgba(29,29,31,.07)`, `#5B5B61`, 11 pt 600, icon 11 pt. Glyph-only chips are 22 × 22.
   - `All`: selected, with a check glyph and label. Selected style: background `#34C759`, ink `#0B2A14`, 700 (dark: `#30D158` / `#04210D`).
   - Glyph-only, unselected, a11y labels and glyph tints: `Links` (`#32ADE6`, link glyph), `Code` (`#5856D6`, `</>`), `Colors` (`#5AC8FA`, palette), `Images` (`#FF9F0A`, picture), `Text` (`#6E6E73`, "A").
5. **Sort** popup (a11y `Sort`): height 22, padding 0 8, border 1 `rgba(0,0,0,.14)`, radius 6, background `#FFFFFF`, 12 pt, label `Newest` plus a 10 pt chevron-down. The pin says the options are `Newest` / `Oldest`.
6. Flexible spacer.
7. **Select** button (`.glass`): height 28, padding 0 10, radius 10, background `#FFFFFF`, border 1 `rgba(0,0,0,.08)`, 12 pt 600 `#1D1D1F`, gap 6, icon 12 pt (dashed square with a check). Label `Select`.
8. **Sync chip** (`.bch`): height 20, padding 0 7, radius 999, background `rgba(29,29,31,.07)`, 11 pt 600 `#3A3A3F`, gap 4, cloud-check glyph 11 pt. Label `Synced 2 min ago` (sample time).

### 1.4 Main pane — date groups and cards (GC-V4-6)

Group header (`.sec`, 10.5 pt, uppercase as styled): `Today · 6`, then `Yesterday · 9` (margin-top 2). Counts are sample values. The frame cuts off after three Yesterday cards.

Grid: 3 equal columns, gap 12 (both axes).

**Card** (`.card`): padding 12, radius 12, background `#FFFFFF`, border 1 `rgba(0,0,0,.08)`, vertical gap 8.
- Header row (gap 8, 13 pt 700): **kind tile** 24 × 24, radius 6, glyph 15 pt (stroke 2.2), then the title (single line, ellipsis).
- Preview block (`.pv`): height 88 (Today cards) or 52 (Yesterday cards), radius 8, background `#F7F7FA`, padding 8 10, 12 pt, line-height 1.45, `#3A3A3F`, clipped.
- Meta line (`.m`): 11 pt `#5B5B61`, gap 8, `<Kind> · <App> · <age>` with optional trailing items right-aligned.
- **Hover actions** (`.acts`): absolute top 8 / right 8, gap 3, opacity .95. Three 24 × 24 buttons, radius 7, background `#F0F0F3`, glyph 12 pt `#3A3A3F`. a11y labels `Copy` · `Pin` · `Add to board`. They are drawn on every card to illustrate the state; pin 3 says hover reveals them.

Kind tile variants (tint = `kindTint`):
- Code / JSON: background `#5856D6` at 16 % (`#5856D629`), glyph `#5856D6`.
- Text: background `#8E8E93` at 16 %, glyph `#4B4B50`.
- Secret: background `rgba(255,59,48,.16)`, lock glyph `#C8231B`.
- Link: gradient 160° `#5BC4F0` → `#32ADE6`, host monogram letter in `#0A2B3A` (e.g. `E`, `G`).
- Colour: the swatch itself, plus an inset 1 pt `rgba(0,0,0,.12)` ring.
- Image: a thumbnail (drawn as sample art: `#52BCCF` with an 18 pt `#F39B3A` circle).

Cards in canvas order (all content is sample data):

| # | Group | Tile | Title | Preview | Meta | Trailing in meta |
|---|---|---|---|---|---|---|
| 1 | Today | code | `Example · Swift` | mono, syntax-coloured: `let greeting = "Hello"` / `print(greeting)` (`let`, `print` `#A33EA3`; `"Hello"` `#2E7D32`) | `Code · Xcode · now` | keycap `⌘C copies` |
| 2 | Today | swatch `#008080` | `Ocean` | full-bleed `#008080` with a bottom-left label `#008080` (mono 11, white on `rgba(0,0,0,.35)`, padding 2 6, radius 5; block padding 6) | `Color · Figma · now` | — |
| 3 | Today | link `E` | `Synthetic link` | host headline `example.com` (15 pt 700 `#1D1D1F`); full URL mono 11, break-all `https://www.example.com:8443/a%2Fb?q=a%26b#section-2`; chip row (margin-top 6, gap 4): board chip `Work` (8 × 8 swatch radius 3 `#2E70D1`), sync chip `Mac + iPhone` (cloud-check 10 pt) | `Link · Safari · 7 min` | — |
| 4 | Today | image thumb | `Synthetic landscape` | image fills the block (sample art, 44 pt circle) | `PNG · 1200 × 800 · Vitrine` | filled pin 10 pt `#6E6E73` (pinned) |
| 5 | Today | secret | `Stripe key · masked` | background `#FFF8F7`, border 1 dashed `rgba(255,59,48,.3)`; mono 700 `sk_live_•••••••••••• 4Q2v`; below (margin-top 6, gap 4, `#7A4B00`): timer glyph 10 pt + `expires in 9:41 · never synced` | `Secret · Terminal · 2 min` | — |
| 6 | Today | text | `Meeting notes` | `Zephyr beta Monday. Marta reviews Kepler dashboards before Friday. Checklist from Ilarion after the call.` | `Text · Portavoz · 2 min` | — |
| 7 | Yesterday | code | `config.json` | mono `{"baseURL": "https://api.example.com"}` (block 52 high) | `JSON · VS Code · 1 d` | — |
| 8 | Yesterday | link `G` | `gancho repo` | host `github.com` (14 pt 700 `#1D1D1F`) + path `/johnny4young/gancho` (mono 11) (block 52 high) | `Link · Arc · 1 d` | — |
| 9 | Yesterday | text | `Release notes draft` | `v0.10.2 — re-seal a stored image or file when copying the same bytes again…` (block 52 high) | `Text · Notes · 1 d` | — |

`.kbd` style for `⌘C copies`: same as the search keycap. Only card 1 carries it, and the board does not say which state it marks (see Feasibility, GC-V4-6, BLOCKED).

States drawn: hover actions (on all cards, illustrative), pinned marker (card 4), masked secret with countdown (card 5). Not drawn: List view, keyboard focus or selection on a card, Select mode, empty scope, load failure, private-mode masking, the hover-action pressed state.

### Implementation notes (not UI)

Pins, quoted verbatim:

1. `Kept: the two-world sidebar (boards with live counts · saved filters · snippets with keywords), click-to-copy cards with the context menu, Free ceilings shown as used/limit before they are hit, the Pro footer that escalates, scope title + count + sync state. Today the window opens at 900 × 640 (minimum 800 × 560, LibraryWindowController); v4 is drawn at 1200 × 892 to show the grid.`
2. `Search in the Library. Today only the panel searches; the Library has no field. The toolbar gains one (ClipSearch scoped by LibraryClipListModel) plus a Grid / List toggle and a visible New board. The scope header gains the panel's kind chips and a Newest / Oldest sort (recovered from the v2 Library): ClipKindFilter already exists, the Library just never offered it.`
3. `Cards say what they are and where they live. Kind tile instead of a bare glyph, link host as a headline, board chips and sync on the card, masked secrets with their expiry; hover reveals Copy · Pin · Board so the menu is no longer the only path. Date groups with counts replace one flat grid.`
4. `Sidebar identity. Boards carry their colour dot (the Library already draws BoardIdentityMark), saved filters get a filter glyph and a count, snippets show their keyword as a keycap, and the Pro card turns into a meter of both ceilings.`

PASS strip: `PASS 2026-10-17` · `Checked against screenshots 22–23`
- `GC-V4-6` `Baseline: cards already show the kind glyph + title and a colour clip shows its swatch; a link still shows only its raw text, with no board chips, date groups or hover actions.`
- `GC-V4-7` `Baseline: the sidebar already has colour dots per board and the 3/3 and 2/20 counters; snippets show a ↩ glyph instead of their keyword and the Pro card only says “Free limit reached — go unlimited”.`

---

## 2. Coverage

| Board element | Covered by |
|---|---|
| Header chips `GC-17`, `GC-28`, title, subtitle, size line | context only. GC-17 is a stale label (Settings item). GC-28 is the iPhone sibling, built on iPhoneFlows |
| Frame label `v4 · Library window` | context only |
| Traffic lights, window title `Library` | kept, no change |
| Toolbar search field + `⌘F` | GC-V4-5 |
| Toolbar `Grid` / `List` toggle | GC-V4-5 |
| Toolbar `New board` button | GC-V4-5 |
| Sidebar `Boards` header + `2 / 3` badge + `+` | kept (shipped `boardLimitBadge`). Spacing `2 / 3` vs shipped `3/3`: GC-V4-7 |
| `All clips`, `Pinned` rows with counts | kept, no change |
| `Favorites`, `Work`, `Brand` rows with identity mark and count | kept (`BoardIdentityMark`, Archive "GC-V4-7 (part)") |
| `Saved filters` header + `+ New filter` | GC-V4-7 (the `+` is new; today the section has no add button) |
| Saved-filter rows with glyph + count | GC-V4-7 |
| `Library · Snippets` header + `2 / 20` + `+` | kept |
| Snippet rows with keyword keycap | GC-V4-7 |
| Pro card meter + caption | GC-V4-7 |
| Scope title + count | kept, no change (count semantics: see GC-V4-13 feasibility) |
| Kind chips | GC-V4-13 |
| `Newest` sort | GC-V4-13 |
| `Select` button | **not in any catalog item** (open question, see GC-V4-13) |
| `Synced 2 min ago` chip | kept (`SyncStatusView`), restyled as a chip |
| Date group headers with counts | GC-V4-6 |
| Card kind tile / host headline / board + sync chips / masked secret + expiry / meta line | GC-V4-6 |
| Card hover actions Copy · Pin · Add to board | GC-V4-6 |
| `⌘C copies` keycap on card 1 | GC-V4-6 (state unclear, BLOCKED) |
| Image meta `PNG · 1200 × 800 · Vitrine` | GC-V4-6 (depends on the metadata from GC-V5-3) |
| Pin 1 | kept list, context |
| Pin 2 | GC-V4-5 + GC-V4-13 |
| Pin 3 | GC-V4-6 |
| Pin 4 | GC-V4-7 |
| PASS strip | context (baselines for GC-V4-6, GC-V4-7) |

---

## 3. Feasibility

### Free ceilings in code (authoritative for every count and meter on this board)

- `Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift:48-59`
  ```swift
  public enum PinLimits {
      public static let freeMaxPins = 15
      public static let freeMaxPinboards = 3
  ```
- `Packages/GanchoKit/Sources/GanchoKit/SnippetLibrary.swift:6-7`
  ```swift
  public enum SnippetLimits {
      public static let freeMaxSnippets = 20
  ```
- Escalation: `Packages/GanchoKit/Sources/GanchoKit/UserTier.swift:55-65` `FreeTierLimits.pressure(boardsUsed:snippetsUsed:isPro:)` takes `left = min(3 - boards, 20 - snippets)`. It returns `.reached` when `left <= 0`, `.almostFull` when `left == 1`, and `.comfortable` otherwise.
- Board count excludes the system Favorites board: `LibraryView+Sidebar.swift:168` (`boards.filter { !$0.isSystem }`) and the gate `GanchoAppCore/BoardsController.swift:113-118`.
- Other Free limits, not on this board: `FreeTierLimits.historyDays = 365 * 86_400`, `historyItems = 10_000`, `freeAITitleTaste = 25` (`UserTier.swift:26-34`).

### GC-V4-5 · Search and view toggle in the Library (UI + feature)

**Changes:** a toolbar with a search field (⌘F), a Grid / List toggle and a visible New board button.

**Code:**
- `Apps/GanchoMac/LibraryWindowController.swift:18-26`: plain `NSWindow`, styleMask `[.titled, .closable, .resizable]`, 900 × 640, min 800 × 560. There is no toolbar today.
- `Apps/GanchoMac/LibraryView.swift:50-58`: `HSplitView` root. Add the toolbar here, for example with SwiftUI `.toolbar` plus `.searchable(placement: .toolbar)`, which gives ⌘F focus natively in a window toolbar. Hosting in `NSHostingController` may need `NSWindow.toolbarStyle = .unified` for the drawn layout. Verify on macOS 15.4 and 26.
- `Packages/GanchoKit/Sources/GanchoAppCore/LibraryClipListModel.swift:5-9`: `LibraryClipScope` has `allClips, pinned, board(UUID), savedFilter(SmartCollectionRule)`. Search is not a scope yet.
- `Packages/GanchoKit/Sources/GanchoKit/ClipSearch.swift:6-60`: `ClipSearchQuery` already supports `boardID`, `pinnedOnly`, `kinds` and `mode`. `ClipSearching.search(_:limit:)` lives in `ClientContract.swift:83-90`.
- `Apps/GanchoMac/AppModel+Library.swift:19-30` `fetchLibraryClips(scope:offset:limit:)`: add a search path.
- New board: `LibraryView+Sidebar.swift:41-47` already sets `boardSheet = .new`. The toolbar button reuses that, through `commitLibraryBoardSheet()` (`LibraryView+Browsing.swift:302`) and `model.createBoard(named:)`, so the Free gate and paywall are kept.

**Exists:** search engine (FTS5 / regex), board and pinned query scoping, the New-board flow and its Free gate, `GanchoMotion`.
**New:** toolbar; a query string on `LibraryClipListModel` (debounced, generation-guarded like `reload`); scope ∩ query mapping (allClips → no filter, pinned → `pinnedOnly`, board → `boardID`, saved filter → rule query plus text); the List layout (not drawn); persisting the Grid / List choice (a per-window preference is not specified); localized strings `Search the Library`, `Search clips, boards and snippets`, `Grid`, `List`, `View` (EN + ES).

**Deps:** GC-V4-13 (the kind chips share the same query); GC-V4-6 (List mode would reuse the card identity; probably `ClipCard` rows).

**Verify:** unit tests in `GanchoAppCoreTests/LibraryClipListModelTests.swift` for query × scope mapping, stale-result suppression and empty results. UI test (extend `Tests/GanchoUITests/VisualLibraryUITests.swift`): ⌘F focuses `library-search-field`, typing narrows `library-clip` cards, and the Grid / List segment switches layout. Snapshot the toolbar against the board.

**BLOCKED:**
1. The placeholder says `Search clips, boards and snippets`. Should search also match board names and snippet titles or keywords, which are sidebar entities, or only clips (snippets are clips with `isSnippet = 1`)? No board-name search exists.
2. The List layout is not drawn. Should it reuse the panel `ClipCard` row (`GanchoDesign/Components.swift:124`)?
3. Should the Grid / List choice persist?

### GC-V4-13 · Kind chips and sort in the Library (UI + feature)

**Changes:** the scope header gains the kind-chip rail and a `Newest` / `Oldest` sort popup.

**Code:**
- `Packages/GanchoKit/Sources/GanchoAppCore/ClipKindFilter.swift:7-32`: cases are **`all, links, code, colors, images, secrets`**. The panel rail renders `ClipKindFilter.allCases` (`Apps/GanchoMac/PanelView.swift:767-781`). The active chip expands to its name, which matches the drawn `All`.
- `Apps/GanchoMac/LibraryView+Browsing.swift:27-33`: header HStack (`scopeTitle`, `"\(clips.count) clips"`, `SyncStatusView`). The chips, sort, Select and sync chip go here.
- Sorting: the All-clips fetch is `GRDBClipboardStore.items(offset:limit:)` (`GRDBClipboardStore.swift:441-457`), ordered `isPinned DESC, COALESCE(lastUsedAt, createdAt) DESC`. `recentForBrowse` (`:479-490`) orders `isPinned DESC, createdAt DESC`. There is no ascending query for any scope (`items(inBoard:)` in `Pinboards.swift:222`, `items(matching:)`).

**Exists:** `ClipKindFilter` with `matches(_:)`, the panel chip component, kind tints (`GanchoTokens.Palette.kindTint`, `Components.swift:104-114`).
**New:** an extracted shared chip-rail view, or a Library copy of it; kind filtering pushed into the query (`ClipSearchQuery.kinds`, or a SQL `kind IN` in the paged fetch, so pagination is not starved by post-filtering); an `Oldest` ordering for every scope; scope-total count.

**Count semantics:** today the header shows `clips.count`, which is the loaded window (`LibraryPager.pageSize = 100`), so 128 clips read "100 clips" until scroll. The board shows `128 clips` equal to the sidebar total. With chips or search active, the header needs a filtered total query.

**Deps:** GC-V4-5 (shared query); GC-V4-6 (date groups must follow the sort direction).

**Verify:** unit tests for kind × scope × sort fetch order (Swift Testing, `GanchoKitTests` store tests); a UI test that the chip `library-kind-links` narrows cards and that `Oldest` reverses the first card. Snapshot.

**BLOCKED:**
1. The board draws `All, Links, Code, Colors, Images, Text`, while the panel's `ClipKindFilter` has **Secrets** and no **Text**. Pin 2 says "the panel's kind chips". Should the Library keep the panel set (code wins) or add a `text` filter and drop Secrets?
2. The `Select` button (multi-select mode in the Library) is drawn but belongs to no catalog item, and the Library has no selection model today (`LibrarySelection` is sidebar-only). Is it in scope, and under which ID?

### GC-V4-6 · Library cards with identity and hover actions (UI + feature)

**Changes:** kind tile, link host headline, board and sync chips, masked secrets with expiry, a `Kind · App · age` meta line, hover Copy · Pin · Add to board, and date groups with counts.

**Code:**
- `Apps/GanchoMac/LibraryClipCard.swift:15-81`: current card. It has a bare SF glyph tinted by kind, the title or kind name, a pin glyph, and a preview 112 high. Masked cards show `•••` for both title and preview. There is no meta line.
- `Apps/GanchoMac/LibraryView+Browsing.swift:59-73`: `LazyVGrid(.adaptive(minimum: 208), spacing: 12)`, flat. At a 1200 window the main pane (≈916 after padding) yields 4 columns, not the 3 drawn. Use a minimum of about 280 or fixed columns if 3 is required.
- `LibraryView+Browsing.swift:140-152` `clipCard`: a `Button` that copies, with `.contextMenu` (`clipMenu`, `:154-179`: Copy text from image, Pin/Unpin, Add to board ▸, Remove from board, Save as snippet, Copy, Delete). Hover actions call the same `copy(_:)`, `model.togglePin` (`AppModel.swift:1741`) and `model.assign(_:toBoard:)` (`:1804`).
- Reusable pieces in `Packages/GanchoKit/Sources/GanchoDesign/Components.swift`:
  - `ClipLinkParts` host parsing (`:84-98`, strips `www.`, local and no network).
  - `ClipCard.linkMonogram` (`:176`).
  - Tile rendering (`leadingTile`, `:345-382`; gradient plus `ContrastingForeground`).
  - `showsExpiryCountdown` (`:165-171`, under 1 h) and `Text(expiresAt, style: .timer)` (`:284-292`).
  - Source app name `SourceApp.fallbackName(forBundleID:)` (`:390-400`).
  - Hover-off-while-scrolling `hoverState` (`:186`) with `listIsScrolling`.
- Date groups: `DateBucket` (`Packages/GanchoKit/Sources/GanchoKit/DateBucket.swift`) and the panel's `ClipSection` headers (`Apps/GanchoMac/PanelResultsView.swift:140-196`, uppercase caption2 + count with `numericText`). Buckets are contiguous only when ordered by `createdAt`, and the Library's All-clips fetch orders pinned first by `lastUsedAt`.
- Board chips per card: `boardIDs(forClip:)` exists (`Pinboards.swift:206`). Calling it per card is an N+1 query, so a batched membership read for a page is new.
- Image meta: `ClipItemFactory.swift:35-41` stores image preview `"Image (<size>)"`. **No width, height or format is in the metadata columns** (`ClipRow.swift:40-46`); the type identifier lives with the binary content.

**Exists:** tile, monogram, host parsing, kind tints, countdown, date buckets, the source-app name, copy / pin / assign actions, thumbnail store (`model.libraryThumbnails`), masking (`ClipSafePresentation`, `SensitiveMasking.maskedPreview` = `"●●●● " + last 4`, `GanchoAI/SensitiveDataDetector.swift:257-263`).
**New:** card layout per the board; meta line with compact age (`now`, `7 min`, `1 d`); date-grouped grid; hover action overlay with labels; batched board membership; per-clip sync chip; stored image dimensions and format.

**Deps:** GC-V4-13 (sort direction drives grouping); GC-V5-3 (image `width × height · format` metadata; its catalog text says "metadata already stored", but the code does not store it); GC-V4-23 (drop on a board, Motion board) shares the Add-to-board path; B-GC-04 is the same image-metadata gap in the panel.

**Verify:** unit tests for the date grouping of a paged Library list and the meta-line formatter (pure; Swift Testing); a UI test that hovering a `library-clip` exposes `library-card-copy`, `library-card-pin` and `library-card-board` and that each acts; a privacy test that a masked card never renders content beyond the stored masked preview. Snapshot the cards against the board.

**BLOCKED:**
1. **Masked secret text.** The board draws `sk_live_•••••••••••• 4Q2v` and the title `Stripe key · masked`. Code stores only `●●●● 4Q2v` (bullets `●`, no prefix) and masks titles of sensitive clips (`LibraryClipCard.swift:20-21`). Showing `sk_live_` would need a new stored, content-derived prefix, which is a privacy change. Use the stored masked preview, and accept a generic title such as the kind name?
2. **Copy on a masked card.** Today `copy(_:)` refuses masked or expired clips (`LibraryView+Browsing.swift:248-252`), so the drawn Copy hover action on the secret card would do nothing. Hide it for masked clips, or allow copy (and with Touch ID?)?
3. **`never synced`.** No code path excludes sensitive clips from CloudKit (`ClipRecordMapper.swift:48-52` maps `isSensitive` and `expiresAt`). Is the claim true, and should it be enforced or the text dropped?
4. **`Mac + iPhone` chip.** `ClipItem` has `sourceDeviceName` (origin) only, with no per-clip sync or device-presence state. What exactly does the chip mean, and from which data?
5. **Pinned clips in date groups.** The board puts the pinned card 4 inside `Today`, while the store orders pinned first (`GRDBClipboardStore.swift:451`) and the panel uses a separate `Pinned` section. Pinned inline, or a `Pinned` group first?
6. **`⌘C copies`** on card 1 implies a keyboard-focused card, but the Library grid has no focus or selection model. Which state shows it?
7. **Link preview rule.** Card 3 shows the host plus the full URL (host repeated); card 8 shows the host plus the path only. The owner rule is that each datum appears once. Use host + path everywhere?
8. Card radius 12 and the drawn `Text` tile glyph `#4B4B50` are not tokens (code: `Radius.md = 10`, tint `#8E8E93`). Code wins unless told otherwise.

### GC-V4-7 · Library sidebar identity and Pro meter (UI)

**Changes:** saved filters get a glyph and a live count (plus a `+` in their header); snippets show their keyword as a keycap instead of ↩; the Pro footer becomes a two-ceiling meter.

**Code:**
- `Apps/GanchoMac/LibraryView+Sidebar.swift`:
  - Saved-filter rows `:50-65`: bare `Text(rule.name)`, with no glyph, no count and no add button in the header.
  - Snippet row `:129-147`: `Image(systemName: "return")` with the keyword only as `.help`.
  - Badges `:166-178`: `"\(userBoardCount)/\(PinLimits.freeMaxPinboards)"` and `"\(snippets.count)/\(SnippetLimits.freeMaxSnippets)"`, hidden for Pro.
  - Footer `:183-219`: `gancho Pro` with a star in the accent colour plus a subtitle from `FreeTierLimits.pressure`, one of `Unlimited boards & snippets`, `Almost full — Pro unlocks unlimited` or `Free limit reached — go unlimited`. a11y id `library-pro`.
- Board marks: `BoardIdentityMark` (`GanchoDesign/BoardIdentityEditor.swift:7-37`) draws a **circle** for coloured boards and the `star` symbol in `Palette.warning` for Favorites. The board draws 12 × 12 rounded squares. Pin 4 says "already draws BoardIdentityMark", so keep the code shape.
- Saved-filter count: `LibraryClipListModel.loadFilter` (`LibraryClipListModel.swift:117-134`) fetches with a limit of 500 or 100, and there is no `count(matching:)` in the store (only `count()` and `count(inBoard:)`).

**Exists:** board identity, live board / all / pinned counts, both Free badges, the pressure function, the paywall trigger `.freeLimitReached`, and the board colours `#2E70D1` / `#F08C08` as `BoardIdentityColor.blue` / `.orange` (`BoardColors.swift:8-9`).
**New:**
- Saved-filter glyph (e.g. `line.3.horizontal.decrease.circle`).
- `count(matching: SmartCollectionRule)` in the store, plus refresh on store changes.
- `+ New filter` in the header (opens `SavedFilterEditor`; today filters are created from the panel's save-filter control).
- Keyword keycap view.
- Meter view: fill = `max(userBoards / PinLimits.freeMaxPinboards, snippets / SnippetLimits.freeMaxSnippets)` clamped to 0…1; caption built from the same constants, never literals.
- New strings in EN + ES.

**Deps:** GC-28 (iPhone shows the same `2 of 3` and keywords; share the meter and caption formatter in `GanchoAppCore` so both platforms read the same constants).

**Verify:** unit test for the meter fraction and caption across comfortable / almostFull / reached, using `PinLimits` and `SnippetLimits` (no hard-coded 3 / 20, per the swift-preflight rule). UI test: a seeded Free store shows `library-pro-meter`, snippet rows expose the keyword keycap, and saved-filter rows show a count. Snapshot the sidebar.

**BLOCKED:**
1. **Escalation vs the drawn caption.** At 2 of 3 boards, `pressure` returns `.almostFull` (one slot left), so the shipped footer would read `Almost full — Pro unlocks unlimited`. The board draws the neutral `… · Pro removes both ceilings`, yet pin 1 keeps "the Pro footer that escalates". Should the meter caption escalate (and with which strings and colour per state), or always read `N of 3 boards · N of 20 snippets`?
2. **Three ceilings, not two.** Free also caps pins at `PinLimits.freeMaxPins = 15`, and the sidebar shows `Pinned 6`. "Pro removes both ceilings" omits pins. Add pins to the meter, or keep boards + snippets only?
3. Brand casing: the board says `Gancho Pro`, while code renders `gancho Pro` (verbatim) and draws the star in the accent green, not `#FF9F0A`. Check against V4_Gancho_Brand (the source of truth per owner decision 1).
4. Badge spacing: the board shows `2 / 3`, code shows `3/3`. Cosmetic; confirm.
5. The sample saved filters (`Links from Safari, 7 days`, `Code · not in a board`) cannot be built today: `SmartCollectionRule` (`SmartCollections.swift:8-31`) has no date window and no "not in a board" predicate. The names are free text, so they display fine. Only flag this if those rules are meant literally.

### Related IDs shown on this board (built elsewhere)

- **GC-17** (Settings): not drawn here; stale header chip.
- **GC-28** (iPhoneFlows): the iPhone counterpart of the Free counts and snippet keywords; it reuses the GC-V4-7 formatter.
- **GC-V5-3 / B-GC-04**: the image metadata line needs stored dimensions and format.
- **GC-V4-23** (Motion): drop onto Library sidebar board rows.
- **GC-V6-7** (Novel2): a future `Suggested` snippets group in this sidebar; not drawn here.

---

## 4. Owner notes

- Pick notes: none (GC-V4-5, GC-V4-6, GC-V4-7, GC-V4-13, GC-17, GC-28 are all `pick` with empty notes).
- No comment thread on this board.
- General owner rules that apply here: "compare every proposal with the current UI and only propose what beats it… Code wins over v2 boards and site screenshots" (hence the code-wins calls on the board-mark shape, the radius and the kind-chip set, each still listed as a question), and "each piece of data appears once per screen" (relevant to the card 3 host + full URL, and to the header sync chip vs the per-card sync chip).
