# V4_Gancho_Novel2 — Find, transform and trust

- **Board:** `V4_Gancho_Novel2.dc.html`, canvas **2400 × 2212**, background `#ECEDF0`, radius 12.
- **What it shows:** eight proposal cards (four rows of two) for search, context, transform, retention, agent visibility, snippets and iPhone surfaces. Each card is a 1152 × 474 white card with a mockup on the left and an annotation column on the right. None of these screens exists in v0.10.2.
- **Related Current boards (reference only):** GanchoPanel_Current (screenshot 04), GanchoPanelActions_Current (05–07), GanchoMCPAccess_Current (19), GanchoSettings_Current (10–13). Also cited: GanchoPhone_Current, screenshots 12, 20, 23.
- **Same IDs drawn on other boards (merge in the plan):** GC-V4-1 → V4_Gancho_Archive row "Search modes as a visible group" (says "in v4 Panel · pills inside the field"); GC-11 → V4_Gancho_Peek (Transform popover, card "GC-11 Code clip · Transform popover open") and V4_Gancho_Panel note 4; GC-12 → V4_Gancho_PanelStates (card "GC-12 Smart paste · was → will paste today") and V4_Gancho_Archive; GC-20 → V4_Gancho_Settings (card "GC-20 Settings · Retention timeline over the pickers", note 3); GC-V6-8 → overlaps V4_Gancho_iPhoneSurfaces (GC-30 keyboard, GC-32 Live Activity, Control Center tile) and V4_Gancho_Novel (GC-V6-1 Up next, GC-10 stack cursor, GC-09 masking, GC-25 capture glyph). V4_Gancho_Overview line: "Extended, same ids: GC-V4-1 filter tokens · … · GC-11 step pipeline · GC-12 prompt-to-transform · GC-20 retention dial + forget …".

## Shared tokens used by every card

| Element | Spec |
|---|---|
| Card | 1152 × 474, white, radius 14, shadow `0 1 3 rgba(0,0,0,.08)` |
| Card header (annotation) | at (20,16), gap 8: ID tag 22 h, padding 0 9, radius 7, 11 pt 800 mono, letter-spacing .04em. Black tag `#1D1D1F`/white = new id; purple tag `#E8E7FB`/`#3D3BB0` = extends a catalog item. Title 16 pt 800. `PROPOSAL` badge 18 h, radius 6, `#FFF1DB`/`#7A4B00`, 10.5 pt 800. `extends`/`new` 11 pt `#5B5B61`. Right: pills `impact X`, `effort Y` 20 h, radius 999, `#F2F2F5`, 11 pt 700 `#3A3A3F` |
| Mock area | (20,54), 660 × 400, radius 12, `#ECEDF0` |
| Panel frame `.pf` | (20,18) in mock, 620 × 360, `#F8F8F8` (or white where noted), radius 12, ring `0 0 0 1 rgba(0,0,0,.10)`, shadow `0 12 30 rgba(0,0,0,.18)`, 13 pt base |
| Annotation column | (700,54), width 432, 12 pt / 1.45 `#3A3A3F`; headings 10.5 pt 800 uppercase .06em `#5B5B61`; sources 10.5 pt `#5B5B61` |
| Chip `.cp` | 22 h, padding 0 8, radius 11, `#E4E4E6`, `#3A3A3F`, 11 pt 600, gap 5. Selected `.cp.on`: `#34C759` fill, `#0B2A14` text |
| Key cap `.kk` | min 18 × 18, padding 0 4, radius 5, white, ring 1 `#D6D6DA`, 11 pt 600 `#3A3A3F` |
| Button `.btn` | 24 h, padding 0 10, radius 7, white, ring 1 `#D6D6DA`, 12 pt 600 `#1D1D1F`, gap 6. Primary `.btn.g`: `#34C759` fill, `#0B2A14` text, no ring. Destructive text `#B3141B` |
| Selected row `.r.sel` | inset 6 left/right, 48 h, radius 10, `#E3F4E6`, 3 pt leading bar `#34C759` (top/bottom inset 8, radius 2) — not built: leading accent bars are banned; the selection is the wash inside a full 1 pt accent outline |
| Glass sheet | radius 14, `rgba(255,255,255,.92)`, ring 1 `rgba(0,0,0,.10)`, shadow `0 14 34 rgba(0,0,0,.22)` |
| Kind tints | link tile `#DDEFF9`/icon `#1F8FC0`; text `#E6E6E8`/`#6E6E73`; code `#E5E4FA`/`#5856D6`; secret icon `#D70015` |
| Fonts | SF Pro Text; mono = `ui-monospace, SF Mono` |

Only light appearance is drawn. No dark variant on this board.

## Board header (annotation, not UI)

- Tag `V4 · NOVEL` (fill `#34C759`, text `#0B2A14`), title `Find, transform and trust` 26 pt 800.
- Intro (13 pt/1.5 `#3A3A3F`, width 2340), verbatim: "Baseline to beat: **macOS 26 Spotlight clipboard** (⌘Space ⌘4 — a plain time list, plain text only, 8 h by default) and **Paste 7** (cards, pinboards, Intelligent Clipboard prediction, MCP). Each card is a proposal drawn in Gancho’s tokens (brand green #34C759, kind tints, 13 pt rows, 11 pt chips), names the screenshot it improves, what the code already has and what it still needs. Purple ids extend an existing catalog item; black ids are new. Research: research/clipboard-ui.md (2026-10-17)."
- Footer (bottom 24, 11.5 pt `#5B5B61`): "All mockups are proposals — none of these screens exists in v0.10.2. Sources are the pages listed under each card; web content was read as data only."

---

## Card 1 (28,150) — `GC-V4-1` · Search modes and filter tokens inside the field

Realises **GC-V4-1** (purple: extends). Header: `PROPOSAL` · `extends` · `impact H` · `effort M`.

Panel `.pf` 620 × 360, `#F8F8F8`.

1. **Search bar** — full width, 44 h, bottom border 1 `#E3E3E6`, padding 0 12, gap 6, left to right:
   - Magnifier icon 15 pt, stroke `#6E6E73`.
   - Token chip `app: Xcode` + `×` (token style: `#E6E5F8` fill, `#3D3BB0` text, `.cp` metrics; `×` is aria-hidden).
   - Token chip `type: code` + `×`.
   - Typed text `greeting` (sample), 14 pt.
   - Caret 1 × 18 `#C7C7CC`, pulses opacity 1 → .55 over 1.6 s only when Reduce Motion is off.
   - Right-aligned segmented control: container padding 2, radius 12, `#ECECEE`, gap 2; four 20 h segments `Exact` (selected, green `.cp.on`), `Fuzzy`, `Regex`, `Meaning` (transparent).
2. **Token completion popover** at (12,52), width 280, white, radius 10, shadow `0 8 24 rgba(0,0,0,.18)`, padding 6, 12 pt:
   - Header `ADD A FILTER · TAB` 10 pt 700 `#6A6A70`, padding 4 8.
   - Rows 26 h, padding 0 8, radius 6, gap 8; key in mono `#3D3BB0`, hint `#55555A`:
     - `device:` `MacBook Pro · iPhone` — highlighted row `#E3F4E6` (sample values).
     - `board:` `Seed board 1 · 2 · 3`
     - `before:` `today · 7d · a date`
     - `#` `tags`
3. **Result row** (`.r.sel`) at top 200: kind tile 34 × 34 radius 8 `#E5E4FA` with code icon 16 pt `#5856D6`; title `Example` 13 pt 700 at (56,7); preview mono 12 pt `#55555A` at (56,26): `greeting` (bold, highlight `#FFF3B0`) + ` = "Hello"`; meta `Xcode · 1 minute ago` 10 pt `#6A6A70` at right 10/top 7; key badge `⌘1` 15 h, radius 4, `#E2E2E4`, `#4A4A4F` 10 pt 600 at right 10/top 26. (sample)
4. **Bottom line** (12, bottom 12), 11 pt `#55555A`: `1 result · Exact · tokens save as a Saved filter with ⌘S`.

States drawn: one token row highlighted (keyboard focus in popover), `Exact` selected, row selected. Not drawn: hover, empty, error (invalid regex), token removal.

### Implementation notes (not UI)
- Improves: "Screenshot 04: “By meaning” takes its own row; Fuzzy / Exact / Regex have no control; app, type and board filters live in two chip rows above the list."
- Reuses: "PanelSearchModel modes (fuzzy default, exact, regex), ClipKindFilter, source-app menu, board rail, SavedFilterEditor, `clip.sourceDeviceName` (device: is possible today)."
- Needs (code check): "A token parser in the field and Tab completion; tokens map onto the existing filter state, so no new storage."
- Inspired by: "Paste Power Search and Pinboard Filters, Raycast ⌘P type filter, Spotlight Tab scoping in macOS 26." Sources: `https://pasteapp.io/updates · https://manual.raycast.com/clipboard-history`.
- The bottom line mixes a status (`1 result · Exact`) with an explanatory clause (`tokens save as a Saved filter with ⌘S`); treat the second half as a note until decided (see Feasibility).

## Card 2 (1220,150) — `GC-V6-5` · Jump to context from any result

Realises **GC-V6-5** (black: new). Header: `PROPOSAL` · `new` · `impact M` · `effort S`.

Panel `.pf` 620 × 360, `#F8F8F8`.

1. **Context header bar** 40 h, bottom border `#E3E3E6`, padding 0 14, gap 8, 15 pt `#6E6E73`: clock icon 15 pt; `Context · 2 min before and after` (`#1D1D1F`); right `esc back to results` 11 pt.
2. **Session list** at (10,52), insets 10. Rows 40 h, padding 0 10, radius 9, white, 4 pt apart, gap 10: time mono 11 pt `#55555A` (width 40) · kind tile 26 × 26 · text 12 pt.
   1. `14:01` · link tile · `developer.apple.com/documentation/appkit`
   2. `14:02` · text tile · `NSPanel · floating, non-activating`
   3. `14:02` · code tile · `panel.becomesKeyOnlyIfNeeded = true` (mono 12 pt 700) · right chip `match` (`.cp.on`, 20 h). Row fill `#E3F4E6` (the anchor result).
   4. `14:03` · text tile · `Fix: panel steals focus in full screen`
   5. `14:05` · link tile · `github.com/johnny4young/gancho/issues/212`
   (all rows sample)
3. **Bottom line** (12, bottom 12), 11 pt `#55555A`: `From any result (exact or By meaning) press` [`⌘`] [`J`] `— the session around it explains why it matched.`

Shortcuts drawn: `⌘J` enters context, `esc` returns to results.

### Implementation notes (not UI)
- Improves: "Screenshots 04–08: a search or By meaning result shows one row; the clips copied with it (the URL, the note, the fix) are lost."
- Reuses: "`clip.createdAt` index, sourceAppBundleID, the panel list and peek."
- Needs (code check): "Nothing new to store; a time-window query around the selected clip and a context mode in the list."
- Inspired by: "Paste Jump to History (Apr 2026)." Source: `https://pasteapp.io/updates`.

## Card 3 (28,648) — `GC-11` · One Transform: a step pipeline with before / after

Realises **GC-11** (purple: extends). Header: `PROPOSAL` · `extends` · `impact H` · `effort M`.

Panel `.pf` 620 × 360, `#F8F8F8`.

1. **Step strip** at (14,14), gap 6: chips white with ring 1 `#D6D6DA`, each with a 10 pt grid (drag-handle) icon `#8E8E93` and a trailing `×` `#8E8E93`:
   `Trim ×` `→` `JSON pretty ×` `→` `Base64 encode ×` then `+ step` (default `.cp`). Arrows `→` in `#8E8E93`.
2. **BEFORE box** (14,52) 290 × 200, white, radius 10, inset ring `#E3E3E6`, padding 10. Label `BEFORE` 10.5 pt 700 `#5B5B61` .04em. Content mono 11 pt, pre-wrapped (sample, note leading/trailing spaces):
   ```
     {"id":7,"name":"Ocean",
   "hex":"#008080"}  
   ```
3. **AFTER box** (316,52) 290 × 200, `#F2FBF4`, inset ring `#BFE6C8`. Label `AFTER · WILL PASTE` in `#1D7A34`. Content mono 11 pt, break-all (sample): `ewogICJpZCI6IDcsCiAgIm5hbWUiOiAiT2NlYW4iLAogICJoZXgiOiAiIzAwODA4MCIKfQ==`
4. **Recipe row** (14,266), gap 8: button `Save as recipe`; `shortcut` 11 pt `#55555A`; key caps `⌥` `⌘` `1`.
5. **Global line** (14,306), 11 pt `#55555A`: `Global:` [`⌃`] [`⌘`] [`V`] `pastes the current clipboard through the last transform.`
6. **Primary** at (right 14, top 266): `Paste result ↩` (green `.btn.g`).

### Implementation notes (not UI)
- Improves: "Screenshots 05–07: Transform ⌄, Smart paste ⌄ and 15 More-actions chips are three surfaces and none previews its output."
- Reuses: "TextRecipe (up to 8 `TextActionStep` s, `text_recipe` table), TextRecipeExecutor, TextRecipeReview, DevActions per kind."
- Needs (code check): "Reorderable step UI and a global “paste with last transform” shortcut; the engine already chains steps."
- Inspired by: "Pastebot filters with step preview and Paste with Last Filter, PowerToys custom format preview, ClipBook ⌘T transform search." Sources: `https://tapbots.com/pastebot2/help/05_filters/ · https://learn.microsoft.com/en-us/windows/powertoys/advanced-paste · https://mac.softpedia.com/get/Utilities/ClipBook.shtml`.
- Peek board draws the entry point (Transform ⌘T popover with sections Recipes / Text / Code · Swift / Smart paste · on-device); this card draws the pipeline state reached from it.

## Card 4 (1220,648) — `GC-12` · Describe the change: prompt-to-transform with a diff

Realises **GC-12** (purple: extends). Header: `PROPOSAL` · `extends` · `impact H` · `effort M`.

Panel `.pf` 620 × 360, `#F8F8F8`.

1. **Prompt field** (14,14), full width minus 14, 36 h, white, radius 10, focus ring 2 pt `#34C759`, padding 0 10, gap 8: sparkles icon 15 pt `#1D7A34`; text `make it a Markdown table, keep the hex codes` 13 pt (sample, typed); right `on-device` 10.5 pt `#55555A`.
2. **Diff box** (14,62), 180 h, white, radius 10, inset ring `#E3E3E6`, padding 10 × 12, 12 pt / 1.6. Label `WAS / WILL PASTE`. Mono 11.5 pt:
   - Removed (fill `#FCE3E2`, strikethrough): `Ocean #008080, Sand #E8D5B5`
   - Added (fill `#DDF3E2`), four lines: `| Name | Hex |` / `| --- | --- |` / `| Ocean | #008080 |` / `| Sand | #E8D5B5 |` (sample)
3. **Options row** (14,254), gap 8, 12 pt: switch ON 30 × 18 radius 9 `#34C759`, knob 14 white; label `Coaching · explain each edit`; right button `Save prompt as recipe`.
4. **Actions row** (14,290), gap 8: `↩ Paste original` (secondary), `⇧↩ Paste result` (primary green).
5. **Bottom line** (14, bottom 12), 11 pt `#55555A`: `Hidden when Apple Intelligence is unavailable — never falls back to a server.`

Shortcuts drawn: `↩` pastes the original, `⇧↩` pastes the result. Not drawn: coaching notes content, thinking/loading, model error, guardrail refusal.

### Implementation notes (not UI)
- Improves: "Smart paste offers five fixed rewrites (screenshot 20) and its result is not shown as a diff."
- Reuses: "Smart paste (ClipPeek+SmartPaste), Apple Intelligence on-device availability checks, Translate routing, TextRecipe for saving prompts."
- Needs (code check): "A free-text prompt path in the on-device rewrite call, a local word diff, optional coaching notes; macOS 26 only."
- Inspired by: "PowerToys Paste with AI and Coaching mode, Raycast Ask Clipboard, Paste Writing Tools." Sources: `https://learn.microsoft.com/en-us/windows/powertoys/advanced-paste · https://manual.raycast.com/clipboard-history · https://pasteapp.io/updates`.

## Card 5 (28,1146) — `GC-20` · Stepped retention dial and “forget the last N minutes”

Realises **GC-20** (purple: extends). Header: `PROPOSAL` · `extends` · `impact H` · `effort M`.

Panel `.pf` 620 × 360, **white**.

1. **Title** (16,14): `Keep clips for` 13 pt 700, 6 pt below.
2. **Three dial rows**, 44 h each: label column 120 wide, 12 pt (`Text`, `Images`, `Secrets`); track 372 × 28 (6 pt top margin).
   - Rail 2 pt `#E3E3E6` from x 4. Filled rail `#34C759` (Secrets: `#D70015`) from x 4 to the selected stop.
   - Eight stops, 8 × 8 circles, at x 0, 52, 104, 156, 208, 260, 312, 364 (52 pt pitch), top −3. Stops before the selection: white + 1.5 ring `#34C759`; selected: solid `#34C759`; after: white + 1.5 ring `#C7C7CC`.
   - Stop labels 10 pt `#55555A`, 24 wide centred, top 10: `30m` `1h` `8h` `24h` `7d` `30d` `1y` `∞`.
   - Values drawn (sample): **Text = `1y`** (fill width 312), **Images = `7d`** (fill width 208), **Secrets = `30m`** (first stop solid `#D70015`, fill width 0, every later stop grey = beyond the cap, disabled).
3. **Footnote** 11 pt `#55555A`: `Pinned clips and boards never expire. Secrets cannot go past their safety cap.`
4. **Forget sheet** (glass) at (300,206), 300 × 138, padding 12:
   - `Forget recent clips` 13 pt 700.
   - Chips (8 pt below, gap 6): `5 min`, `15 min` (selected), `60 min`.
   - Preview 11 pt `#55555A`: `7 clips will be removed · 2 pinned are kept` (counts sample).
   - Buttons (gap 6): `Cancel`, `Forget 7 clips` (destructive text `#B3141B`; the number follows the preview count).
5. **Caption** (16,250), width 270, 11 pt `#55555A`: `Type “forget” in the panel, or use the menu. Shows what goes before it deletes.`

### Implementation notes (not UI)
- Improves: "Screenshot 12: three pop-up menus (1 year, Use global ×2) and no way to undo the last few copies."
- Reuses: "`RetentionPolicy.perKind` (24h … 1y, never), sensitive lifetime 5/10/30 min, RetentionEngine, `purge_log` counters for the receipt."
- Needs (code check): "Shorter windows (30 min, 1 h, 8 h) in the policy enum; a time-window delete in DeletionCoordinator (today it deletes by id); a preview count before deleting."
- Inspired by: "Gboard stepped slider (beta), Raycast delete last 5/15/30 min, Alfred “clear”, Spotlight 30 min / 8 h / 7 d." Sources: `https://androidauthority.com/gboard-clipboard-duration-slider-apk-teardown-3698099 · https://manual.raycast.com/clipboard-history · https://www.alfredapp.com/help/features/clipboard/`.
- V4_Gancho_Settings draws GC-20 differently: "3 Retention (GC-20): the three pickers stay; a timeline above them shows the four windows (secrets · images · everything · never) in one line. Changing a picker moves its marker." See conflict in Feasibility.

## Card 6 (1220,1146) — `GC-V6-6` · Agent reads you can see as they happen

Realises **GC-V6-6** (black: new). Header: `PROPOSAL` · `new` · `impact M` · `effort S`.

Mock (no `.pf` at top):

1. **Menu-bar strip** 28 h across the mock, desktop sample gradient `#3E74AF → #4A80BC`. At (520,3): status-item pill 22 h, padding 0 8, radius 6, `rgba(255,255,255,.28)`, gap 5: hook glyph 14 pt white (stroke 2.2) + **dot** 8 × 8 `#5AC8FA`.
2. **HUD** (glass) at (300,36), 340 × 66: icon tile (14,14) 36 × 36 radius 9 `#E3EEF9` with terminal icon 18 pt `#2F7DE1`; `Claude read 3 clips` 13 pt 700 at (62,13); `Seed board 1 · 7 days · 14:02` 11 pt `#55555A` at (62,33); button `Revoke` (destructive text `#B3141B`) at right 12/top 20. (sample)
3. **Ledger panel** `.pf` (20,120) 620 × 260, white:
   - Title (16,14): `Access ledger` 13 pt 700 + `metadata only — never the query or clip content` 11 pt 500 `#55555A` (6 pt left margin).
   - Rows at top 44 / 84 / 124, insets 16, 34 h, radius 8, `#F5F5F7`, padding 0 10, gap 10, 12 pt. Columns: client (bold, 70) · tool (mono 11 pt, 120) · scope (flex, `#55555A`) · count (60, right) · time (46, right, `#55555A`):
     1. `Claude` · `search` · `Seed board 1 · 7 days` · `3 clips` · `14:02`
     2. `Cursor` · `get_clip` · `Marked clips` · `1 clip` · `13:40`
     3. `Codex` · `search` · `denied · secret veto` · `denied` (`#B3141B`) · `13:12`
   - Badge row (16,176), gap 8: chip `#E3EEF9`/`#1F5FA8` with terminal icon 11 pt and text `Exposed to agents`; then `badge on boards inside an active grant` 12 pt.
   - Caption (16,212) 11 pt `#55555A`: `Toggle: “Show a menu-bar dot when an agent reads” · Settings › Integrations`.

### Implementation notes (not UI)
- Improves: "Screenshot 19: MCP Access already has per-client grants, a privacy boundary and an access ledger, but a read is only visible if you open that window."
- Reuses: "`mcp_access_log` (tool, scope, resultCount, wasDenied), MCPClientGrant (scope, read-only / read-write, context pack with board + time window, expiry, revoke)."
- Needs (code check): "A live signal from the MCP runner to the app (dot + HUD), the client name on each log row, and a board badge for boards inside an active grant. Scope enforcement already exists."
- Inspired by: "Paste MCP (tools you choose and revoke); Android’s paste-access toast as the visibility model." Sources: `https://pasteapp.io/updates · https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling`.
- Settings toggle copy to add (from caption): `Show a menu-bar dot when an agent reads`, in Settings › Integrations.

## Card 7 (28,1644) — `GC-V6-7` · Suggested snippets and smart placeholders

Realises **GC-V6-7** (black: new). Header: `PROPOSAL` · `new` · `impact M` · `effort M`.

Panel `.pf` 620 × 360, white.

1. **Library sidebar** (0,0) 230 wide, full height, `#FBFBFB`, right border `#E3E3E6`, padding 12, 12 pt:
   - `Library · Snippets` 11 pt 700 `#6E6E73` + `2/20` (500) — Free-tier meter (sample count).
   - Snippet rows 24 h, gap 8, 4 pt apart: list icon 13 pt `#6E6E73` · name · right key cap keyword: `Seed sign-off` [`;sig`]; `Seed greeting` [`hi`].
   - 16 pt below: `SUGGESTED · 2` 11 pt 700 `#1D7A34`.
   - Suggestion card (6 pt below): radius 9, `#F2FBF4`, inset ring `#BFE6C8`, padding 8: `Cra. 43A #1-50…` 700; `pasted 5× in 2 weeks` 11 pt `#55555A`; buttons 22 h padding 0 8 gap 4: `Keep` (green), `Never`, `Dismiss`. (Only one of the two counted suggestions is drawn.)
2. **Editor** (right of sidebar, x 246):
   - Title `Follow-up` 16 pt 700 at top 14.
   - Body box (246,46), 150 h, radius 10, `#F4F4F5`, inset ring `#DCDCDF`, padding 10, mono 12 pt / 1.7. Lines:
     1. `Hi ` + token `{name}` (`#F6E3C4`/`#8A4F00`) + `, as promised:`
     2. token `{clipboard | trim}` (`#E3EEF9`/`#1F5FA8`)
     3. `I will check back on ` + token `{date +2d}` (`#E6E5F8`/`#3D3BB0`) + `.`
     4. token `{cursor}` (`#E4E4E6`)
   - `Insert placeholder` 11 pt 700 `#4A4A4F` at top 208.
   - Chip row (top 228, wrap, gap 6): `{field}` `{clipboard}` `{clipboard offset=1}` `{date}` `{cursor}` `| trim` `| uppercase`.
   - Caption (top 300) 11 pt `#55555A`: `{date} fills with a date picker; {field} keeps today’s fill sheet.`

Token colour legend (drawn): field = amber, clipboard = blue, date = purple, cursor = grey.

### Implementation notes (not UI)
- Improves: "Screenshot 23: snippets support {field} only; the reuse-based suggestion exists but is a one-off banner in the panel."
- Reuses: "`recordUseAndSnippetSuggestion` (threshold 3 uses), `uses` and `keyword` columns, SnippetFillSheet, the {field} parser."
- Needs (code check): "A persistent “Suggested” group with Keep / Never / Dismiss (needs a never-suggest flag); placeholder engine for {clipboard}, {date}, {cursor} and modifiers."
- Inspired by: "TextExpander Suggested Snippets (Keep / Drop / Delete, date picker), Raycast dynamic placeholders, Espanso forms." Sources: `https://smilesoftware.com/blog/entry/all-about-suggested-snippets · https://manual.raycast.com/dynamic-placeholders · https://espanso.org/`.

## Card 8 (1220,1644) — `GC-V6-8` · iPhone: Up next in the keyboard, capture state in Control Center

Realises **GC-V6-8** (black: new). Header: `PROPOSAL` · `new` · `impact M` · `effort M`.

Mock contains three iOS surfaces:

1. **Phone** at (24,14), 250 × 370, radius 34, `#F2F2F7`, bezel 6 pt `#1C1C1E`.
   - Host app card (14,30), 120 h, white, radius 12, padding 10, 12 pt `#55555A`: `Messages · reply to Ana`; bubble (8 pt below) 30 h radius 15 `#F2F2F7` padding 6 × 10 `#1D1D1F`: `Sure, here it is: |` (sample).
   - **Keyboard** bottom 200 h, `#D1D3D9`, padding 8:
     1. **Up next row** 44 h, radius 10, white, ring 2 pt `#34C759`, padding 0 10, gap 8, 12 pt: `UP NEXT` 10 pt 800 `#1D7A34`; `Cra. 43A #1-50, Envigado` (single line, ellipsis).
     2. **Secret row** 6 pt below, 38 h, radius 10, white: lock icon 13 pt `#D70015`; mono `sk_live_••••4Q2v`; right countdown `0:45` 10 pt `#9A5A00`.
     3. **Text row** 38 h: text icon 13 pt `#6E6E73`; `Best regards, Gancho`.
     4. **Board chips** 8 pt below, gap 6, 24 h: `All` (selected green), `Seed board 1`, `Seed board 3` (white).
     (all values sample)
2. **Control Center control** at (310,30), 150 × 150, radius 34, `#3A3A3C`, white, centred column gap 8: hook glyph 34 pt; `Capturing` 13 pt 700; `tap to pause 1 h` 11 pt `#D1D1D6`.
3. **Live Activity** (compact banner) at (476,30), 164 × 70, radius 24, `#1C1C1E`, padding 10 × 14, 11 pt: `Gancho · 2 waiting` 12 pt 700; `stack 3 of 5 · next: Envigado` `#D1D1D6`, 4 pt below. (sample)
4. **Caption** (310,200), width 330, 12 pt / 1.5 `#3A3A3F`: "Control Center control shows and toggles the capture state (today’s control only saves the clipboard). The Live Activity carries the paste-stack cursor. The keyboard top row shows Up next and masks secrets with their countdown."

### Implementation notes (not UI)
- Improves: "GanchoPhone_Current: the keyboard and widgets list recents only; the Control Center control saves the clipboard but does not show or change the capture state."
- Reuses: "GanchoKeyboard, SaveClipboardControl, ClipLiveActivity / ClipActivityController, shared sensitive masking."
- Needs (code check): "The Up next ranking from GC-V6-1 shared through the app group; a state-toggle ControlWidget; stack position in the activity content state."
- Inspired by: "Paste Keyboard, PastePal Control Center toggle and Live Activity, Paste 7 prediction." Sources: `https://pasteapp.io/blog/introducing-paste-keyboar · https://apps.apple.com/app/id1503446680` (first URL is truncated as drawn).

---

## Coverage

| Board element | ID(s) |
|---|---|
| Board header tag, title, intro | context only |
| Card 1: search bar, token chips, mode segmented control | GC-V4-1 |
| Card 1: `ADD A FILTER · TAB` popover (device/board/before/#) | GC-V4-1 |
| Card 1: selected result row with highlight | GC-V4-1 (row itself kept, no change) |
| Card 1: bottom line `1 result · Exact · …⌘S` | GC-V4-1 (status + note; ⌘S blocked) |
| Card 2: context header, 5-row session list, `match` chip, ⌘J line | GC-V6-5 |
| Card 3: step strip, BEFORE/AFTER, Save as recipe + ⌥⌘1, ⌃⌘V line, Paste result | GC-11 |
| Card 4: prompt field, diff, Coaching switch, Save prompt as recipe, paste buttons, availability line | GC-12 |
| Card 5: three-row dial, footnote | GC-20 |
| Card 5: Forget recent clips sheet + caption | GC-20 |
| Card 6: menu-bar dot | GC-V6-6 (also touches GC-25 glyph states, V4_Gancho_Novel) |
| Card 6: HUD with Revoke | GC-V6-6 |
| Card 6: ledger rows, `Exposed to agents` badge, Settings toggle caption | GC-V6-6 |
| Card 7: Library sidebar with `SUGGESTED · 2` card | GC-V6-7 |
| Card 7: placeholder editor, `Insert placeholder` chips, caption | GC-V6-7 |
| Card 8: keyboard Up next row | GC-V6-8 (depends on GC-V6-1) |
| Card 8: keyboard masked secret row with countdown | GC-V6-8 (conflicts with GC-09 / keyboard policy) |
| Card 8: keyboard board chips, text row | kept, no change (shipped GC-30) |
| Card 8: Control Center `Capturing` control | GC-V6-8 |
| Card 8: Live Activity `stack 3 of 5` | GC-V6-8 (depends on GC-10) |
| All Improves / Reuses / Needs / Inspired by columns, sources | context only |
| Footer line | context only |

No numbered pins are drawn on this board.

---

## Feasibility

Cross-cutting facts verified in code:

- **Feature flags:** there is no runtime feature-flag system. `Packages/GanchoKit/Sources/GanchoKit/DebugFlags.swift` is `#if DEBUG` only (`forcePro`). Gating patterns available: (a) a preference that hides the surface (e.g. `IntelligencePreferences`, `ClipboardCore/IntelligencePreferences.swift` — its decoder defaults **missing keys to ON**, so an off-by-default feature needs `decodeIfPresent … ?? false`); (b) launch-argument gates used for UI tests (`IntelligenceCapability.simulateSequoiaArgument`); (c) not shipping the UI entry point until done. Unfinished work can stay behind (c) on a branch; a release-time hide would need a new compile-time `#if` or a hidden default.
- **Schema:** append-only migrator `GanchoKit/GanchoDatabaseMigrator.swift:7-34`, last id `v26-embedding-cleanup`. Any new table/column is a `v27+` migration with `DatabaseMigrationTests` updated.
- **Min OS:** macOS 15.4 / iOS 26. FoundationModels needs macOS 26 → `#available(macOS 26, *)` (iOS already 26). ControlWidget toggles are iOS 18+ → no fence on iOS 26.
- **Mac app is not sandboxed** (`Apps/GanchoMac/Gancho.entitlements` has no `app-sandbox`) and already uses `DistributedNotificationCenter` for the menu-bar helper channel (`GanchoMacApp.swift:177`, `GanchoMenuBarCommand.swift:49`).

### GC-V4-1 — Search modes and filter tokens inside the field (UI + feature)

- **Changes:** replace the separate `By meaning` row (`Apps/GanchoMac/MeaningSearchControls.swift:9`, toggle bound to `search.meaningEnabled`) and add a 4-way mode control (Exact/Fuzzy/Regex/Meaning) inside `SearchField` (`Apps/GanchoMac/PanelView.swift:556`). Add a token parser + Tab completion that turns `app:`, `type:`, `board:`, `device:`, `before:`, `#tag` into removable chips mapped to `PanelSearchModel` state.
- **Exists:** `PanelSearchModel` (`Packages/GanchoKit/Sources/GanchoAppCore/PanelSearchModel.swift:41`) has `mode` (`ClipSearchQuery.Mode` exact/fuzzy/regex, `:49`), `kindFilter` (`:116`), `selectedBoardID` (`:123`), `selectedSourceAppBundleID` (`:128`), `meaningEnabled` (`:42`). `ClipSearchQuery` already has `dateRange` (`GanchoKit/ClipSearch.swift:23`) and SQL for it (`GRDBClipboardStore+SearchFilters.swift:20`). Today **no panel control sets `mode`** — only `SavedFilterEditor.swift:37-38` does. `clip.sourceDeviceName` column exists (`GanchoDatabaseMigrator.swift:104`).
- **New:** parser (pure, in GanchoAppCore); `device` filter (`ClipSearchQuery`, `SmartCollectionRule`, `PanelSearchModel.Context`, SQL clause); `before:` mapping to `dateRange`; multi-board (`board: 1 · 2 · 3` implies OR of several boards — today one `boardID`); `#tag` filter (tags are a JSON text column `clip.tags`, used internally for `lang:` snippet tags, `SnippetLibrary.swift:140-149`; there is no user tag UI); `type:` vocabulary must map to `ClipKindFilter` cases (all/links/code/colors/images/secrets — `type: code` maps to `.code`). `SmartCollectionRule` (`SmartCollections.swift:8`) needs new optional fields (`deviceName`, date bound, tags) to save tokens; it is Codable JSON in `saved_filter.definition` so new optional keys are backward compatible.
- **Preferences/data:** none new except SavedFilter fields above.
- **Performance:** `device:` has no index (only `idx_clip_dedupe (contentHash, sourceDeviceName)`), `#tag` needs `json_each` over every row — both are table scans at 100k rows unless intersected with FTS or a new index (`clip(sourceDeviceName, createdAt)`). Regex mode is already a scan (`ClipSearch.swift:12`). Note `refresh()` caps durable search at 100/500 rows (`PanelSearchModel.swift:378`). Gate perf in the `GANCHO_PERF=1` harness, never `make test`.
- **Privacy:** none beyond today (tokens are local query state; never log the query).
- **Deps:** GC-08 (no-results counts per mode, PanelStates), GC-V4-3 (scope/app chips with counts, Panel board) — decide which chips survive once tokens exist; GC-V4-10 (iPhone filter chips) for parity.
- **Verify:** Swift Testing for the parser (each token, Tab completion, invalid date, unknown key stays text, `×` removal); `PanelSearchModelTests` for token→state; SQL plan test for device/tag filters; XCUITest: type `app:`, Tab, chip appears with id e.g. `search-token-chip`; snapshot vs card 1.
- **BLOCKED:** (1) `⌘S` in the panel already promotes the selected clip to a snippet (`PanelView.swift:644-650`); the board says tokens save as a Saved filter with `⌘S`. Which binding wins? (2) Is `#tag` in scope given there is no user-facing tag feature? (3) Is "Meaning" a fourth exclusive mode, or still additive to Fuzzy/Exact (today Meaning appends related rows to conventional results, `PanelSearchModel.swift:439-446`)?

### GC-V6-5 — Jump to context from any result (feature)

- **Changes:** `⌘J` on a selected result switches the list to a context mode: clips within ±2 min of the anchor, anchor highlighted with `match`; `esc` returns to the prior results and selection.
- **Exists:** `clip.createdAt` is indexed (`GanchoDatabaseMigrator.swift:96`, `.indexed()`), `idx_clip_browse (isPinned DESC, createdAt DESC)` (`:306`). `⌘J` is unused in `PanelView.swift:558-665`. `esc` currently hides the panel (`:605-613`) — context mode must intercept it first.
- **New:** store query `items(createdBetween:)` (archived/expired/pending-delete filtered, `unexpiredPredicate`); a `PanelSearchModel` context state (save/restore query, mode, filters, selection); header bar UI; time column in rows.
- **Data caveat:** a recopy only bumps `lastUsedAt`, not `createdAt` (`GRDBClipboardStore.swift:422-436`), and pastes also bump `lastUsedAt`. There is no per-copy event log, so "the session around it" is approximate. Choosing `createdAt` vs `IFNULL(lastUsedAt, createdAt)` changes results.
- **Privacy:** sensitive rows must stay masked; private-mode gaps simply show nothing.
- **Performance:** bounded index range scan; negligible.
- **Deps:** none hard; shares list chrome with GC-V4-1.
- **Verify:** unit test window query (boundaries, pinned rows, expired rows excluded); `PanelSearchModelTests` enter/exit restores state; XCUITest `⌘J` then `esc` with id `context-header`; snapshot vs card 2.
- **BLOCKED:** Which timestamp anchors the window (first copy `createdAt` or last activity)? A recopied clip shows at its original date today.

### GC-11 — One Transform: step pipeline with before / after (UI + feature; also on Peek and Panel boards)

- **Changes:** a step strip (add `+ step`, remove `×`, drag to reorder) with live BEFORE / AFTER, `Save as recipe` with a per-recipe global shortcut (`⌥⌘1`), `Paste result ↩`, and a global `⌃⌘V` "paste current clipboard through the last transform".
- **Exists:** `TextRecipe` (≤ 8 steps, `GanchoKit/TextRecipe.swift:62-66`), `text_recipe` table (`GanchoDatabaseMigrator.swift:67`), `TextRecipeExecutor` (`GanchoAppCore/TextRecipeExecutor.swift:6`, chains steps, 1 MiB limit), `TextRecipeReview` sheet (`Apps/GanchoMac/TextRecipeReview.swift`, Before/After + `Copy result` only, `:74`). `DevActions` jsonPretty/base64Encode (`GanchoAI/DevActions.swift:17-19`). `KeyboardShortcuts` names catalog (`Apps/GanchoMac/GlobalShortcuts.swift:8`).
- **New:** (a) `TextActionCatalog` (`TextRecipe.swift:41-56`) only contains `PasteTransform` cases + 5 whitespace/PII/context actions — **JSON pretty and Base64 encode are not recipe steps today**; add `dev.*` descriptors and executor cases (executor in GanchoAppCore already imports GanchoAI, so no layering problem). (b) Reorderable strip UI. (c) Delivery by **paste** — docs/TEXT-RECIPES.md says recipes only "Copy result" and never paste automatically; changing to paste needs the paste-back path with the same revalidation. (d) Recipe→shortcut binding: new persisted mapping (recipe UUID → `KeyboardShortcuts.Name("recipe-<uuid>")`), local only. (e) New global name `paste-with-last-transform` (+ persisted "last transform" recipe id/steps in preferences). 
- **Platform:** macOS only (panel). No #available. Global hotkeys via KeyboardShortcuts (Carbon); `⌘V` synthetic paste needs Accessibility (as today).
- **Privacy:** `⌃⌘V` reads the live pasteboard: must skip Concealed/Transient/AutoGenerated and sensitive content, and never log text. Last-transform state stores steps, never content.
- **Performance:** executor is detached and capped at 1 MiB; live preview should debounce and cap display at 8,000 characters as today.
- **Risks:** a global `⌥⌘1` also fires while the panel is key, where `⌘1` quick-paste is matched with `modifiers.contains(.command)` (`PanelView.swift:628-635`) — the panel handler would also match `⌥⌘1` if the global is not registered. A default `⌃⌘V` may collide with other apps; existing defaults are `⇧⌘V` panel and `⌃⌥T` screen text.
- **Deps:** Peek-board Transform popover (`⌘T`), GC-12 (shares preview/paste row and "save as recipe"), GC-V4-2 (paste button names target app).
- **Verify:** executor unit tests for new `dev.*` steps (chain Trim→JSON pretty→Base64 equals expected bytes; JSON pretty key order/spacing comes from DevActions, so do not compare to the board sample); store test recipe-shortcut mapping; XCUITest add/remove/reorder steps with ids `transform-step-chip`, `transform-paste-result`; snapshot vs card 3.
- **BLOCKED:** (1) Should `⌃⌘V` ship with a default binding or be user-recorded like `cyclic-paste`? (2) Recipes move from copy-only to paste — confirm, since docs/TEXT-RECIPES.md publishes the copy-only contract.

### GC-12 — Describe the change: prompt-to-transform with a diff (feature; also on PanelStates board)

- **Changes:** free-text prompt runs on the on-device model; result shown as a word/line diff (`WAS / WILL PASTE`); optional Coaching notes; `↩ Paste original` / `⇧↩ Paste result`; `Save prompt as recipe`; whole surface hidden when Apple Intelligence is unavailable.
- **Exists:** `SmartPasteService.transform` with fixed `SmartPasteAction` cases (`GanchoAI/SmartPasteService.swift:15-22`, `:184-199`), fresh `LanguageModelSession` per call, `ModelInputSanitizer` redaction before the model, 3,000-char clamp (`:73`); availability via `SmartPasteService.isAvailable` and `IntelligenceCapability` (`GanchoAI/IntelligenceCapability.swift`); peek Smart paste menu + result box (`Apps/GanchoMac/ClipPeek+SmartPaste.swift:38-97`); preference `IntelligencePreferences.smartPaste`.
- **New:** a `transform(_:prompt:)` path (user prompt as the request, frozen safety instructions from `PromptCatalog` as system instructions); local diff algorithm (pure, GanchoKit/AppCore); coaching (second structured response or `@Generable` notes); `⇧↩` handling in the peek.
- **Platform:** FoundationModels → `#available(macOS 26, *)` and `SystemLanguageModel.default.availability == .available`; on macOS 15.4–25 the field must not render. iOS 26 detail view (`Apps/GanchoiOS/ClipDetailView+SmartPaste.swift`) only if parity is wanted (not drawn).
- **Privacy:** on-device only, never a server (drawn rule). Prompt text and results must not be logged or put in diagnostics. Sensitive clips stay gated off (as today). Clip content can carry prompt injection; the diff review before paste is the mitigation.
- **Performance:** model latency seconds; 3,000-char clamp means long clips are truncated silently — the diff must show only what was sent, or the UI must say it was clipped.
- **Deps:** GC-11 (shared result/paste row, recipes), GC-V5-5 (Intelligence window), PanelStates GC-12 card (the "today" state).
- **Verify:** unit tests for the diff (pure); prompt-path tests with a fake engine (no FoundationModels in `make test`); UI test with `-simulate-sequoia-capabilities` asserts the field is absent; snapshot vs card 4.
- **BLOCKED:** `Save prompt as recipe` conflicts with the recipe contract: `TextActionStep.validate()` rejects any parameters (`TextRecipe.swift:31`), the executor is "Deterministic execution only. No … model sessions" (`TextRecipeExecutor.swift:5`), and docs/TEXT-RECIPES.md says "no scripts, provider calls, models". Should model prompts become a new recipe step kind (version 2, parameterised, non-deterministic, macOS 26 only) or a separate "saved prompts" list?

### GC-20 — Stepped retention dial and “forget the last N minutes” (UI + feature; also on Settings board)

- **Changes:** per-kind stepped dials (Text, Images, Secrets) with stops 30m…∞ and the secret cap visible; a "Forget recent clips" flow (5/15/60 min) with a preview count and pinned-kept count, reachable by typing `forget` in the panel or from the menu.
- **Exists:** `RetentionPolicy` (`GanchoKit/RetentionPolicy.swift:6-46`): `Window` = 24h, 7d, 30d, **90d, 180d**, 365d, never; `global`; `perKind`; `sensitiveLifetime` default 600 s. UI is three pickers + sensitive picker 5/10/30 min (`Apps/GanchoMac/RetentionSettingsTab.swift:11-44`). Purge in `RetentionEngine.runPurge` (`GanchoKit/RetentionEngine.swift:25-119`) tombstones synced rows before delete and logs `purge_log`. `DeletionCoordinator` (`GanchoAppCore/DeletionCoordinator.swift:38`) is by id, 6 s undo window.
- **New:** `Window` cases `30m`, `1h`, `8h` (raw values are persisted in `retention-policy` JSON — additive cases are safe, removing 90d/180d is not); a time-window query `ids(createdSince:)` excluding pinned/board/snippet rows, feeding `DeletionCoordinator.beginDeletion(_ ids:)` (batch already supported, `:131`) so Undo still works; preview counts query; panel `forget` command; menu item; dial control (Slider with stops or custom).
- **Privacy/sync:** forgetting synced rows must tombstone (delete everywhere) — use the sync-aware delete, not `deleteLocalOnly`. The receipt counts can go to `purge_log`/private receipt (no content).
- **Performance:** `createdAt` index range; batch delete ≤ minutes of clips — small. Sub-day windows mean `runPurge` must run more often than today's schedule (check the timer) or 30 m retention is not honoured.
- **Deps:** GC-17/GC-21 (Settings/Privacy Center), GC-09 (secret keep-longer capped by retention), GC-07 (private mode auto-off).
- **Verify:** `RetentionPolicy` decode of old blobs; `RetentionEngine` tests for 30m/1h/8h; forget-window tests (pinned/board/snippet kept, sensitive included, tombstones written); XCUITest forget sheet with ids `forget-recent-sheet`, `forget-window-15`; snapshot vs card 5.
- **BLOCKED:** (1) Board conflict: V4_Gancho_Settings says "the three pickers stay; a timeline above them", Novel2 replaces them with a dial. Both are v4, so precedence does not settle it, but the catalog title matches Novel2. Which one ships? (2) The dial has no row for the **global** window (`Keep history for`), and `Text` maps only to kind `.text` (links, code, colours follow global). Where do other kinds and the global go? (3) The secrets row starts at 30m, but today's secret lifetimes are 5/10/30 min and the code defaults to 10 min: are 5 and 10 min dropped? (4) 90 days and 6 months are not on the dial: migrate users who chose them to what? (5) Typing `forget` in the search field collides with searching for the word "forget". Is it a command prefix?

### GC-V6-6 — Agent reads you can see as they happen (feature)

- **Changes:** a menu-bar dot when an MCP client reads, a HUD (`Claude read 3 clips`, scope, time, `Revoke`), ledger rows showing client + tool + scope + count + time, an `Exposed to agents` badge on boards inside an active grant, and a Settings › Integrations toggle `Show a menu-bar dot when an agent reads`.
- **Exists:** ledger table with `grantID`, `clientName`, `accessMode`, `denialReason` since v19 (`GanchoKit/MCPAccessStore.swift:58-75`); the ledger UI **already shows the client name** (`Apps/GanchoMac/MCPAccessView.swift:224`, `PrivacyCenterView.swift:220`), so that "Needs" item is already done. Runner logs each call (`GanchoMCP/MCPToolRunner.swift:362-376`). Grants with context pack board + time scope (`GanchoKit/MCPAccess.swift:51-118`). Revoke exists in MCP Access. Integrations tab (`Apps/GanchoMac/IntegrationsSettingsTab.swift`).
- **New:** cross-process signal: the MCP server runs in the `gancho mcp` CLI process (`Sources/gancho/GanchoCLI.swift:48`), not the app. Since the Mac app is unsandboxed and already observes distributed notifications, the CLI can post a **content-free** distributed notification after each logged access; the app then reads the newest ledger row. The status item is drawn by the paint-only helper (`Apps/GanchoMenuBarHelper/main.swift:117-123`) from `MenuBarStatusIcon` (`Apps/GanchoMac/GanchoMenuBarCommand.swift:187`) — the dot needs a new icon state carried over the bridge, plus the fallback `StatusItemController.swift:108`. New HUD window (reuse `ToastPresenter.swift` style). Board badge: compute boards covered by active grants (`contextPack.boardID`). New preference (off/on default to decide).
- **Privacy:** notification must carry no query, no clip ids, no content (the ledger already holds none). The HUD scope label `Seed board 1 · 7 days` comes from the grant, not the request.
- **Performance:** one indexed ledger read per notification (`occurredAt` indexed); throttle bursts (an agent can call many times per second).
- **Deps:** GC-25 (capture-state glyph badges on the same status item, V4_Gancho_Novel), GC-24 (status menu mini-panel), GC-21 (Privacy Center Verify group shows MCP).
- **Verify:** unit test the notification payload is empty / name-only; `MCPToolRunnerTests` that logging triggers the signal; UI test with a seeded ledger event shows HUD id `agent-read-hud`, Revoke flips the grant; snapshot vs card 6.
- **BLOCKED:** (1) Tool names drawn as `search` but the real tool is `search_clips` (`MCPAccess.swift:216`) — use the real names? (2) The scope column shows the grant's board and window, but the log stores only `grantID`; if a grant is edited later, rows would show the new scope. Snapshot scope into the log (new column) or render current?

### GC-V6-7 — Suggested snippets and smart placeholders (feature)

- **Changes:** a persistent `SUGGESTED` group in the Library with `Keep` / `Never` / `Dismiss`; new placeholders `{clipboard}`, `{clipboard offset=1}`, `{date}`, `{date +2d}` (date picker), `{cursor}`, modifiers `| trim`, `| uppercase`, and an `Insert placeholder` chip row in the snippet editor.
- **Exists:** one-shot suggestion at exactly 3 uses (`SnippetLimits.promotionSuggestionUseThreshold = 3`, `GanchoKit/SnippetLibrary.swift:10`; `recordUseAndSnippetSuggestion` `:236-264`, excludes sensitive and masked kinds); Free cap 20 (`:7`); `uses`, `keyword` columns (`GanchoDatabaseMigrator.swift:256-261`); `{field}` / `{field:default}` parser (`GanchoKit/SnippetTemplate.swift`); `SnippetFillSheet` (`Apps/GanchoMac/SnippetFillSheet.swift`); editor `Apps/GanchoMac/LibraryView+SnippetEditor.swift`.
- **New:** (a) suggestion state: `Never` needs a persisted flag — prefer a local-only table (e.g. `snippet_suggestion(clipID, state, decidedAt)`) over a new `clip` column, because `clip` rows sync; (b) the drawn copy `pasted 5× in 2 weeks` needs a time-windowed count, but only a lifetime `uses` counter exists — needs a use-event log (same gap as GC-V6-1's per-paste log); (c) placeholder engine with a new grammar (current regex only matches `[A-Za-z0-9_ ]` names, so `{clipboard | trim}` is today pasted literally); (d) date picker in the fill sheet; (e) `{cursor}`: after the synthetic `⌘V`, move the caret back by N characters with synthetic arrow keys (Accessibility, already required for paste-back).
- **Privacy:** `{clipboard}` reads the live pasteboard at insert time: skip Concealed/Transient/AutoGenerated and detected secrets; `{clipboard offset=1}` reads history (respect masked kinds). No content in logs.
- **Back-compat risk:** existing snippets that already use `{clipboard}`, `{date}` or `{cursor}` as plain user fields would change meaning — migration or escaping rule needed.
- **Deps:** GC-V4-5/6/7/13 (Library board), GC-V6-1 (shared use-event log).
- **Verify:** parser/filler unit tests (each placeholder, modifiers, offsets, unknown token literal, old `{name:World}` unchanged); suggestion state tests (Keep promotes respecting Free cap, Never persists, Dismiss re-offers later); UI test ids `snippet-suggestion-keep`, `insert-placeholder-chip`; snapshot vs card 7.
- **BLOCKED:** (1) Is a use-event log approved (needed for "in 2 weeks"), or should the copy show lifetime uses? (2) How should existing snippets with `{clipboard}`/`{date}`/`{cursor}` fields migrate? (3) Should the Suggested group also replace the panel banner (`presentReuseSuggestion`, `Apps/GanchoMac/AppModel.swift:926-929`) and the iOS `ReuseSuggestionBanner.swift`?

### GC-V6-8 — iPhone: Up next in the keyboard, capture state in Control Center (feature; overlaps iPhoneSurfaces and Novel)

- **Changes:** keyboard top row `UP NEXT` (predicted clip), masked secret row with countdown, Control Center control that shows and toggles capture (`Capturing` / `tap to pause 1 h`), Live Activity carrying the paste-stack cursor (`stack 3 of 5 · next: …`).
- **Exists:** keyboard (`Apps/GanchoKeyboard/KeyboardModel.swift`, app-group store only with Full Access, thumbnail cap 24); `KeyboardClips` **excludes sensitive clips entirely** (`GanchoKit/KeyboardClips.swift:5-17`); `SaveClipboardControl` is a `ControlWidgetButton` (`Apps/GanchoWidgets/SaveClipboardControl.swift`); Live Activity content state = preview, kind symbol, isSensitive, sync (`GanchoKit/ClipActivity.swift:10-25`), 3-minute self-dismissing (`Apps/GanchoiOS/ClipActivityController.swift:18`).
- **New:** (a) Up next ranking computed in the app (GC-V6-1, not built) and written to the app group for the keyboard; the keyboard extension has a tight memory budget, so it must read a precomputed id, not run a ranker or model. (b) A `ControlWidgetToggle` with `SetValueIntent` and shared state (iOS 18+ API, no fence on iOS 26); WidgetKit `ControlCenter.shared.reloadControls` on change. (c) `stackIndex`/`stackCount`/next preview in `ContentState` (additive Codable fields). (d) Masked secret row with expiry countdown (`Text(timerInterval:)`).
- **Privacy:** Up next preview in the keyboard must be masked-safe; Live Activity preview stays masked as today; Control Center shows state only.
- **Deps:** GC-V6-1 (Up next, Novel), GC-10 (stack cursor, Novel), GC-09 (masked everywhere, Novel), GC-30/GC-V4-19 (keyboard), GC-32/GC-V4-17 (Live Activity actions), GC-25 (capture state).
- **Verify:** unit tests for the shared Up next payload and ContentState coding; widget timeline/control previews; XCUITest on the keyboard host (`make test-ui-ios`) for the Up next row id `keyboard-up-next`; snapshot vs card 8.
- **BLOCKED:** (1) iOS has **no capture state**: capture on iPhone is user-initiated (paste control, share sheet, intents); `CapturePreferences.isPrivateModePaused` exists only for the Mac monitor (`ClipboardCore/MacPasteboardMonitor.swift:57-64`). What does the control pause — iOS-side intents, or the Mac via sync (cross-device control does not exist)? (2) iOS has **no paste stack** (`PasteStack` is used only by the Mac `AppModel`), so `stack 3 of 5` has no source on iPhone. Is an iOS stack in scope? (3) The keyboard draws a masked secret row, but code excludes secrets from the keyboard on purpose, and GC-09 (Novel) says "Never in widgets, the keyboard preview, Spotlight or MCP results." Which rule wins?

---

## Owner notes

- Pick state: GC-V4-1, GC-V6-5, GC-11, GC-12, GC-20, GC-V6-6, GC-V6-7, GC-V6-8 are all **pick**, with **no pick note** on any of them.
- No owner comment thread targets this board. General rules that apply: compare every proposal with the current UI and only propose what beats it, and code wins over v2 boards and site screenshots (2026-10-17); each piece of data appears once per screen (cross-app rule); annotations ("Improves / Reuses / Needs / Inspired by", in-mock captions, IDs, PROPOSAL badges) are not UI.

## IDs mentioned that are not realised here

- **GC-V6-1** (Up next, catalog item on V4_Gancho_Novel): GC-V6-8 depends on its ranking.
- Cross-board references only (not drawn here): GC-09, GC-10, GC-25 (Novel), GC-30, GC-32 (iPhoneSurfaces, legacy ids with v4 items GC-V4-17/GC-V4-19), GC-V4-3, GC-08 (Panel/PanelStates).
