# V4_Gancho_Settings — spec

- **Board:** `V4_Gancho_Settings.dc.html`
- **Canvas:** 1640 × 1660 (board background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14).
- **Shows:** three v4 panes of `SettingsView` (Privacy, Capture, Retention; 760 × 500 each) and the v4 `PrivacyCenterView` (480 × 620). Below them: four numbered notes and a "PASS 2026-10-17" card that carries three more items (GC-V5-2, GC-V5-4, GC-V5-5) as text only.
- **Light mode only.** No dark variant is drawn.
- **Related Current boards:** `GanchoSettings_Current` (screenshots 10–13: General, Capture, Retention, Privacy), `GanchoSettingsMore_Current` (14–16: Integrations, Pro, About), `GanchoPrivacyCenter_Current`, `GanchoIntelligence_Current`, `GanchoMCPAccess_Current`, `GanchoPaywall_Current` (no Paywall element appears on this board; the only Pro reference is the `Sync off · … · Pro` tile).
- **Catalog IDs whose `board` is this board:** GC-17, GC-19, GC-21, GC-V5-2, GC-V5-4, GC-V5-5 (all `pick`, no pick notes). **Drawn here but catalogued elsewhere:** GC-20 (catalog board `V4_Gancho_Novel2`, see the overlap note in Feasibility), GC-07 (catalog board `V4_Gancho_PanelStates`; its Settings auto-off picker is drawn here). **Not a catalog item:** GC-18 (shipped).
- **Bugs fixed with these items:** B-GC-02 and B-GC-03 (GC-V5-2), B-GC-05 (GC-V5-4), B-GC-06 (GC-V5-5).

Colour key used below: `#34C759` = `GanchoTokens.Palette.brandGreen` / `accent` fallback (light); `#1F7A3A` = the board's green **text** ink (proposed accent-ink, see GC-V5-2); `#0B2A14` = ink on a green fill; `#5B5B61` = secondary text; `#FF3B30` = `Palette.danger`; `#FF9F0A` = `Palette.warning`; `#C8231B` = red text ink; `#7A4B00` = amber text ink.

---

## 0. Board header (context only, not UI)

One row, gap 12:
- ID chips (22 high, padding 0 9, radius 7, 11 pt mono 800): `GC-17` (green `#34C759` / `#0B2A14`), then `GC-18`, `GC-19`, `GC-20`, `GC-21` (black `#1D1D1F` / white).
- Title (22 pt 800): `Settings and Privacy Center · status first, then the toggles`
- Subtitle (13 pt `#5B5B61`, max 860 wide): `v4 of SettingsView (760 × 500, seven tabs) and PrivacyCenterView (480 × 620). Every toggle, picker and button of v0.10.2 is present; what changes is grouping, status tiles and two additions (auto-off, concealed-types card).` (`SettingsView`, `PrivacyCenterView` in mono)
- Right-aligned: `Gancho · macOS · v4`

Layout: row 1 = frame A (left) + frame B (right), gap 28; row 2 = frame C (left) + frame D (right), gap 28; then the notes grid (4 columns); then the PASS card.

---

## Shared Settings window chrome (frames A, B, C)

Applies to all three Settings frames; per-frame sections only list what differs.

- **Window:** 760 × 500, background `#F5F5F7`, radius 12, border 1 `rgba(0,0,0,.1)`, shadow `0 1 2 rgba(0,0,0,.08), 0 20 46 rgba(0,0,0,.2)`. Two columns. Matches code `SettingsView.swift:30` (`.frame(width: 760, height: 500)`).
- **Traffic lights:** three 12 pt circles at (12, 12), gap 7: `#FF5F57`, `#FEBC2E`, `#28C840`.
- **Sidebar:** 210 wide, background `#ECECEF`, right border 1 `rgba(0,0,0,.08)`, padding 38 top / 12 sides / 10 bottom, row gap 2.
  - Seven nav rows, in order: `General`, `Capture`, `Retention`, `Privacy`, `Integrations`, `Pro`, `About`. Row: height 32, padding 0 8, radius 7, 13 pt, icon 14 pt (stroke 2) in an 18-wide slot, gap 8.
  - Icons as drawn (stand-ins for the code's SF Symbols, which stay): General = gear (`gearshape`), Capture = clipboard (`doc.on.clipboard`), Retention = clock (`clock`), Privacy = lock (`lock.shield`), Integrations = puzzle piece (`puzzlepiece.extension`), Pro = sparkles (`sparkles`), About = info circle (`info.circle`).
  - **Selected row:** fill `#34C759`, ink `#0B2A14`, weight 600. **Unselected:** no fill, ink `#1D1D1F`, regular. **No focus ring is drawn on any row** (GC-V5-4).
  - **NEW — Privacy Center card, pinned to the sidebar bottom** (spacer above it): button, padding 9 × 10, radius 10, background `#fff`, no border, gap 8, 11.5 pt, line height 1.3. Left: shield glyph 16 pt (stroke 2.2) in `#1F7A3A`. Right, two lines: bold `Privacy Center` / `0 content requests · receipt · agents` in `#5B5B61`. Action (implied): opens the Privacy Center window (replaces the `Open Privacy Center` form button).
- **Content column:** title 18 pt 800, padding 30 top / 22 sides. Form: padding 10 22 12, group gap 8. Bottom 16 pt fades out (mask) and a scroll thumb is drawn (5 × 150, radius 3, `rgba(0,0,0,.22)`, right 4, top 70): **the pane scrolls**.
- **Form primitives:**
  - Section label: 10.5 pt 700, uppercase, tracking .06em, `#5B5B61`.
  - Group: background `#fff`, radius 10, border 1 `rgba(0,0,0,.08)`, row separators 1 `rgba(0,0,0,.07)`.
  - Row: min height 30, padding 5 × 12, 12.5 pt, gap 10; footnote under the label 10.5 pt `#5B5B61`, line height 1.3.
  - Switch: 34 × 20 pill, on `#34C759`, off `#D1D1D6`, white knob 16. (Board `aria-label="Toggle"` is a placeholder; the code's labels/ids stay.)
  - Pop-up: 22 high, padding 0 8, radius 6, border 1 `rgba(0,0,0,.14)`, `#fff`, 12 pt, chevron-down 10 pt (stroke 2.4) after the value.
  - Glass button: default 28 high, padding 0 10, radius 10, border 1 `rgba(0,0,0,.08)`, `#fff`, 12 pt 600 `#1D1D1F` (per-use height/size overrides noted below). These are **neutral** buttons, not green text.

---

## 1. Frame A "Settings · Privacy" — realises GC-17 (+ GC-07 auto-off picker)

Label above the frame (13 pt 800): chip `GC-17` (green) + `Settings · Privacy` + small (12 pt 600 `#5B5B61`) `status tiles + grouped controls · the pane scrolls`.

Sidebar: `Privacy` selected. Content title: `Privacy`.

Top to bottom:

### 1.1 Status tiles (NEW)
Grid of 4 equal columns, gap 8. Tile: padding 8 × 10, radius 10, `#fff`, border 1 `rgba(0,0,0,.08)`, gap 2. Value line 13 pt 700 (glyph + text, gap 6); sub line 11 pt `#5B5B61`, line height 1.3.

| # | Glyph | Value line | Sub line |
|---|---|---|---|
| 1 | 8 pt dot `#34C759` | `Capturing` (ink `#1D1D1F`) | `128 clips · 2.1 MB on this Mac` (sample numbers) |
| 2 | lock 12 pt (stroke 2.4) | ` Encrypted at rest` (ink `#1F7A3A`) | `SQLCipher · key in your Keychain` |
| 3 | half-filled shield 12 pt (stroke 2.4) | ` 12 skipped this week` (ink `#1D1D1F`; `12` sample) | `protected copies · never stored` |
| 4 | cloud 12 pt (stroke 2.2) | ` Sync off` (ink `#5B5B61`) | `iCloud private database · Pro` |

Only these states are drawn (capturing, encrypted, sync off). Other states (paused / private mode / screen share, ephemeral store, syncing / synced / failed) are not drawn — see Feasibility.

### 1.2 Section `Capture control`
1. `Private mode (pause capture)` — footnote `Nothing is saved while on. Pasting keeps working.` — switch **off**.
2. `Private mode shortcut` — right: recorder chip (22 high, padding 0 6, border 1 `rgba(0,0,0,.14)`, radius 6, `#fff`, gap 3) holding key caps `⌥` `⌘` `P` (sample value; key cap 18 high, min-width 18, radius 5, `rgba(29,29,31,.08)`, 10.5 pt 700 `#3A3A3F`).
3. **NEW (GC-07)** `Turn Private mode off automatically` — footnote `So a pause never silently becomes a week.` — pop-up `After 1 hour` (sample; no other options drawn).
4. `Pause automatically while sharing the screen` — footnote `Zoom, Meet, FaceTime, Teams and QuickTime are detected.` — switch **on**.

### 1.3 Section `Searches and Spotlight`
1. `Remember searches` — footnote `Recall recent panel searches with ⌘↑. Stored only on this Mac; turning this off erases them.` — switch **on**.
2. `Show snippets and pins in Spotlight` — footnote `Only snippets and pinned clips reach the system index — never raw history, secrets or expiring clips.` — switch **on**.

### 1.4 Section `Diagnostics`
1. `Share anonymous usage diagnostics` — footnote `Counts and broad buckets only — never clipboard content, titles, searches or source-app names.` — switch **off**.
2. Glass button `Save support bundle…` (height 26) followed, same row, by footnote `Versions, settings and counters — never clipboard content.`

Not drawn in this pane (present in code today): the `Open Privacy Center` button (moved to the sidebar card), the note `Secrets and card numbers are always masked in previews; revealing them takes an explicit click.`, the Spotlight sentence `Turning this off removes them from Spotlight immediately.`, and the post-save `supportNote` line (state-only; keep).

---

## 2. Frame B "Settings · Capture" — realises GC-19 (+ GC-18 shipped denylist, redrawn)

Label: chip `GC-19` (green) + `Settings · Capture` + small `denylist (shipped) + concealed rule · the pane scrolls`.

Sidebar: `Capture` selected. Content title: `Capture`. Form gap 8.

### 2.1 Capture types (group, no section label)
`Capture images` — on; `Capture copied files` — on; `Keep rich text formatting` — on.

### 2.2 Section `Never capture from these apps` (GC-18, shipped)
Group rows (sample data):

| App tile (22 × 22, radius 6, 9 pt 800 white initials; stand-in for the real app icon) | Name line | Caption (10.5 pt mono `#5B5B61`) | Trailing |
|---|---|---|---|
| `1P` on `#1A73E8` | `1Password` + chip `also concealed` | `com.1password.1password` | glass button `Remove` (24 high, 11 pt) |
| `KA` on `#8E8E93` | `Keychain Access` | `com.apple.keychainaccess` | `Remove` |
| `Bw` on `#175DDC` | `Bitwarden` | `com.bitwarden.desktop` | `Remove` |

- **NEW chip `also concealed`:** 20 high, padding 0 7, radius 999, 11 pt 600, background `rgba(52,199,89,.14)`, ink `#1F7A3A`, inline after the name.
- Add row (gap 8): glass button with menu (`aria-haspopup="menu"`, 24 high, 11 pt): plus glyph 11 + `Add app` + chevron-down 10. Then footnote (flex) `running app ▸ · Applications… · bundle id, validated as you type`. Then right-aligned disclosure button (no chrome, 11.5 pt `#1D1D1F`, `aria-expanded="false"`): chevron-right 11 + `Built-in exclusions` + `· 20` in `#5B5B61`. Collapsed.

### 2.3 NEW — Concealed-types rule card (GC-19), no switch
Group with tinted chrome: border 1 `rgba(52,199,89,.35)`, background `rgba(52,199,89,.06)`, radius 10. One row, top-aligned:
- Shield glyph 14 pt (stroke 2.2) `#1F7A3A`, 2 pt top offset.
- Title (bold 700): `Built-in rule · concealed and transient copies`
- Body (footnote style): `Password managers and some apps mark a copy as concealed, transient or auto-generated. Gancho senses the mark and stops there: the content is never read, stored, indexed or synced. This cannot be turned off.`
- Chip row (margin-top 6, gap 4, wraps), mono chips (16 high, padding 0 4, radius 5, `rgba(29,29,31,.08)`, 10 pt 600 `#5B5B61`): `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`.
- No control, no action. Static, always shown.

### 2.4 Intelligence (group row, no section label)
Row: title `Intelligence`, footnote `On-device titles, semantic retrieval, screenshot OCR and secret detection — each a toggle, all local.`; trailing glass button `Open Intelligence…` (height 26).

Not drawn (present in code today): the footnote `Built-in exclusions switch off one by one; your own entries are removed with the minus.`, the built-in row's `20 · password managers and banking apps`, and the `Intelligence` section header (now a row title).

---

## 3. Frame C "Settings · Retention" — realises GC-20 (timeline variant; see overlap)

Label: chip `GC-20` (green) + `Settings · Retention` + small `timeline over the pickers`.

Sidebar: `Retention` selected. Content title: `Retention`.

### 3.1 NEW — Retention timeline card
Card: padding 12 × 14, radius 10, `#fff`, border 1 `rgba(0,0,0,.08)`.
- Track area 36 high. Track: full width, 3 high, radius 2, `rgba(0,0,0,.1)`, top 16.
- Four markers (16 × 16 circle, 3 pt white border, ring `0 0 0 1 rgba(0,0,0,.12)`), each with a label under it (gap 4, 10.5 pt 700, no wrap). Positions as drawn (share of track width):

| Position | Marker fill | Label | Label ink | Alignment |
|---|---|---|---|---|
| 3 % | `#FF3B30` | `10 min · secrets` | `#C8231B` | left-aligned to the marker |
| 30 % | `#FF9F0A` | `7 d · images` | `#7A4B00` | centred |
| 55 % | `#34C759` | `30 d · everything else` | `#1F7A3A` | centred |
| 96 % | `#1D1D1F` | `never · pins, boards` | `#1D1D1F` | right-aligned to the marker |

- Caption (11 pt `#5B5B61`, margin-top 18): `Change a picker below and its marker moves. Older clips are deleted on this Mac and, when sync is on, on your other devices.`
- Behaviour (from the caption and note 3): each marker reflects its picker; changing a picker moves the marker. No interaction on the timeline itself is drawn (not draggable).

### 3.2 Section `History`
1. `Keep history for` — pop-up `30 days` (sample).
2. `Images` — pop-up `7 days` (sample).
3. `Text` — footnote `A per-type limit overrides the global window. Pinned clips and boards never expire.` — pop-up `Use global`.

### 3.3 Section `Sensitive items`
1. `Sensitive items expire after` — footnote `Detected secrets — passwords, keys, cards — always follow this limit. A safety guard you can shorten but not extend.` — pop-up `10 minutes`.

Differences from code: the History footnote drops `; leave a type on Use global to follow it` and sits under the `Text` row; the sensitive footnote drops `, even when your history keeps everything longer` and `It's`, and loses its `lock.shield` label icon.

---

## 4. Frame D "Privacy Center" — realises GC-21 (+ GC-V5-2 hero ink)

Label: chip `GC-21` (green) + `Privacy Center` + small `verify group first`.

- **Window:** 480 × 620 (same as code `PrivacyCenterView.swift:322`), `.win` chrome. Title bar 34 high, padding 0 12, bottom border 1 `rgba(0,0,0,.08)`; traffic lights; centred title `Privacy Center` 12.5 pt 600 (margin-right 46 to optically centre). **No in-content `Privacy Center` heading** (code draws one at `PrivacyCenterView.swift:28`).
- Content: padding 12 × 14, gap 8. Top to bottom:

### 4.1 Hero (kept; colours changed — GC-V5-2 / B-GC-03)
Padding 12 × 14, radius 12, background `linear-gradient(160deg, #5FD57F, #34C759)`, **ink `#04210D`** (dark, not white), gap 12, row.
- Shield glyph 30 pt (stroke 2).
- `0` — 26 pt 800, line height 1.
- `clipboard-content analytics requests` — 13 pt 700.
- `Optional diagnostics contain anonymous counts and broad buckets only.` — 11 pt, opacity .85.

### 4.2 Section `Verify, don’t trust` (NEW position; curly apostrophe)
Group, four rows; leading glyph 14 pt:
1. lock (stroke 2.2, `#1F7A3A`) — `History is encrypted on this Mac` / footnote `SQLCipher database, sealed image and file blobs. The key lives in your login Keychain.` — glass button `Verify` (24 high, 11 pt).
2. cloud with check (stroke 2.2, `#1F7A3A`) — `iCloud sync` / `Private database · Mac + iPhone · synced 2 min ago` (sample) — glass button `Force sync` (24, 11 pt).
3. eye (stroke 2, `#5B5B61`) — `Last content read` / `4 seconds ago · a copy you made in Safari` (sample) — no button.
4. puzzle piece (stroke 2, `#5B5B61`) — `Local AI agents (MCP)` / `Off · 0 calls this week · 0 denied` (sample) — glass button `MCP Access…` (24, 11 pt).

### 4.3 Section `Private activity receipt` (kept)
Group; compact rows (min height 26, padding 3 × 12), label left, value right (tabular digits, `#5B5B61`), sample values:
`Items reused` `41` · `Copies captured` `128` · `Captures skipped` `12` · `Protected copies skipped` `7` · `Sensitive items self-expired` `3`.
Last row (min height 30, padding 4 × 12): footnote `Stored only on this Mac for a rolling 13 months. Per-app totals never sync, export or enter diagnostics.` + right text button `Clear receipt` (no chrome, 11.5 pt 600, ink `#C8231B`).

### 4.4 Section `Optional diagnostics · Recent issues`
1. `Share anonymous usage diagnostics` — switch **off**.
2. Footnote row (min height 30, padding 4 × 12): `No issues recorded. Technical issues only — content-free, nothing about your clips.` (empty state).

Not drawn but stated as kept (note 4): `Activity by app` (per-app table, after the receipt), the `Unreadable clips` section (only when its count > 0, as today). Not drawn and not mentioned: `On this Mac now` (Secrets masked, Items synchronized), the sync event list, the MCP access ledger and `Agent results returned`, `Pasteboard access` debug row, `Successful reuses this session`, `Copy for support` (issues non-empty state), the two long diagnostics footnotes, and the `Network` section — see GC-21 questions.

---

## 5. Notes grid (annotations, not UI)

Four columns; each note = numbered black circle (20 pt, 11 pt 800) + 12 pt text. These are the board's numbered notes (there are no pins placed on the frames).

### Implementation notes (not UI)
> 1 **Privacy (GC-17 · GC-19):** the same seven tabs and the green selection the code draws; the Privacy Center is pinned to the sidebar bottom; four status tiles answer “what do you keep, where” before any toggle; every current control stays (private mode + shortcut, auto-pause on screen share, remember searches, Spotlight, support bundle, diagnostics) grouped by question. New: the auto-off picker (GC-07).

> 2 **Capture (GC-18 · GC-19):** the shipped denylist already shows app icon, name, bundle id, a visible Remove, one Add app menu (running app · Applications… · bundle id with live validation) and the collapsed built-in exclusions with their count — all from the “Pasteboard y Settings Capture” note, kept as built. New: the “also concealed” chip and the concealed-types rule as a card with no switch, so the privacy hard rule is visible once in Settings and matches “Sensed, not stored” in the panel.

> 3 **Retention (GC-20):** the three pickers stay; a timeline above them shows the four windows (secrets · images · everything · never) in one line. Changing a picker moves its marker.

> 4 **Privacy Center (GC-21):** hero and receipt stay; a Verify group puts encryption (with the mechanism and a Verify action), sync, the last content read and MCP agent access first; per-app activity (kept, not drawn), diagnostics and issues follow. Unreadable-clips section appears only when the count is non-zero, as in v0.10.2.

## 6. PASS card (annotations, not UI)

White card, radius 12, padding 14 × 18, inset left bar 3 `#34C759`. Header: black tag `PASS 2026-10-17` + 14 pt 800 `Checked against screenshots 10–20 (settings panes, Privacy Center, MCP Access, Intelligence)`. Two-column grid of four items:

> `GC-21` (amber tag) Corrected baseline: today the proofs (pasteboard access, last content read, network, MCP, iCloud sync) sit at the bottom of the Privacy Center, below the receipt and per-app activity (PrivacyCenterView sections). v4 moves them up as the Verify group.

> `GC-V5-2` **Accent text that passes AA.** Green text on light surfaces (Edit, By meaning, Clear filters, Open Privacy Center…) renders at about 2.6:1 and the Privacy Center hero is white on #72CE77 (about 2:1). Add an accent-ink token (fill stays the system accent; text uses a darker step, about #3B7D28) and darken the hero gradient. The Current boards already draw text with that step.

> `GC-V5-4` **Settings sidebar ring follows the selection.** Screenshots 11–16: General keeps a light green focus ring after another pane is chosen, so two rows look selected. Show the ring only for keyboard focus, on the row that has it.

> `GC-V5-5` **Intelligence pipeline fits its window.** Screenshot 20: the fifth node (Indexed · FTS + embeddings) is cut at the 520 pt edge and the Smart paste row has no glyph. Tighten the node spacing so all five fit and give Smart paste its icon.

GC-V5-5 has no drawing on this board; GC-V5-2 and GC-V5-4 are only visible indirectly (green text in `#1F7A3A`, dark hero ink, no focus ring).

---

## 7. Coverage

| Board element | Covered by |
|---|---|
| Header chips/title/subtitle | context only |
| Shared window chrome, seven-tab sidebar, green selection | kept, no change (code `SettingsView.swift:99-153`) |
| Sidebar: no focus ring on non-selected rows | GC-V5-4 / B-GC-05 |
| Sidebar Privacy Center card (all three Settings frames) | GC-17 |
| Frame A status tiles | GC-17 |
| Frame A `Capture control` rows 1, 2, 4 | GC-17 (regrouped; controls kept) |
| Frame A `Turn Private mode off automatically` | GC-07 (built with GC-17 layout) |
| Frame A `Searches and Spotlight`, `Diagnostics` | GC-17 (regrouped; copy shortened) |
| Frame B capture toggles | kept, no change |
| Frame B denylist rows, Add app, Built-in exclusions | GC-18 — shipped (Archive: “DenylistSettingsSection: icon, bundle id, Add app menu, built-in exclusions”); drawn deltas listed under GC-19 questions |
| Frame B `also concealed` chip | GC-19 |
| Frame B concealed-types card | GC-19 |
| Frame B Intelligence row | kept (layout: header → row title), folded into GC-19 work |
| Frame C timeline card | GC-20 (timeline variant on this board) |
| Frame C History / Sensitive pickers | kept; footnotes shortened (GC-20) |
| Frame D title bar, removal of in-content heading | GC-21 |
| Frame D hero | kept; colours = GC-V5-2 / B-GC-03 |
| Frame D Verify group | GC-21 |
| Frame D receipt | kept; footnote/button copy = GC-21 |
| Frame D diagnostics + issues | GC-21 (merged section) |
| Note 1 | GC-17, GC-19, GC-07 |
| Note 2 | GC-18 (shipped), GC-19 |
| Note 3 | GC-20 |
| Note 4 | GC-21 |
| PASS card: GC-21 baseline | GC-21 |
| PASS card: GC-V5-2 | GC-V5-2 / B-GC-02 / B-GC-03 |
| PASS card: GC-V5-4 | GC-V5-4 / B-GC-05 |
| PASS card: GC-V5-5 | GC-V5-5 / B-GC-06 |

---

## 8. Feasibility

### GC-17 · Privacy settings with status tiles first (UI + small data)

**What changes**
- `PrivacySettingsTab` gains the four status tiles, three grouped sections (`Capture control`, `Searches and Spotlight`, `Diagnostics`) and new/shortened footnotes; loses `Open Privacy Center`.
- `SettingsSidebar` gains the bottom-pinned Privacy Center card, on every pane.

**Code (verified)**
- `Apps/GanchoMac/PrivacySettingsTab.swift:14-73` (Form today: ungrouped toggles + footnotes; `Open Privacy Center` at :43-45; support bundle at :46-57; telemetry toggle :59-71, id `telemetry-consent-toggle`).
- `Apps/GanchoMac/SettingsView.swift:99-116` (sidebar: `Spacer(minLength: 0)` at :107 is where the card goes; `model.privacyCenterWindow.show(model:)` is the action, as in `PrivacySettingsTab.swift:44`).
- Tile 1 count: `ClipboardStore.count()` (`Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift:499`). Size on disk: **no API** (new: database file + blob directory size, computed off the main actor).
- Tile 1 state: `MacPasteboardMonitor` status (`Packages/GanchoKit/Sources/ClipboardCore/MacPasteboardMonitor.swift:30`, `.pausedByScreenShare` etc.) and `preferences.isPrivateModePaused` (`ClipboardCore/CapturePreferences.swift:17`).
- Tile 2: the durable Mac store is opened encrypted through `StoreBootstrap` (`Packages/GanchoKit/Sources/GanchoAppCore/StoreBootstrap.swift:125-131`, `AppModel.swift:322-328`); `model.storageIsEphemeral` (`AppModel.swift:76`) is the "not saved / not encrypted" case.
- Tile 3: protected skips exist only as a 13-month aggregate (`PrivateActivityReceipt.swift:166-176`, `191-245`). The table is keyed by UTC day, so a "last 7 days" query is a small new store method.
- Tile 4: `model.syncStatus` (`SyncEngine.swift:6-13`) + Pro entitlement.

**Exists vs new**
- Exists: every control and binding; clip count; sync status; encryption by construction; receipt counters.
- New: tiles view, sidebar card, size-on-disk, weekly protected-skip count, ~12 new strings (EN + ES in `Apps/GanchoMac/Localizable.xcstrings`; `LocalizationTests` fails otherwise).

**Dependencies:** GC-07 (auto-off picker row; its timer and preference are GC-07 work). GC-V5-2 (tile 2 and the card glyph use the accent-ink `#1F7A3A`).

**Verify**
- Unit: weekly protected-skip query (Swift Testing, beside `PrivateActivityReceiptTests`), size calculator.
- UI: extend `Tests/GanchoUITests/SettingsPrivacyUITests.swift` (opens `settings-tab-privacy`) to assert the tiles and the sidebar card exist (new ids, e.g. `privacy-status-capturing`, `privacy-status-encrypted`, `privacy-status-skipped`, `privacy-status-sync`, `settings-privacy-center-card`), and that the card opens `privacy-center`. Screenshot compared with frame A.

**BLOCKED / questions**
1. **Screen-share footnote is false today.** `ScreenShareDetector.shareHelperNames` (`ClipboardCore/ScreenShareDetector.swift:20-25`) detects Zoom (`CptHost`, `caphost`), Teams and Apple Screen Sharing only, not Meet, FaceTime or QuickTime. Should we ship the copy and extend the detector, or rewrite the copy to `Zoom, Teams and Screen Sharing are detected.`?
2. Tile 3 sample `12 skipped this week · protected copies` conflicts with the receipt sample (`Captures skipped 12`, `Protected copies skipped 7` over 13 months). Does the tile count **protected** skips or **all** skips in the last 7 days?
3. Tile copy for the undrawn states (Private mode on, paused by screen share, ephemeral store = not encrypted, sync on/syncing/failed)?
4. The masked-previews note (`Secrets and card numbers are always masked…`) and the Spotlight sentence `Turning this off removes them from Spotlight immediately.` are not drawn. Drop them, or keep them as drawn-elsewhere copy?
5. Sidebar card subtitle `0 content requests · receipt · agents`: is the `0` the fixed hero claim (as in the hero) or a live count?

---

### GC-07 (as drawn here) · Auto-off picker
Only the Settings row is on this board. `Turn Private mode off automatically` / `So a pause never silently becomes a week.` / pop-up `After 1 hour`. **No auto-off preference or timer exists** (grep for any private-mode expiry in `Apps` and `Packages/GanchoKit/Sources` returns nothing). New: preference on `CapturePreferences`, timer in `CaptureLifecycleController` (`Packages/GanchoKit/Sources/GanchoAppCore/CaptureLifecycleController.swift`). **BLOCKED:** the option list is not drawn (only `After 1 hour`). Which values, and is there a `Never` option? The rest is specified on `V4_Gancho_PanelStates`.

---

### GC-19 · Concealed-types rule as a card, no toggle (UI) + `also concealed` chip

**What changes**
- `CaptureSettingsTab` gains a static card after the denylist section (`Apps/GanchoMac/CaptureSettingsTab.swift:18-20`).
- The Intelligence section becomes one row (title + footnote + `Open Intelligence…`, id `open-intelligence` kept, :21-22).
- Denylist rows gain the `also concealed` chip (`Apps/GanchoMac/DenylistSettingsSection.swift:45-69`).

**Code (verified)**
- The hard rule already exists. The type strings come from `Packages/GanchoKit/Sources/ClipboardCore/SensitivePasteboardTypes.swift:8-12` (`concealed`, `transient`, `autoGenerated`); the veto runs before any read in `MacPasteboardMonitor` (comment at `DenylistSettingsSection.swift:7-9`).
- Chips: the first is the full `org.nspasteboard.ConcealedType`; the other two are drawn short (`TransientType`, `AutoGeneratedType`). They are identifiers, so mark them `verbatim:` (not localised).

**Exists vs new**
- Exists: the rule, the type constants, the denylist (GC-18).
- New: the card view, 2 new strings (title, body; EN + ES), the chip and its data source.

**Dependencies:** GC-V5-2 (card glyph and chip use the accent-ink). The concealed card must stay consistent with the panel's "Sensed, not stored" copy (`V4_Gancho_PanelStates` / Onboarding).

**Verify**
- UI: `Tests/GanchoUITests/DenylistUITests.swift` (opens `settings-tab-capture`, :181). Assert the card (new id, e.g. `capture-concealed-rule-card`) exists and contains no switch.
- Snapshot vs frame B.

**BLOCKED / questions**
1. **Data source for `also concealed`.** The receipt records protected skips only in the aggregate bucket, never per app (`PrivateActivityReceipt.swift:166-176`, by design). A static rule ("password-manager category" from `SourceAppDenylist.swift:37-60`) would tag 1Password, Bitwarden **and** Keychain Access, but the board tags only 1Password. Options: (a) a static list of apps known to set `ConcealedType`, or (b) a new per-app "concealed seen" flag. Option (b) touches the privacy boundary (per-app protected metadata), so it needs an owner decision.
2. **Sample conflicts with code behaviour.** 1Password, Keychain Access and Bitwarden are built-in exclusions (`SourceAppDenylist.swift:37,40,43`). `addApp` switches a built-in on instead of listing it (`DenylistSettingsSection.swift:290-296`), so these three can never appear as user rows. Treat them as sample only?
3. **GC-18 "kept as built" vs drawing.** The code shows an icon-only `minus.circle` remove (`DenylistSettingsSection.swift:60-67`, a11y label `Remove`, id `denylist-remove-<slug>`), the built-in label `20 · password managers and banking apps` (:183-187) and the footnote `Built-in exclusions switch off one by one; your own entries are removed with the minus.` (:32-36). The board draws a text `Remove` button, `· 20`, no footnote and an inline helper line. Note 2 says "kept as built". Which wins?
4. `running app ▸ · Applications… · bundle id, validated as you type` reads as a description of the menu (code items: `Running app`, `From Applications…`, `By bundle identifier…`, :77-93). Is it UI copy or annotation?

---

### GC-20 (as drawn here) · Retention timeline over the pickers — overlap with Novel2

**What changes**
- A read-only timeline card above the `History` section in `Apps/GanchoMac/RetentionSettingsTab.swift:10-27`, driven by `model.retentionPolicy` (`global`, `perKind[.image]`, `perKind[.text]`, `sensitiveLifetime`).
- Footnotes shortened.

**Code (verified)**
- Window enum `RetentionPolicy.Window` (`Packages/GanchoKit/Sources/GanchoKit/RetentionPolicy.swift:7`; options 24 h, 7 d, 30 d, 90 d, 6 mo, 1 y, Forever per `RetentionSettingsTab.swift:51-69`); sensitive 5/10/30 min (:34-36); default 600 s (`RetentionPolicy.swift:41`).
- Caption claim "deleted … on your other devices" is **true**: `RetentionEngine.runPurge` tombstones synced victims before deleting (`RetentionEngine.swift:31-52`).
- Caveat for "never · pins, boards": secrets expire **even when pinned or on a board** (`RetentionEngine.swift:59-65`). That matches the existing footnote, but the timeline must not imply a pinned secret is kept.

**Exists vs new**
- Exists: pickers, policy, purge, sync deletion.
- New: timeline view; a pure "policy → ordered markers" mapper (put it in `GanchoAppCore` so it can be unit-tested); 4 marker label formats + caption (EN + ES).

**Overlap:** catalog GC-20 (board `V4_Gancho_Novel2`) proposes a **stepped dial per type** (30m 1h 8h 24h 7d 30d 1y ∞), replacing the pickers, plus **"Forget recent clips"** (5/15/60 min, preview count, `Forget 7 clips`). Novel2's "Needs" also lists shorter windows in the policy enum and a time-window delete in `DeletionCoordinator`. This board keeps the pickers and adds only a read-only timeline.

**Dependencies:** GC-V5-2 (marker label inks).

**Verify**
- Unit: the mapper (each picker change moves exactly its marker; `Use global` folds Text into "everything else").
- UI: `Tests/GanchoUITests/RetentionPassUITests.swift`; change `Images` and assert the marker label updates.

**BLOCKED / questions**
1. **Which GC-20 ships?** The timeline over the pickers (this board) or the dial + Forget recent (Novel2, the catalog board)? Or the timeline first and the dial later? Precedence does not settle it: both are v4 boards and there is no owner note.
2. Marker positions (3 / 30 / 55 / 96 %) follow no linear or log scale (on a log scale from 10 min to 30 d, `7 d` would sit near 46 %, not 30 %). Is the spacing ordinal (evenly ordered) or scaled?
3. When `Text` has its own window (not `Use global`), is there a fifth marker? When `Images` is `Use global`, does its marker merge into "everything else"? When global is `Forever`, how does "everything else" merge with "never"?

---

### GC-21 · Privacy Center opens with a Verify group (UI + small data)

**What changes:** reorder `PrivacyCenterView` (`Apps/GanchoMac/PrivacyCenterView.swift:26-320`):
1. Hero.
2. New `Verify, don’t trust` group (4 rows).
3. Receipt (copy edits; button `Clear receipt`).
4. `Activity by app` (kept).
5. Merged `Optional diagnostics · Recent issues`.
6. `Unreadable clips` stays conditional (:142).

Also drop the in-content `Label("Privacy Center", …)` (:28-29), because the title bar already shows it (:428).

**Code (verified)**
- Force sync exists (:128, id `force-sync`). Sync status uses `SyncStatusView` (:127), and `SyncStatus.upToDate(at: Date?)` (`SyncEngine.swift:9`) gives `synced 2 min ago`.
- Last content read: `monitor.lastContentReadAt` (`ClipboardCore/MacPasteboardMonitor.swift:79`, set at :265). Only the timestamp is tracked.
- MCP: on/off (:188), calls / denied this week (:357-362); window action `model.mcpAccessWindow.show` (:198, id `open-mcp-access`).
- Receipt ids `private-receipt-*-count`, `clear-private-receipt-button` (:59-84) stay.
- Telemetry toggle id `privacy-telemetry-consent-toggle` (:290) stays.
- Issues come from `model.diagnostics.entries` (:251).

**Exists vs new**
- Exists: all data except the items listed under new.
- New:
  - the `Verify` action (undefined);
  - the source app of the last content read (`a copy you made in Safari`);
  - the device list `Mac + iPhone` (no API; per-device provenance exists as `sourceDeviceName` on clips);
  - the row layout;
  - ~10 strings (EN + ES).

**Dependencies:** GC-V5-2 (hero ink + green glyphs). iPhone counterpart on `V4_Gancho_iPhoneFlows` (catalog says "Mac e iPhone"; that board's Verify group lists encryption, sync and the **masked count**).

**Verify**
- UI: `Tests/GanchoUITests/PrivateActivityReceiptUITests.swift` and `PanelUITests.swift:458-474` open via `-open-privacy-center-on-launch`. Add an order assertion (the Verify group's frame sits above `private-receipt-section`).
- Snapshot vs frame D.

**BLOCKED / questions**
1. **What does `Verify` do?** Options: re-check `PRAGMA cipher_version` / the Keychain item and show a result, or open documentation. No such action exists today.
2. **`Network` section.** The PASS baseline lists "network" among the proofs moved up, but the drawn Verify group has no Network row and the section is not drawn anywhere. Keep it (where), fold its copy into the hero, or drop it?
3. Sections not drawn and not mentioned: `On this Mac now` (Secrets masked / Items synchronized, :121-124), the sync event list (:130-139), the MCP ledger list and `Agent results returned` (:196, :200-229), `Successful reuses this session` (:291-295), `Copy for support` (:268-276), the two diagnostics footnotes (:296-307). Dropped or kept below the fold? (iPhoneFlows puts the masked count *in* Verify.)
4. `a copy you made in Safari`: is surfacing the source app of the last read acceptable? It is local UI only, so it does not hit the log or telemetry rule, but it is new per-read metadata held in memory.
5. Receipt footnote drops `Protected copies are included in skipped captures.` Intentional?

---

### GC-V5-2 · Accent text and Privacy hero that pass AA (system) — with B-GC-02, B-GC-03

**What changes:** add an accent-**ink** token to `GanchoTokens.Palette` (`Packages/GanchoKit/Sources/GanchoDesign/GanchoColors.swift`). Fills keep `accent`; text and small glyphs that act as text use `accentInk`. Change the Privacy Center hero to dark ink (as drawn) or a darker gradient.

**B-GC-02 location (verified, refined):** `GanchoColors.swift:68-79` (`accent`). Line 72 is the `.system` branch (`controlAccentColor`). The **default** Multicolor path is line 73 (`brandGreen` = `#34C759`), which is the failing case on most Macs. The ink problem is not a single line: it appears at every call site that uses `accent` (or the `.ganchoTinted()` tint, :186-189) as text.

**B-GC-03 location (verified):** `Apps/GanchoMac/PrivacyCenterView.swift:382` (`.foregroundStyle(.white)` on the text stack), plus :374 (white glyph) and :386-388 (`Palette.success.gradient`). The hero uses `success`, which is fixed green, not `accent`, so B-GC-03 does not depend on the system accent.

**Contrast math** (WCAG 2.x; relative luminance L = 0.2126 R + 0.7152 G + 0.0722 B on linearised sRGB, where c ≤ 0.04045 gives c/12.92 and otherwise ((c+0.055)/1.055)^2.4; ratio = (L1 + 0.05)/(L2 + 0.05))

| Colour | L |
|---|---|
| `#FFFFFF` | 1.0000 |
| `#F5F5F7` (window bg) | 0.9143 |
| `#ECECEF` (sidebar) | 0.8406 |
| `#E6F3DF` / `#E3EFDC` (tinted button fills on the Current boards) | 0.8625 / 0.8323 |
| `#34C759` (brand / accent) | 0.4230 |
| `#72CE77` (hero gradient top) | 0.4905 |
| `#5FD57F` (v4 hero top) | 0.5155 |
| `#3B7D28` (catalog's ink step) | 0.1575 |
| `#1F7A3A` (ink drawn on the v4 boards) | 0.1452 |
| `#04210D` (v4 hero ink) | 0.0114 |
| `#2F8C3B` / `#257A31` (Current-board hero) | 0.1968 / 0.1453 |

| Pair | Ratio | AA normal (4.5) |
|---|---|---|
| `#34C759` on `#FFFFFF` (today's green text) | (1.05)/(0.473) = **2.22** | fail (catalog says ≈2.6; it is worse) |
| `#34C759` on `#F5F5F7` | 0.9643/0.473 = **2.04** | fail |
| `#FFFFFF` on `#72CE77` (today's hero, top) | 1.05/0.5405 = **1.94** | fail |
| `#FFFFFF` on `#34C759` (today's hero, bottom) | **2.22** | fail |
| `#3B7D28` on `#FFFFFF` | 1.05/0.2075 = **5.06** | pass |
| `#3B7D28` on `#F5F5F7` | **4.65** | pass |
| `#3B7D28` on `#E6F3DF` (pressed "By meaning") | 0.9125/0.2075 = **4.40** | **fail** |
| `#3B7D28` on `#E3EFDC` (tinted Form button) | **4.25** | **fail** |
| `#1F7A3A` on `#FFFFFF` | 1.05/0.1952 = **5.38** | pass |
| `#1F7A3A` on `#F5F5F7` | **4.94** | pass |
| `#1F7A3A` on 14 % green over white (`#E3F7E8`, `also concealed` chip) | **4.80** | pass |
| `#1F7A3A` on 6 % green over white (`#F3FCF5`, concealed card) | **5.14** | pass |
| `#04210D` on `#5FD57F` (v4 hero, top) | 0.5655/0.0614 = **9.21** | pass |
| `#04210D` on `#34C759` (v4 hero, bottom) | 0.473/0.0614 = **7.70** | pass |
| `#04210D` at 85 % opacity on `#5FD57F` (hero caption → `#123C1E`) | **6.69** | pass |
| `#FFFFFF` on `#2F8C3B` (Current-board hero top) | **4.26** | fail |
| `#0B2A14` on `#34C759` (selected sidebar row) | **6.98** | pass (code picks black via `ContrastingForeground`: 9.46) |
| `#30D158` on `#1C1C1E` / `#2C2C2E` (dark mode accent text) | **8.42 / 6.89** | pass (dark needs no ink step) |
| System accents on white: blue `#007AFF` 4.02, orange `#FF9500` 2.20, yellow `#FFCC00` 1.51 (approx. system values) | | all fail |

Conclusions:
- `#3B7D28` passes only on white or `#F5F5F7`, so use **`#1F7A3A`** (what the v4 boards draw) or darker for light-mode ink. The first same-hue (HLS) step of `#34C759` that clears 4.5 on both white and `#F5F5F7` is `#22813A` (4.92 / 4.52).
- Because the system accent can be any hue, derive ink in code: darken the resolved accent in the light appearance until it reaches ≥ 4.5:1 against `windowBackgroundColor` (reuse the luminance maths in `ContrastingForeground.swift:10-19`), and use the accent as-is in dark mode.
- Hero: the board's dark-ink option (9.21 / 7.70) passes without changing the gradient.

**Call sites that use the accent as text ink today (macOS)**

Explicit `foregroundStyle(GanchoTokens.Palette.accent)` on text or a text-bearing label:
- `Apps/GanchoMac/PanelSelectionContextBar.swift:19-22` — `Label("\(selectionCount) clips", …)`
- `Apps/GanchoMac/ToastPresenter.swift:70-76` — toast action `Button(action.title)` (borderless + accent)
- `Apps/GanchoMac/PanelView.swift:478-487` — UI-test drag overlay label (`… file items`), debug/UI-test only

Implicit, via the `.ganchoTinted()` tint on `.borderless`/`.link` buttons and `.toggleStyle(.button)`:
- `Apps/GanchoMac/ClipTextEditor.swift:45-46` — **`Edit`**
- `Apps/GanchoMac/PanelResultsView.swift:274-275` — **`Clear filters`**
- `Apps/GanchoMac/MeaningSearchControls.swift:9-10` — **`By meaning`**
- `Apps/GanchoMac/ClipPeek.swift:295-299` — `Add` (board suggestion)
- `Apps/GanchoMac/ClipPeek.swift:332-338` — `Save` / `Cancel` (title edit)
- `Apps/GanchoMac/PeekImageText.swift:216-217` — OCR `Cancel`
- `Apps/GanchoMac/PanelStatusFooter.swift:81-82` — footer notice action
- `Apps/GanchoMac/LibraryView+Sidebar.swift:69-70` — `Retry` (`.link`)

Grouped-`Form` push buttons, drawn as green text on a light-green fill in the Current boards (screenshots 10–16):
- `Apps/GanchoMac/PrivacySettingsTab.swift:43` — **`Open Privacy Center`**
- `Apps/GanchoMac/CaptureSettingsTab.swift:21` — `Open Intelligence…`
- `Apps/GanchoMac/PrivacyCenterView.swift:128` — `Force sync`
- `Apps/GanchoMac/PrivacyCenterView.swift:198` — `Open MCP Access…`
- `Apps/GanchoMac/PrivacyCenterView.swift:268` — `Copy for support`
- `Apps/GanchoMac/DenylistSettingsSection.swift:172` — `Restore default exclusions`
- `IntegrationsSettingsTab` / `ProSettingsTab` buttons (`Open MCP Access…`, `See what Pro adds`, `Reset & re-pull sync`)

Accent glyphs only (icon ink, not text; same token, lower priority under WCAG 1.4.11's 3:1 rule):
- `ClipPeek.swift:292`
- `LibraryView+SnippetEditor.swift:107`
- `AboutSettingsTab.swift:104`
- `LibraryView+Sidebar.swift:202`
- `ClipLargePreview.swift:37,155`
- `MigrationImportComponents.swift:10,77`
- `PanelBoardPicker.swift:131,158`
- `IntelligenceView.swift:31,72,89` (+ `179`, stage tint)
- `PeekImageText.swift:21`
- `OnboardingView.swift:60,86,144` (`.tint`)
- `WrappedView.swift:16` (`.tint`)

iOS / extensions with accent text:
- `Apps/GanchoiOS/CaptureView.swift:129-132` — `Ask gancho` label
- `Apps/GanchoKeyboard/KeyboardView.swift:35-38` (label) and `:145-148` (Save clipboard button)
- iOS borderless buttons, 3 sites (`grep buttonStyle(.borderless|.link)`, `Apps/GanchoiOS`)

iOS glyph-only:
- `PasteboardStatusRow.swift:94`
- `ReuseSuggestionBanner.swift:29`
- `BoardsHomeView.swift:50`
- `IOSOnboardingView.swift:25,83`
- `ClipDetailView.swift:370`
- `IPadSplitView.swift:182,209`
- `KeyboardView.swift:377`
- `RecentClipsWidget.swift:91,99,113`

On iOS the accent is always `brandGreen` (`GanchoColors.swift:75-78`).

**Exists vs new**
- Exists: `accent`, `brandGreen`, `ContrastingForeground` luminance helper, `PaletteTests` (`Packages/GanchoKit/Tests/GanchoDesignTests/PaletteTests.swift`).
- New: `accentInk` token (dynamic light/dark), the call-site sweep, and the hero ink change.

**Dependencies:** none upstream. GC-17, GC-19, GC-20 and GC-21 consume the token.

**Verify**
- Unit (Swift Testing, `PaletteTests`): `accentInk` resolved in aqua has a contrast ratio ≥ 4.5 against `#FFFFFF` and `#F5F5F7` for brand green and for a sample of system accents (blue, orange, yellow, graphite). The dark appearance returns the accent unchanged.
- Snapshot: Privacy Center hero vs frame D.
- `grep` gate: no `foregroundStyle(GanchoTokens.Palette.accent)` on `Text`.

**BLOCKED / questions**
1. Hero fix: the board **draws** dark ink on the brand gradient (`#5FD57F → #34C759`, ink `#04210D`), but its PASS note says "darken the hero gradient", and `GanchoPrivacyCenter_Current` draws a dark gradient (`#2F8C3B → #257A31`) with white, whose top fails at 4.26. Which one?
2. Should borderless/link buttons get the ink through a scoped `.tint(accentInk)` on text-only controls, or through a custom button style? A global `.tint(accentInk)` would also darken switches and fills, which must stay on the accent.

---

### GC-V5-4 · Settings sidebar ring follows the selection (bug) — B-GC-05

**B-GC-05 real location (was "unverified"):** `Apps/GanchoMac/SettingsView.swift:121-153`, `sidebarRow`. Each row is a `Button` with `.buttonStyle(.plain)` (:150) and default focusability.
- When the window opens (`SettingsWindowController.swift:23-27`), AppKit gives initial key focus to the first focusable control: the `General` row.
- On macOS a mouse click on a button does not move keyboard focus. The system focus ring therefore stays on `General` while `selection` changes the fill (:138-146).
- This is my reading of the code; I have not reproduced it here. Confirm with a screenshot before fixing.

**What changes:**
- Add `@FocusState private var focusedTab: SettingsTab?` to `SettingsSidebar`.
- On each row: `.focused($focusedTab, equals: tab)` and `.focusEffectDisabled()` (pattern already used at `ClipPeek.swift:186-187`).
- Set `focusedTab = tab` in the button action.
- Draw the app's own ring (`GanchoTokens.Stroke.focus` = 1.5 pt) only when the row has keyboard focus and is not the selected row. The selected row keeps the green fill as its only marker.
- Optionally support ↑/↓ to move focus/selection.

**Exists vs new:** the selection state and the fill exist. New: focus state, focus-effect suppression, the custom ring.

**Dependencies:** none.

**Verify:**
- UI: `Tests/GanchoUITests/AppQualityUITests.swift:37-49` already clicks every `settings-tab-<id>` and asserts `isSelected`. Add a step: after clicking `settings-tab-capture`, `settings-tab-general` is not selected and `hasKeyboardFocus` is false (via `value(forKey:)`).
- Screenshot compared with frame A (no ring on `General`).

**BLOCKED:** —

---

### GC-V5-5 · Intelligence pipeline fits its window (bug) — B-GC-06 (no drawing on this board)

**B-GC-06 location (verified):** `Apps/GanchoMac/IntelligenceView.swift:132` (`.frame(width: 520, height: 600)`), with the pipeline at :172-195.

Width math:
- Content width = 520 − 2 × `Spacing.md` (16) = **488**.
- Pipeline needs 5 nodes × 92 (:186) + 8 HStack gaps × `Spacing.xs` (8, :174) + 4 chevrons (`caption2`, ≈ 6 each) + 2 × `xxs` (4) padding (:193) ≈ 460 + 64 + 24 + 8 = **≈ 556**.
- The overflow is **≈ 68**, so the horizontal `ScrollView` (:173) clips node 5.
- Fix options (any one fits): node width ≤ 78 with gap 8 (5w ≤ 392); node width ≤ 84 with gap 4; or keep 92 and wrap into two rows. Remove the horizontal `ScrollView` so nothing clips silently. `Tier 1 · Apple Intelligence` already wraps (`multilineTextAlignment(.center)`).

**Smart paste glyph:** the row uses `"pencil.and.sparkles"` (:89), which renders blank in screenshot 20, so the symbol does not resolve on the shipped OS. Use a symbol that already renders in the app: `"wand.and.sparkles"` (`ClipPeek.swift:828`) or `"sparkles"` (what iOS uses for the same row, `Apps/GanchoiOS/IntelligenceView.swift:80`). Also check the macOS 15.4 minimum.

**Exists vs new:** both are small edits to existing code; nothing new.

**Dependencies:** GC-V5-2 if the Smart paste / Smarter titles glyph tint moves to the ink token (glyph only, optional).

**Verify:**
- Unit/app test: every SF Symbol name used by `IntelligenceView` resolves via `NSImage(systemSymbolName:accessibilityDescription:) != nil`.
- UI: `Tests/GanchoUITests/IntelligenceCapabilityUITests.swift` (opens via `settings-tab-capture` → `open-intelligence`). Assert all five stage titles are hittable inside the window frame.
- Screenshot vs screenshot 20.

**BLOCKED:** —

---

### Related IDs shown on this board

- **GC-18** (not in the catalog): "Ignored apps with identity and suggestions" — shipped (`V4_Gancho_Archive`: "shipped DenylistSettingsSection: icon, bundle id, Add app menu, built-in exclusions"; `V4_Gancho_Overview`: "shipped in 0.9–0.10 … denylist identity … documented as kept, not redrawn"). Here it is redrawn with deltas; see GC-19 question 3.
- **GC-07:** catalog item on `V4_Gancho_PanelStates`; only its Settings picker is drawn here.
- **GC-20:** catalog item on `V4_Gancho_Novel2`; this board's timeline is a different realisation (see the overlap above).

---

## 9. Owner notes

- No pick notes on GC-17, GC-19, GC-20, GC-21, GC-V5-2, GC-V5-4 or GC-V5-5 (all `pick`, `note: ""`).
- No owner comment thread targets this board directly. Cross-board owner rules that apply:
  - "compare every proposal with the current UI and only propose what beats it; … Code wins over v2 boards and site screenshots" (2026-10-17). This bears on GC-18's drawn deltas (GC-19 question 3).
  - "each piece of data appears once per screen; no duplicated info". This supports removing the duplicated in-content `Privacy Center` heading, moving `Open Privacy Center` into the sidebar card, and merging the duplicated diagnostics toggle sections. Note that `Share anonymous usage diagnostics` still appears in both Settings › Privacy and the Privacy Center, which are separate windows.
  - "Annotations are NOT UI". Notes 1–4, the PASS card and the `(shipped)` / `status tiles…` frame subtitles are not UI.
