# V4_Gancho_iPad — spec

- **Board:** `V4_Gancho_iPad.dc.html`
- **Canvas:** 1400 × 1140 (board background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14).
- **Shows:** one iPad frame, "v4 · Split view, link selected": the three-column `IPadSplitView` with sidebar identity (boards, types, apps with colour/tint/icon and counts), the pasteboard card docked at the sidebar bottom, a content column with its own toolbar and date headers with counts, and the v4 phone detail at column width with a drag-out hint. Four numbered notes below the frame.
- **Device frame:** `Gancho · iPadOS 26 · v4 · 1150 × 800 (13-inch at 0.85)`. All sizes below are as drawn on the board. The board states a 0.85 scale, so device pt ≈ drawn ÷ 0.85. Read column widths as proportions: the system `NavigationSplitView` sets the real widths.
- **Light mode only.** No dark variant is drawn.
- **Related Current boards:** `GanchoPhone_Current` (iPhone capture screen: board rail `✓ All clips` · `Favorites` · `+ New board…`, `Sensed, not read` / `Pasteboard is empty` row with `i`, `Today` section, `•••` menu with `Copy` / `Pin` / `Delete`, `Paste` control). No iPad Current board exists. The baseline is the code in `Apps/GanchoiOS/IPadSplitView.swift`.
- **Catalog IDs on this board:** GC-33 (pick), GC-34 (pick). No pick notes.

---

## 0. Board header (context only, not UI)

Left to right, one row, gap 12:
- ID chips: `GC-33` (green chip `#34C759` / ink `#0B2A14`), `GC-34` (black chip `#1D1D1F` / white). Chip: 22 high, padding 0 9, radius 7, 11 pt mono 800.
- Title (22 pt 800): `iPad · three columns, identity in the sidebar, the clip that leaves the app`
- Subtitle (13 pt `#5B5B61`, max 860 wide): `v4 of IPadSplitView: same split, same model, same shortcuts; boards, types and apps get identity and counts, the pasteboard card docks in the sidebar, the detail becomes the phone's v4 detail and cards can be dragged into the app beside Gancho.` (`IPadSplitView` in mono)
- Right-aligned: `Gancho · iPadOS 26 · v4 · 1150 × 800 (13-inch at 0.85)`

Frame label above the device (13 pt 800): chip `GC-33` (green) + `v4 · Split view, link selected` + small (12 pt 600 `#5B5B61`) `Boards · Types · Apps · docked pasteboard card`.

---

## 1. Frame "v4 · Split view, link selected" — realises GC-33 (sidebar, content column) and GC-34 (drag-out)

Device: 1150 × 800, radius 28, border 1 `rgba(29,29,31,.16)`, shadow `0 20 50 rgba(0,0,0,.18)`, background `#fff`.

### 1.0 Status bar (context only)
Height 26, padding 0 22, 12 pt 700, background `#F2F2F7`. Left `9:41`. Right: cloud glyph 12 + battery outline 22 × 10 (border 1.5, radius 3).

### 1.1 Sidebar column (GC-33)
Width 260, background `#F2F2F7` (system grouped background), right border 1 `rgba(0,0,0,.1)`, padding 8 × 10, row gap 2.

Top to bottom:

1. **Title** `Gancho`: 26 pt 800, letter-spacing −0.02em, padding 6 6 8. Kept, already `.navigationTitle("Gancho")`.
2. **Section header** `Boards`. Section header style for all three sections: 11 pt 700, uppercase, letter-spacing .06em, `#5B5B61`. Padding is 4 × 10 for the first header and 10 10 4 for later ones.
3. **Sidebar row style** (all rows): height 34, padding 0 10, radius 8, gap 10, label 13.5 pt (ellipsis on overflow). Trailing count: 12 pt `#5B5B61`, tabular figures.
   - `All clips`: **selected**, background `rgba(52,199,89,.16)` (accent at 16%), label weight 600. Icon is an inbox tray, 15, `#5B5B61`. Count `128` (sample).
   - `Favorites`: filled star, 15, `#FF9F0A` (warning/favorite hue). Count `9` (sample).
   - `Work`: 11 × 11 rounded square, radius 3, `#2E70D1`. Count `12` (sample).
   - `Brand`: 11 × 11 rounded square, radius 3, `#F08C08`. Count `9` (sample).
   - `New board…`: plus glyph 14 (stroke 2.4) in accent ink `#1F7A3A`. Trailing `2 of 3` in the count style (Free limit, sample).
4. **Section header** `Types`.
   - `All types`: 2 × 2 grid glyph, 14, `#5B5B61`. **No count.**
   - `Text`: "A" glyph 14, `#6E6E73`, count `61` (sample).
   - `Link`: link glyph 14, `#32ADE6`, count `40` (sample).
   - `Code`: `</>` glyph 14, `#5856D6`, count `14` (sample).
   - `Image`: photo glyph 14, `#FF9F0A`, count `9` (sample).
   - `Color`: palette glyph 14, `#5AC8FA`, count `3` (sample).
   - `Secret`: lock glyph 14, `#FF3B30`, count `1` (sample).
   - Only these six kinds and `All types` are drawn.
5. **Section header** `Apps`.
   - `Safari`: 14 × 14 app icon, radius 4 (sample gradient `#4FC3F7 → #1565C0`), count `40` (sample).
   - `Xcode`: 14 × 14 app icon, radius 4 (sample `#1D1D1F`), count `14` (sample).
   - No `All apps` row is drawn.
6. Flexible spacer.
7. **Docked pasteboard card** (bottom of the sidebar): padding 10, radius 12, background `#fff`, border 1 `rgba(0,0,0,.06)`, gap 8, one row:
   - Kind tile 36 × 36, radius 8. Background is the link tint at 16% (`#32ADE629`) and the link glyph (15) is `#32ADE6`.
   - Two text lines, 12 pt, line-height 1.3: bold `Link on your clipboard`, then `Sensed, not read` in `#5B5B61`.
   - Paste button 80 × 36, radius 10, 14 pt 600, background `#34C759`, ink `#0B2A14`, clipboard glyph 14 + `Paste`.
   - Drawn state: link sensed. Empty, Saved, save-note and other sensed types are not drawn (see Feasibility GC-33).
   - No selection highlight on any `Types` or `Apps` row.

### 1.2 Content column (GC-33)
Width 420, right border 1 `rgba(0,0,0,.1)`.

**Column toolbar** (height 52, padding 0 14, gap 6, bottom border 1 `rgba(0,0,0,.08)`), left to right:
- `History`: 20 pt 800.
- `128 clips`: 12 pt `#5B5B61`, no wrap (sample count).
- Search field: flexible width, height 34, radius 10, background `rgba(120,120,128,.12)`, padding 0 10, gap 8. Magnifier 14 (stroke 2.4) `#5B5B61`, placeholder `Search` (14 pt, placeholder colour `#8A8A8F`), accessibility label `Search your clipboard`.
- `Select` button: height 32, radius 10, padding 0 10, background `#fff`, border 1 `rgba(0,0,0,.08)`, 12 pt 600 `#1D1D1F`. Glyph 13 is a dashed rounded square with a check.
- Icon button 32 × 32, same style. Stacked-boards glyph 14, accessibility label `Boards`.
- Icon button 32 × 32, same style. Gear glyph 14, accessibility label `Settings`.
- No Paste control in this toolbar.

**List** (background `#fff`):
- Date header style: 13 pt uppercase, letter-spacing .02em, `#5B5B61`, padding 10 16 6, background `#F8F8FA`. Text is bucket + ` · ` + count.
- Row style (`ClipCard`): min-height 56, padding 8 × 14, gap 12, bottom hairline 1 `rgba(60,60,67,.12)`. Tile 36 × 36, radius 8. Title 15 pt 600 (ellipsis). Preview 13 pt `#5B5B61` (ellipsis; mono for code/colour/JSON). Trailing meta column: source line 11 pt `#6E6E73`, then markers row (gap 4).
- Selected row: background `rgba(52,199,89,.14)`. No leading bar.

Rows in order (all sample data):
1. Header `Today · 5`
2. Code tile (bg `#5856D629`, glyph `#5856D6`). Title `Example · Swift`, preview (mono) `let greeting = "Hello"`, meta `Mac · Xcode · now`.
3. Colour tile (solid `#008080`, inset 1 `rgba(0,0,0,.12)`). Title `Ocean`, preview (mono) `#008080`, meta `Mac · Figma · now`.
4. **Selected.** Link tile with a favicon letter `E` (gradient 160° `#5BC4F0 → #32ADE6`, letter `#0A2B3A`). Title `Synthetic link`, preview `https://www.example.com:8443/a%2Fb?q=a%26b#section-2`, meta `Safari · 7 min`.
5. Image thumbnail tile (sample art `#52BCCF` + 18 pt circle `#F39B3A`). Title `Synthetic landscape`, preview `PNG · 1200 × 800`, meta `Mac · Vitrine · now`. Marker: filled pin glyph 11, `#6E6E73` (pinned).
6. Secret tile (bg `rgba(255,59,48,.16)`, lock glyph `#C8231B`). Title `Stripe key · masked`, preview `sk_live_•••••••••• 4Q2v`, meta `Terminal · 2 min`. Marker: expiry pill, height 18, padding 0 6, radius 999, bg `rgba(255,159,10,.18)`, ink `#7A4B00`, 10.5 pt 600, timer glyph 9 + `9:41` (sample countdown).
7. Header `Yesterday · 9`
8. Link tile with letter `G` (same gradient). Title `gancho repo`, preview `https://github.com/johnny4young/gancho`, meta `Arc · 1 d`.
9. Code tile. Title `config.json`, preview (mono) `{"baseURL": "https://api.example.com"}`, meta `VS Code · 1 d`.
10. **Keyboard legend** (under the list): padding 8 × 16, 11 pt `#5B5B61`, gap 10. Key chips are 18 high, min-width 18, padding 0 5, radius 5, bg `rgba(29,29,31,.08)`, 10.5 pt 700 `#3A3A3F`. Content: `⌘F` `search` · `⌘⏎` `copy` · `⌘1–9` `copy nth` · `↑↓` `select` (lowercase as drawn).

### 1.3 Detail column (GC-34 drag-out; layout = GC-27 phone detail)
Remaining width (≈ 468), background `#F2F2F7`. Top to bottom:

1. **Meta chips** (padding 12 16 0, gap 6, wrap):
   - Kind pill `Link`: height 20, padding 0 8, radius 999, bg `rgba(50,173,230,.16)`, ink `#0B5C80`, 11 pt 700, link glyph 11.
   - `Safari`: chip, height 22, 11 pt 500 `#3A3A3F`, bg `rgba(120,120,128,.16)`, dashed app-square glyph 11.
   - `7 min`: same chip, clock glyph 11.
   - `Synced from Mac`: same chip with bg `rgba(52,199,89,.14)`, ink `#1F7A3A`, cloud-check glyph 11.
2. **Title row** (padding 8 16 4, gap 8): `Synthetic link` 20 pt 800. Then an icon button, 14 glyph, `#1F7A3A`, accessibility label `Edit title` (the glyph is a wand with sparks).
3. **Hero card** (the drag source): margin 4 16 0, padding 12 × 14, radius 14, bg `#fff`, border 1 `rgba(0,0,0,.06)`. A 4-wide `#32ADE6` bar runs down the leading edge. Host `example.com` 22 pt 800. URL (mono 12 pt `#5B5B61`, line-height 1.45, breaks anywhere) `https://www.example.com:8443/a%2Fb?q=a%26b#section-2`.
4. **Primary Copy** (padding 10 16 0): full width, height 46, radius 12, bg `#34C759`, ink `#0B2A14`, 16 pt 700, gap 8. Clipboard glyph 18 + `Copy` + key chip `⌘⏎` (chip bg `rgba(0,0,0,.14)`, ink inherits).
5. **Action row** (padding 8 16 8, gap 10). Four equal buttons, each a 46-high box (radius 10, bg `rgba(120,120,128,.16)`, glyph 20 `#1D1D1F`) above a 12 pt `#5B5B61` label, gap 6: `Share` · `Pin` · `Board` · `Snippet`.
6. **Header** `Smart actions` (13 pt uppercase `#5B5B61`, padding-top 6). Trailing `on-device` (not uppercase, `#5B5B61`).
7. **Smart action chips** (padding 6 16 0, gap 6, wrap; chip height 30, 13 pt, bg `rgba(120,120,128,.16)`): `Parse URL`, `Markdown link`, `Transform ▾`. Then three green chips (bg `rgba(52,199,89,.14)`, ink `#1F7A3A`, sparkle glyph 11): `Summarize`, `Fix grammar`, `Translate ▾`.
8. **Header** `Boards` (padding-top 10).
9. **Board chips** (padding 6 16 0, gap 6): `Work` with a 10 × 10 radius-3 `#2E70D1` square. Then `Add` with a plus glyph 12 and ink `#1F7A3A`.
10. Flexible spacer.
11. **Drag hint** (margin 0 16 14, padding 10 × 12, radius 12, **dashed** border 1.5 `rgba(0,0,0,.18)`, 12 pt `#5B5B61`, gap 8, arrow-right glyph 16): `Drag the card into Notes or Mail to paste it there — text + URL, images as PNG. Secrets never drag.`

States not drawn: dragging/lifted card, drop accepted, masked clip (no drag), empty detail.

### Implementation notes (not UI)
Numbered notes under the frame (4 columns), verbatim:

1. `Kept: the three-column NavigationSplitView (IPadSplitView), sidebar sections Boards / Types / Apps, the history search, the Paste control, and the hardware shortcuts the code already binds (⌘F, ⌘⏎, ⌘1–9, ↑↓).`
2. `Sidebar identity (GC-33): boards show their colour and live count and the Free limit (“2 of 3”); types take the kind tints; apps show their icon and count. The “Sensed, not read” card docks at the sidebar bottom with its own Paste control, visible in every board — the content column no longer spends a row on it.`
3. `Content column: search moves into the column toolbar next to Select; date headers carry counts; the keyboard legend sits under the list. Rows are the same ClipCard with device provenance.`
4. `Detail: the v4 phone detail at column width (no 680 pt centring needed). Drag-out (GC-34) is new: a .draggable on the card hands text + URL or a PNG to the other Split View app; masked clips are not drag sources, the same rule the Mac's clipDragSource applies.`

---

## 2. Coverage

| Board element | ID(s) | Notes |
|---|---|---|
| Board header (IDs, title, subtitle, size line) | context only | — |
| Frame label "v4 · Split view, link selected" | context only | — |
| Status bar | context only | system |
| Sidebar title `Gancho` | kept, no change | `IPadSplitView.swift:51` |
| Boards section (All clips, Favorites, Work, Brand with colour + counts) | GC-33 | counts/identity new on iPad; shared with GC-28 (iPhone boards) |
| `New board…` + `2 of 3` | GC-33 | new row on iPad; Free limit pattern from GC-28 / Mac Library |
| Types section with tints + counts | GC-33 | per-kind counts are new |
| Apps section with icon + count | GC-33 | count exists; icon is BLOCKED |
| Docked pasteboard card + Paste | GC-33 | moves `PasteboardSection` and the pad Paste control; status strings shared with GC-26 |
| Content toolbar (History, count, inline search, Select, Boards, Settings) | GC-33 | `Select` has no catalog item (see Feasibility) |
| Date headers with counts | GC-33 (iPad) / GC-V4-8 (counts pattern) | iPad list is flat today |
| Rows with device provenance | GC-V4-8 | context on this board; built by GC-V4-8 |
| Secret row mask + expiry pill | GC-V4-9 | context on this board; built by GC-V4-9 |
| Keyboard legend | GC-33 | shortcuts exist; legend is new |
| Detail chips, title, hero, Copy ⌘⏎, action row, Smart actions, Boards | GC-27 | "the v4 phone detail at column width"; iPad only drops the 680 pt cap |
| Hero card as drag source | GC-34 | new |
| Drag hint (dashed) | GC-34 | new copy |
| Pin 1 (Kept) | kept, no change | — |
| Pin 2 (Sidebar identity) | GC-33 | — |
| Pin 3 (Content column) | GC-33, GC-V4-8 | — |
| Pin 4 (Detail + drag-out) | GC-27, GC-34 | — |

---

## 3. Feasibility

### GC-33 · iPad sidebar identity and docked pasteboard (UI + small store feature)

**What changes**
- Sidebar, `Apps/GanchoiOS/IPadSplitView.swift:18-56`:
  - Board rows use `BoardIdentityMark` instead of the generic `sfSymbol`. Selection becomes a highlighted row instead of the trailing checkmark (`boardRow`, `:168-187`).
  - Add live counts and a `New board…` row with `%lld of %lld` on Free only.
  - Type rows get the kind tint and a count.
  - App rows get an icon and keep their count (`sourceAppRow`, `:189-214`).
- Docked card: move `PasteboardSection()` out of the content list (`:60`) into a pinned bottom area of the sidebar (`.safeAreaInset(edge: .bottom)` on the sidebar `List`). The card shows the sensed title + `Sensed, not read` and its own `PasteControlView` at 80 × 36 with a rounded-rect corner style (today it is a capsule, `CaptureView.swift:457`).
- Remove the pad Paste item from `CaptureToolbar`: `CaptureShell.swift:154-157`.
- Content column:
  - Inline search field + `Select` + Boards + Settings in the column toolbar. Today the Boards item is at `CaptureShell.swift:158-166` and Settings is topBarLeading at `:167-174`.
  - `128 clips` beside the title.
  - Date sections with counts, reusing `model.sections` / `isGroupedView` like `CaptureView.swift:44-57`. The iPad list is flat today (`IPadSplitView.swift:61-63`).
  - Keyboard legend row at the end of the list.

**Exists in code**
- The `NavigationSplitView` with Boards/Types/Apps sections, `kindFilter` / `selectedBoardID` / `selectedSourceAppBundleID` bindings, and ⌘F / ⌘⏎ / ⌘1–9 (`IPadSplitView.swift:134-147`) with ↑↓ from List selection.
- `BoardIdentityMark` (`Packages/GanchoKit/Sources/GanchoDesign/BoardIdentityEditor.swift:7`).
- Board counts: `IOSAppModel.clipCount()` / `clipCount(in:)` (`IOSAppModel.swift:429-438`), already used by `BoardsHomeView.reload()` (`BoardsHomeView.swift:291-297`).
- `PinLimits.freeMaxPinboards` = 3 (`Packages/GanchoKit/Sources/GanchoKit/Pinboards.swift:51`) and `model.tier`. The Mac badge pattern is in `LibraryView+Sidebar.swift:170-173`.
- Kind tints: `GanchoTokens.Palette.kindTint(for:)` (`GanchoDesign/Components.swift:103-113`).
- App counts: `ClipSourceApp.clipCount`, already shown.
- `PasteboardStatusRow` sense titles (`PasteboardStatusRow.swift:140-146`) and `PasteControlView` (`CaptureView.swift:446`).
- Date sections: `ClipSectionGroup` (`HistoryListViewModel.swift:24`, `IOSAppModel.swift:35`).

**New**
- Per-kind counts: no store API. `ClientContract` only has `count()` and `count(inBoard:)` (`ClientContract.swift:67`, `:259`). This needs a content-free aggregate (`GROUP BY kind` over non-archived rows) in the store + `ClipListCore` / `IOSAppModel`.
- `New board…` row in the sidebar (today creation lives in `BoardsHomeView` / rail).
- Docked card layout.
- Inline column search: `.searchable(placement: .toolbar)` or a custom field bound to `searchFocused`, so ⌘F keeps working.
- `Select` (multi-select): no iOS implementation exists.
- Counted section headers.
- Keyboard legend.
- New String Catalog keys, EN + ES: `%lld of %lld`, `%lld clips`, `Select`, `Search`, `search`, `copy`, `copy nth`, `select`, and the `<bucket> · %lld` header format. `All types`, `Types`, `Apps`, `Boards`, `New board…`, `History`, `All clips`, `Sensed, not read` and `Link on your clipboard` already exist in `Apps/GanchoiOS/Localizable.xcstrings`.
- Accessibility ids (kebab-case), proposed: `sidebar-board-row`, `sidebar-type-row`, `sidebar-pasteboard-card`, `history-keyboard-legend`. Keep `paste-control`, `pasteboard-status-title`, `boards-home-open` and `source-app-*` intact (existing tests use them: `Tests/GanchoiOSUITests/SourceAppFilterUITests.swift`, `CaptureFlowUITests.swift`).

**Dependencies**
- GC-28: board identity, counts and Free-limit wording on iPhone. Share one helper.
- GC-26: pasteboard status card strings and states.
- GC-V4-8: row provenance + counts.
- GC-V4-9: secret expiry pill.
- GC-27: detail.
- SY-V4-3: dark ink `#0B2A14` on green. Today `PasteControlView` uses `.black`, `CaptureView.swift:460`.

**Verify**
- Unit (Swift Testing, `Packages/GanchoKit/Tests/GanchoKitTests`): the per-kind count query excludes archived rows and matches `count()` when summed.
- Unit: the Free badge is hidden on Pro and shows `n of 3` on Free.
- UI (XCTest, `Tests/GanchoiOSUITests`, run on an iPad simulator via `make test-ui-ios IOS_SIM_DEST=…`):
  - `paste-control` exists inside the sidebar and not in the content list.
  - Tapping a type row filters the list.
  - ⌘F focuses the column search.
  - Selection shows the detail without the 680 cap.
- Snapshot at 1150 × 800-equivalent compared to this board.

**BLOCKED**
1. App icons: iOS has no public API to resolve another app's icon from a bundle id. `SourceApp.icon(forBundleID:)` is AppKit-only (`GanchoDesign/SourceApp.swift:45`), and Mac-captured bundle ids are not installed on iPad. What should the `Apps` rows show: a generic glyph, a letter tile, or a bundled icon set for known apps?
2. Types list: the board draws six types (Text, Link, Code, Image, Color, Secret). The code lists all 17 `ClipContentKind.allCases` (`IPadSplitView.swift:39`). Does the sidebar show only these six? If so, do they group kinds (e.g. Code = code + json + uuid, Secret = secret + jwt + creditCard, as `kindTint` groups them)? `kindFilter` is a single kind today, so grouping needs a filter change.
3. `All apps` row: drawn without it, but the code has it (`IPadSplitView.swift:46`). How does the user clear an app filter?
4. Selection state across sections: board, type and app filters are independent and can all be active, but only `All clips` is highlighted. `All types` is the active type and is not highlighted. How should an active type/app filter look?
5. Docked Paste in narrow layouts: in iPad portrait, Slide Over and narrow Stage Manager windows, `NavigationSplitView` hides or collapses the sidebar. The code sets no `columnVisibility`. If Paste lives only in the sidebar, it disappears there. Should the toolbar Paste stay when the sidebar is hidden or `horizontalSizeClass == .compact`?
6. `Select`: multi-select on iPad has no catalog item and no code. Is it in scope for GC-33, or should it be dropped from the toolbar?
7. Section counts: the history is paginated (`loadMoreIfNeeded`), so `Today · 5` from loaded rows can undercount. Is a store count per bucket required?
8. Pinned clip inside `Today`: the board shows the pinned `Synthetic landscape` inside `Today`. The code groups `Pinned` first (`CaptureView.swift:47`). Code wins unless decided otherwise.
9. Board mark shape: the board draws an 11 pt rounded square. `BoardIdentityMark` is a circle on Mac and iPhone. This is shared UI; proposal: keep `BoardIdentityMark`.
10. Docked card states: only "Link on your clipboard / Sensed, not read" is drawn. Confirm that the card reuses all `PasteboardStatusRow` states (empty, Saved, save notes, info popover).

### GC-34 · Drag a clip into another app on iPad (feature)

**What changes**
- Make the detail hero card a drag source when `ClipDragPayload.isDraggable(item)`.
- Link clips advertise `public.url` + `public.utf8-plain-text`, other text kinds plain text, and images `public.png`. Masked/sensitive clips advertise nothing.
- Bytes load lazily through `ClipSafeDelivery.load` (store-authorized, expiry-checked) when the drop target asks.
- Add the dashed hint under the detail. Hide it when the clip cannot drag.

**Exists in code**
- `ClipDragPayload` (pure, platform-neutral, `Packages/GanchoKit/Sources/GanchoAppCore/ClipDragPayload.swift:13-91`). The iOS target already links `GanchoAppCore` (`project.yml` GanchoiOS deps). Tests in `Packages/GanchoKit/Tests/GanchoAppCoreTests/ClipDragPayloadTests.swift`.
- `ClipSafeDelivery.load` / `isEligible` (`Packages/GanchoKit/Sources/GanchoKit/ClipSafeDelivery.swift:11-37`).
- `ClipShareItem: Transferable` with lazy PNG + plain-text representations and a cross-platform `pngData` (`Packages/GanchoKit/Sources/GanchoDesign/ClipShareItem.swift:15-85`). iOS builds it via `IOSAppModel.shareItem(for:)` (`IOSAppModel.swift:668-673`).
- Mac reference: `ClipDragSource` / `dragProvider(for:)` (`Apps/GanchoMac/ClipDragProvider.swift:26-91`, `:172-240`). It is AppKit-bound (`NSBitmapImageRep`, panel hooks), so it is not reusable as is.
- Split View is supported (all four iPad orientations, `project.yml:310-316`).

**New**
- iOS drag source on the hero card. Option A: `.draggable(model.shareItem(for:))`, which needs a new `.url` representation in `ClipShareItem` for link clips (today it offers only PNG/plain text). Option B: an iOS `.onDrag` building an `NSItemProvider` from `ClipDragPayload.representations`.
- Drop `.fileURL` on iOS. Mac file paths are meaningless on iPad, and `representations` returns `[.fileURL, .plainText]` for `fileReference`.
- Optional: drag-delivered usage bookkeeping like the Mac's `noteDragOutDelivered` (`AppModel.swift:1056`).
- Hint string (EN + ES) and an a11y id, e.g. `detail-drag-hint`.
- A drag-preview a11y label naming the kind, never the content.
- Privacy: no content in logs or errors. The Mac's content-free `CocoaError(.fileReadUnknown)` pattern applies.

**Dependencies**
- GC-27: the hero card it attaches to.
- GC-33: removing the 680 pt cap at `IPadSplitView.swift:99-102`.

**Verify**
- Unit: extend `ClipDragPayloadTests` / `GanchoDesignTests` with:
  - the URL representation for `.url` clips;
  - no representations for masked kinds and `isSensitive`;
  - no file URL on iOS.
- UI: XCUITest cannot drop into another app. Assert that the hero card exists with its id and that the hint is absent on a masked clip (seed via `IOSAppModel+UITestSeeds`).
- Manual on an iPad in Split View:
  - Notes receives the text + URL.
  - Mail receives the PNG.
  - A secret does not lift.
  - An expired clip yields no data.

**BLOCKED**
1. Scope of drag sources: the board names only "the card" (the detail hero). The Mac also drags list rows. Should content-column rows be drag sources on iPad?
2. Hint persistence: is the dashed `Drag the card…` box permanent, or a dismissible / one-time tip? Its sample app names (`Notes or Mail`) are fixed copy.

### Related IDs shown on this board (built elsewhere)
- **GC-27** (V4_Gancho_iPhoneFlows): detail layout (chips, title edit, hero, primary `Copy`, `Share`/`Pin`/`Board`/`Snippet`, Smart actions, Boards). On iPad the only delta is the width cap and the `⌘⏎` key chip on Copy. The current iPhone detail has `Copy`/`Share`/`Pin` (`ClipDetailView.swift:135-157`), `Save as snippet` as a separate section (`:205-211`), and `Copy` calls `dismiss()`, which is a no-op in the split.
- **GC-V4-8**: provenance on rows. `ClipCard.sourceTimeLine` shows app · time only (`GanchoDesign/Components.swift:386-398`). Doubt: the sample is inconsistent. `Synthetic link` reads `Safari · 7 min` but its detail says `Synced from Mac`, while other Mac rows read `Mac · …`.
- **GC-V4-9**: secret mask + expiry pill. The expiry countdown already exists (`Components.swift:162-170`, `:274-285`).
- **GC-26**: the pasteboard status card, iPhone counterpart.

---

## 4. Owner notes
- Pick notes: GC-33 none; GC-34 none.
- No owner comment thread on this board. These general rules apply:
  - Compare with the current UI and only propose what beats it.
  - Code wins over v2 boards.
  - Each piece of data appears once per screen. Check: the detail chips `Safari` / `7 min` repeat the selected row's meta, but they are in different columns, which matches the phone detail.
  - Annotations are not UI.
- Legacy board references: `V4_Gancho_Archive` lists `GC-33 · 34 iPad split view, drag-out GC3_iPad in v4 iPad` (moved here). `V4_Gancho_Overview` lists `iPad 1400 × 1140 GC-33 GC-34`.
