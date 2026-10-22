# V4_Gancho_Onboarding — spec

- **Board:** `V4_Gancho_Onboarding.dc.html` (page title "Gancho onboarding v4")
- **Canvas:** 2000 × 1140, background `#ECEDF0`, radius 12, padding 24 × 28, vertical gap 14.
- **What it shows:** the Mac first run grows from three steps to four (promise → permission → shortcuts → live first copy that ends in the real panel); the iPhone keeps today's single welcome as screen 1 and adds a screen 2 that explains "Sensed, not read".
- **Related Current board:** `GanchoWelcome_Current` (three steps, 520 × 420 plus the title bar; step 1 live clips + importer, step 2 Accessibility with live status, step 3 panel shortcut then the real panel; Skip on every step).
- **Drawn appearance:** light only. The stylesheet has `.ph.dark` / `.panel.dark` rules, but no frame uses them, so no dark variant is specified.
- **Realises:** GC-35, GC-36. Applies owner decision 2 (brand mark replaces SF `paperclip` at `OnboardingView.swift:58`, GC-V7-1). Depends on GC-V5-2 (accent ink) for link and green text colours.

Units: board px = pt. Colours are hex as drawn. Common inks: `#1D1D1F` primary text, `#5B5B61` secondary text, `#6E6E73` tertiary, `#1F7A3A` green ink (links, icons, status; this is the accent-ink token proposed by GC-V5-2, not `brandGreen`), `#34C759` = `GanchoTokens.Palette.brandGreen` (light), `#0B2A14` = ink on green fills, `#7A4B00` = dark warning ink (no token exists today; `Palette.warning` is `#FF9F0A`).

---

## 0. Board header (context only)

Left to right, flex row, gap 12:
- ID chips `GC-35` (green chip: `#34C759` / `#0B2A14`) and `GC-36` (dark chip: `#1D1D1F` / `#FFFFFF`). Chips are 22 tall, radius 7, 11 pt / 800, monospaced.
- Title `Onboarding · promise, permission, shortcut, first paste` (22 pt / 800, tracking −0.02 em).
- Subtitle `Mac: four short steps that end inside the real panel. iPhone: the current welcome kept as screen 1, plus a screen that explains “Sensed, not read” before the user meets it.` (13 pt, `#5B5B61`, max width 860).
- Right side: `Gancho · v4`.

### Implementation notes (not UI)
The whole header is board chrome.

---

## 1. GC-35 · Mac first run (four window frames, 2 × 2 grid)

Group label: chip `GC-35` + `Mac first run · 4 steps, 520 × 420, skippable at every step` (13 pt / 800).

Grid: two columns of 520, column gap 28, row gap 16. Order: step 1 top-left, step 2 top-right, step 3 bottom-left, step 4 bottom-right.

### Shared window chrome (all four steps)
- Window **520 × 420**, radius 12, background `#F5F5F7`, border 1 px `rgba(0,0,0,.10)`, shadow `0 14 36 rgba(0,0,0,.16)`.
- Padding **22 top / 26 sides / 20 bottom**. Column gap 10.
- Traffic lights at left 12, top 10: three 11 × 11 circles, gap 6, `#FF5F57` `#FEBC2E` `#28C840`. **No window title text is drawn** (the current window shows `Welcome to Gancho` in its title bar).
- **Page indicator (new):** top-right (right 16, top 14), four dots 6 × 6, gap 4. Current step `#1D1D1F`, others `rgba(0,0,0,.18)`. No accessibility label is drawn.
- Content block: margin-top 14, vertical stack, gap 8, **leading-aligned** (today's steps are centred).
- Step title: **19 pt / 800**, tracking −0.01 em, `#1D1D1F`.
- Step body: **12.5 pt**, `#5B5B61`, line-height 1.45.
- Footer button row pinned to the bottom (`margin-top: auto`), gap 8: `Skip` (or `Skip for now`) on the left, a flexible spacer, then `Back` (from step 2) and the primary button.
- Buttons ("glass"): height 28, horizontal padding 10, radius 10, background `#FFFFFF`, border 1 px `rgba(0,0,0,.08)`, 12 pt / 600, `#1D1D1F`. **Primary:** background `#34C759`, text `#0B2A14`, 700, no border.
- Text links (`Open Privacy Center`, `Change…`, `Import from Maccy or CSV…`): no background, `#1F7A3A`, 700, 12 or 11.5 pt as listed.

### 1.1 Step 1 — `Your clipboard, private by design` (GC-35, GC-V7-1)
Dots: 1st active.

Top to bottom:
1. Row (gap 10): **brand mark tile 44 × 44** (viewBox 96, tile 80/96 at rx 20, gradient `#43D267` → `#2BB14E`, white hook; the `data-gancho-mark="tile"` asset from V4_Gancho_Brand), then an annotation (see notes).
2. Title `Your clipboard, private by design`.
3. Body `Gancho keeps everything you copy — text, links, code, colours, images — so you can find it and paste it again.`
4. Promise list, margin-top 4, gap 6. Each row: 12 × 12 icon in `#1F7A3A` (stroke 2.4, margin-top 2), gap 8, 12 pt text at line-height 1.35, with a bold lead:
   - laptop icon: **`Stays on this Mac.`** ` Encrypted on disk. Nothing leaves unless you turn on iCloud sync.`
   - padlock icon: **`Secrets are masked and expire.`** ` Keys, cards and passwords self-destruct after 10 minutes.` ("10 minutes" is the default value; see feasibility.)
   - shield icon: **`Password managers are never read.`** ` Copies they mark as concealed are sensed, not stored.`
5. Link `Open Privacy Center` (12 pt / 700, `#1F7A3A`, leading).
6. Footer: `Skip` · spacer · primary `Continue`. There is no Back button on step 1.

#### Implementation notes (not UI)
- Annotation next to the tile: `Brand mark: see V4_Gancho_Brand (source of truth)` (10.5 pt, `#5B5B61`, 2 px `#34C759` left rule, padding-left 7). This is board text, not UI.

### 1.2 Step 2 — `One permission for instant pasting` (GC-35)
Dots: 2nd active.

1. Hand icon, 34 × 34, stroke 2, `#7A4B00` (the not-granted state).
2. Title `One permission for instant pasting`.
3. Body `Gancho presses ⌘V for you in the app you came from. That needs Accessibility — the only permission it asks for, and never used to read your screen.`
4. Comparison grid: 2 equal columns, gap 8, margin-top 2. Each card has padding 10, radius 10, background `#FFFFFF`, border 1 px `rgba(0,0,0,.08)`, 11.5 pt, line-height 1.4. A bold first line, then a line break:
   - **`With it`** / `Pick a clip, press ⏎, it lands where your cursor was. Paste stack and snippets work in one key.`
   - **`Without it`** / `Gancho copies the clip and you press ⌘V yourself. Everything else works the same.`
5. Status line (gap 8, 12 pt, `#7A4B00`): warning-triangle icon 13 × 13 + `Not granted yet · turns green when you come back`.
6. Footer: `Skip for now` · spacer · `Back` · primary `Open System Settings`.

States: only the **not granted** state is drawn. The text says the line "turns green" once permission is granted, but the granted layout (icon, line copy, primary button) is not drawn.

### 1.3 Step 3 — `Your clipboard, one shortcut away` (GC-35)
Dots: 3rd active.

1. Keyboard icon, 34 × 34, `#1F7A3A`.
2. Title `Your clipboard, one shortcut away`.
3. Body `Press the shortcut, pick a clip with ↑↓, hit Enter — it pastes right where you were typing. That’s the whole loop.` (curly apostrophe in "That’s"; today's string uses a straight `'`).
4. Shortcut list, gap 6, margin-top 2. Each row has padding 8 × 10, radius 10, background `#FFFFFF`, border 1 px `rgba(0,0,0,.08)`, 12 pt, gap 10. Layout: label (flex) · key caps · `Change…` link (11.5 pt / 700, `#1F7A3A`).
   - `Open Gancho panel` · `⇧` `⌘` `V` · `Change…`
   - `Paste from stack` · `⌥` `⌘` `V` · `Change…`
   - `Private mode` · `⌥` `⌘` `P` · `Change…`
   - Key caps: height 18, min-width 18, padding 0 5, radius 5, background `rgba(29,29,31,.08)`, 10.5 pt / 700, `#3A3A3F`, gap 3.
5. Fallback line (11.5 pt, `#5B5B61`): `Forgot it? Gancho also lives in your menu bar — click the hook anytime.`
6. Footer: `Skip` · spacer · `Back` · primary `Continue`.

The board does not draw what `Change…` does: an inline recorder, a popover, or opening Settings.

### 1.4 Step 4 — `Try it now` (GC-35)
Dots: 4th active.

1. Clipboard icon, 34 × 34, `#1F7A3A`.
2. Title `Try it now`.
3. Body `Copy any text in any app — it appears below instantly. Then press ⇧⌘V to open the real panel and paste it back.`
4. Live list box: radius 12, background `#FFFFFF`, border 1 px `rgba(0,0,0,.08)`, padding 4, gap 2.
   - One clip row (the panel `.row`, unselected): height 50, padding 0 8, radius 10, gap 10.
     - Tile 36 × 36, radius 8, background `#5856D6` at 16 %, code-brackets glyph 15 pt in `#5856D6`.
     - Title `Example · Swift` (sample), 13 pt / 600.
     - Preview `let greeting = "Hello"` (sample), 12 pt, monospaced, `#5B5B61`.
     - Trailing source `Xcode · just now` (sample), 10.5 pt, `#6E6E73`.
   - Placeholder under the row: `Your next copy lands here` (12 pt, `#6E6E73`, centred, padding 12).
5. Status line (gap 6, 11.5 pt, `#1F7A3A`): check icon 12 × 12 (stroke 2.6) + `Capturing · the title “Example · Swift” was written on-device`. The quoted title is the sample clip's title.
6. Link `Import from Maccy or CSV…` (11.5 pt / 700, `#1F7A3A`).
7. Footer: `Skip` · spacer · `Back` · primary `Open Gancho panel ⇧⌘V`.

Strings dropped compared with today: `Everything you copy, safe and searchable`, `Try it now: copy any text — it appears below instantly.`, `Copy something — it will appear here.`, `Your clips never leave this Mac unless YOU turn on iCloud sync.`, `Your first clips get smart AI titles, free and on-device.`, `Import clipboard history…`, `To paste a clip directly…ONLY to send the paste keystroke — never to read your screen.`, `Permission granted`, `Without it, Gancho still works: clips are copied and you paste with ⌘V.`, `Panel shortcut:`, `The real panel opens next so you can search and reuse a clip now.`, `If direct paste is unavailable, Gancho copies the clip so you can press ⌘V.`

---

## 2. iPhone · current welcome (`NOW`, context, kept as screen 1)

Label: chip `NOW` + `iPhone · current welcome (from code)`, with the small note `kept as screen 1`.

Phone frame: 390 × 844, radius 44, background `#F2F2F7`, status bar 54 (`9:41`, sample).
- Nav bar (padding 8 × 16, 17 pt / 700, hairline below): leading spacer (60 wide) · centred `Welcome to Gancho` · trailing `Get started` (17 pt / 600, `#1F7A3A`).
- Content: padding 16, gap 22.
  - Header (gap 8): clipboard icon 44 in `#1F7A3A`, then `Everything you copy, saved and searchable` (22 / 800, line-height 1.15), then `Gancho keeps a private history of what you copy — all on this device.` (16, `#5B5B61`, line-height 1.35).
  - `Three ways to save` (17 / 700). Rows have gap 14, a 22 pt icon in a 28-wide column (`#1F7A3A`), a 15 / 600 title and a 13 pt `#5B5B61` detail:
    - hand-tap icon · `Tap to save` · `iOS can't watch the clipboard in the background — no app can. Use the Paste button to save what you copied.`
    - share icon · `Share from any app` · `Send text, a link, or an image to Gancho from the share sheet.`
    - bolt icon · `Shortcuts & Action Button` · `Save your clipboard with a Shortcut — even from the Action Button.`
  - Footer (13 pt, `#5B5B61`, shield icon 14): `Nothing leaves this device unless you turn on iCloud sync.`

This frame mirrors `IOSOnboardingView.swift` exactly (same strings and symbols). The board specifies no change to it, but see GC-36 Q1 on how the user reaches screen 2.

---

## 3. GC-36 · iPhone v4 screen 2

Label: chip `GC-36` + `iPhone · v4 screen 2`, with the small note `the row before you meet it`.

Phone frame as above (390 × 844, `#F2F2F7`, status bar `9:41` sample, home indicator 134 × 5).

1. **Nav bar** (padding 8 × 16, hairline below): `Back` (17 pt, regular, `#1F7A3A`) · centred `2 of 2` (17 / 700) · `Get started` (17 / 600, `#1F7A3A`).
2. **Content** (padding 16, gap 18):
   - Header (gap 8): half-filled shield icon 44 in `#1F7A3A`; title `Sensed, not read` (22 / 800, line-height 1.15); body (15 pt, `#5B5B61`, line-height 1.4) `This is the row you will see at the top of your history. Gancho only sees the ` **`type`** ` of what is on the clipboard — never the content — until you tap Paste.`
   - **Example sensed row:** padding 10 × 12, radius 14, background `rgba(52,199,89,.12)`, border 1 px `rgba(52,199,89,.25)`, gap 12.
     - Tile 36 × 36, radius 8, background `#32ADE6` at 16 %, link glyph 15 in `#32ADE6`.
     - Text column (gap 3): `Link on your clipboard` (15 / 600, sample sensed type), then a 10 pt half-shield icon + `Sensed, not read` (12 pt, `#5B5B61`).
     - Trailing down-arrow 18 in `#1F7A3A`, pointing at the Paste button below.
   - Explainer (13 pt, `#5B5B61`, line-height 1.4): `iOS shows no “pasted from” banner because the Paste button is the system’s own control: your tap is the permission.`
   - Section (gap 8): heading `Optional, set up later in Settings` (15 / 700). Option rows have padding 10 × 12, radius 12, background `#FFFFFF`, gap 12, a 22 pt icon in a 28 column (`#1F7A3A`), a 15 / 600 title, a 12 pt `#5B5B61` subtitle, and a trailing capsule button (height 30, radius 999, white, 1 px `rgba(0,0,0,.08)` border, 12 pt / 600):
     - keyboard icon · `Gancho keyboard` · `Insert any clip while typing` · `How`
     - 2 × 2 grid icon · `Home Screen widget` · `Recent clips + Save` · `How`
     - share icon · `Share sheet` · `Already on — send anything to Gancho` · `On`
3. **Bottom bar** (absolute, padding 10 16 40, fades from `rgba(242,242,247,0)` to `rgba(242,242,247,.92)` at 36 %): a full-width paste button, height 48, capsule, `#34C759` with `#0B2A14` text, 16 pt / 600, clipboard icon 16, gap 7: `Try Paste now`.

The board does not draw what `How` opens, whether `On` is tappable, what happens after a successful paste, or a dark appearance.

---

## 4. Numbered notes (pins)

Each note uses a 20 × 20 dark circle numeral, 12 pt text, and a two-column grid.

1. `Mac (GC-35): today's three steps (value with live clips → Accessibility → shortcut) become four: the privacy promise first and concrete (where, how long, what is never read), the permission as a with/without comparison with the live status the code already polls (AXIsProcessTrusted every second), the three global shortcuts with the menu-bar fallback, and the live first copy as the last step — the current step 1, moved to the end so the window ends inside the real panel. Skip / Back / Continue and the importer stay.`
2. `iPhone (GC-36): the current single welcome screen stays as screen 1 (its three ways to save are kept verbatim); screen 2 shows the exact “Sensed, not read” row the user will meet, explains why there is no banner, and offers keyboard, widget and share sheet with their path in Settings. “Try Paste now” uses the same UIPasteControl.`

### Implementation notes (not UI)
Both notes are annotations, not UI. Their verbatim text is quoted above.

---

## Coverage

| Board element | Covered by |
|---|---|
| Board header (chips, title, subtitle, `Gancho · v4`) | context only |
| GC-35 group label | context only |
| Mac step 1 · privacy promise + brand tile | GC-35, GC-V7-1 (owner decision 2) |
| Brand-mark annotation beside the tile | context only (points to V4_Gancho_Brand) |
| Mac step 2 · permission with/without + live status | GC-35 (green ink and warning ink depend on GC-V5-2) |
| Mac step 3 · three shortcuts + menu-bar fallback | GC-35 (B-GC-01 lesson: show the configured shortcut) |
| Mac step 4 · live first copy + importer + open panel | GC-35 |
| Page dots (all Mac steps) | GC-35 |
| iPhone `NOW` frame (current welcome) | kept, no change: today's `IOSOnboardingView` becomes screen 1 |
| iPhone v4 screen 2 · Sensed, not read | GC-36 |
| Pin 1 | GC-35 (annotation) |
| Pin 2 | GC-36 (annotation) |

---

## Feasibility

### GC-35 — Mac first run in four steps (UI + small feature)

**What changes**
- `OnboardingView` goes from 3 to 4 steps:
  - `privacyStep` (new)
  - `permissionStep` (rewritten)
  - `shortcutStep` (rewritten to three rows)
  - `firstCopyStep` (today's `valueStep`, moved last and trimmed to 1 row + placeholder)
- Layout changes from centred to leading. A page indicator is added. Typography and paddings follow §1.
- The primary button label depends on the step: `Continue` / `Open System Settings` / `Continue` / `Open Gancho panel ⇧⌘V`. Step 2's left button reads `Skip for now`.
- Brand tile replaces `Image(systemName: "paperclip")`.

**Code files (verified)**
- `Apps/GanchoMac/OnboardingView.swift`:
  - :13 `@State step`; :22–26 step switch; :28–45 footer (`step < 2` hard-codes 3 steps at :36–37).
  - :48 `.frame(width: 520, height: 420)`.
  - :56–95 `valueStep`; :58 `paperclip`; :67 `recentItems.prefix(3)`; :88–91 importer button `onboarding-open-migration-importer`.
  - :99–137 `permissionStep` (`AXIsProcessTrusted` 1 s timer :17–18, :134–136; deep link :123–127, id `open-accessibility-settings`).
  - :140–166 `shortcutStep` (`ShortcutRecorder("Panel shortcut:", name: .togglePanel)` :147).
  - :168–170 `finish`; :175–196 `WelcomeWindowController` (title `Welcome to Gancho` :183, `styleMask [.titled, .closable]` :184).
- `Apps/GanchoMac/GlobalShortcuts.swift:10–17`:
  - `togglePanel` initial ⇧⌘V.
  - `togglePrivateMode` and `pasteFromStack` have **no initial shortcut**.
- `Apps/GanchoMac/ShortcutRecorder.swift` (inline `KeyboardShortcuts.RecorderCocoa`). Existing recorders: `GeneralSettingsTab.swift:26` (panel, with `ShortcutConflicts` warning), `:60` (paste from stack), `PrivacySettingsTab.swift:16` (private mode).
- Privacy Center: `model.privacyCenterWindow.show(model:)` (`AppModel.swift:135`, `GanchoMenuBarCommandResponder.swift:29–30`).
- Secret lifetime: `RetentionPolicy.sensitiveLifetime` default 600 s (`Packages/GanchoKit/Sources/GanchoKit/RetentionPolicy.swift:41`). Users can change it in `RetentionSettingsTab.swift:32`.
- Concealed copies are counted as skipped captures, not stored (`ClipboardCore/SensitivePasteboardTypes.swift`, `PrivateActivityReceipt.skippedCaptures`).
- Disk encryption is always on via SQLCipher (`StoreBootstrap.swift`; if opening the store fails, the fallback is in memory, never plaintext on disk).
- Brand asset: `Resources/Brand/gancho-mark.svg`. `Apps/GanchoMac/Assets.xcassets` has only `AppIcon` today. V4_Gancho_Brand says to add a `GanchoMark.imageset` (44–56 pt).
- Strings: `Apps/GanchoMac/Localizable.xcstrings` (EN + ES).
- Tests: `Tests/GanchoUITests/ActivationFunnelUITests.swift`, `Tests/GanchoUITests/MigrationImportUITests.swift:9–33`.

**What step 4 adds compared with today**
- Today the live copy is step 1. It shows up to **3** `ClipCard`s inside a 140-high surface, plus the iCloud line, the AI-titles promo and `Import clipboard history…`.
- v4 moves it **last** and shows **one** panel-style row plus the placeholder `Your next copy lands here`.
- A new live status line, `Capturing · the title “…” was written on-device`, replaces the static AI-titles promo.
- The importer label is renamed to `Import from Maccy or CSV…`. The importer itself exists and supports only Maccy and CSV (`ClipMigrationCoordinator.swift:14–15`).
- The primary button carries the shortcut, `Open Gancho panel ⇧⌘V`, and still calls `finish(completed: true, openPanel: true)`.
- Today's step-3 lines (`The real panel opens next…`, `If direct paste is unavailable…`) are removed. Their meaning moves into the step-2 `Without it` card.

**Exists vs new**
- Exists:
  - window, size, Skip/Back/Continue, live AX polling, deep link, live `recentItems`, importer sheet, panel hand-off
  - `finishOnboarding` (`AppModel.swift:1039–1044`), Privacy Center window, shortcut recorders
- New:
  - privacy step
  - with/without cards
  - page dots
  - three-row shortcut list with key caps + `Change…`
  - step-4 status line
  - leading layout and type scale
  - GanchoMark imageset in the Mac target
  - accent-ink and warning-ink colours (GC-V5-2)
  - about 20 EN + ES strings
- The status line needs to know the clip title came from auto-titling. `ClipItem.title` (`ClipItem.swift:17`) records no provenance. For the first clip, a non-empty title before the user edits it means it was auto-titled. Without that, the line can only say `Capturing`.

**Persisted flag / migration**
- The Mac flag is `UserDefaults` bool `has-seen-welcome`: read at `AppModel.swift:689` (into `LaunchPresentation.decide`, `GanchoAppCore/LaunchPresentation.swift:41`), written at `AppModel.swift:1040` on **any** finish (Skip or complete).
- It has no version, so users who already finished or skipped the 3-step flow **will not see** the 4-step flow automatically. No migration is needed for correctness: no schema or stored step index exists.
- They can still open it from the menu-bar command `Welcome to Gancho` (`GanchoMenuBarCommand.swift:19, 78`, responder :27–28).
- The `onboardingCompleted` activation milestone is first-write-wins (`ActivationTracker.swift:106–114`), so re-running onboarding never double-counts.
- Re-showing v4 to returning users would need a new key (for example `welcome-version`). That is not drawn; see Q4.
- Today's behaviour: `WelcomeWindowController` keeps its window (`isReleasedWhenClosed = false`, `close()` only calls `orderOut`). The `@State step` therefore survives, and reopening from the menu lands on the last step seen. With 4 steps, that is step 4.

**Dependencies**
- GC-V7-1 (brand tile asset)
- GC-V5-2 (accent ink `#1F7A3A`; a warning ink `#7A4B00` is also needed, which GC-V5-2 does not list)
- GC-V5-1 / B-GC-01 (render the *configured* panel shortcut; never hard-code ⇧⌘V)

**Verify**
- Update `ActivationFunnelUITests`. It walks 3 steps today, asserts `Open Gancho panel` as the final label at :48, and asserts the removed fallback text at :42–47.
- Update `MigrationImportUITests.testOnboardingOffersGuidedMigration`. It expects the importer on the first step; the importer moves to step 4.
- New UI test: 4 dots, Back hidden on step 1, `Open Privacy Center` opens the Privacy Center window.
- Snapshot each step at 520 × 420 against the board.
- `LocalizationTests` for the new strings.
- A unit test that the "10 minutes" text follows `retentionPolicy.sensitiveLifetime`.

**BLOCKED / questions**
- Q1: Step 3 draws `Paste from stack ⌥⌘V` and `Private mode ⌥⌘P`, but neither has a default in code.
  - Should they get new `initial:` shortcuts? `KeyboardShortcuts` applies an initial value to every user who never set one, so an update would silently register global hotkeys.
  - ⌥⌘V also collides with users who moved the panel to ⌥⌘V (the owner's own Current board shows panel = ⌥⌘V).
  - The alternative is to show "not set" with a recorder, which is not drawn.
- Q2: Step 2 states that are not drawn:
  - Does `Skip for now` advance to step 3, or close onboarding like `Skip`?
  - When permission is granted, what are the icon, status copy, and primary button (presumably `Continue`)?
- Q3: What does `Change…` do: swap the key caps for the inline recorder, or open Settings › General / Privacy? Not drawn.
- Q4: Should users who already finished the 3-step flow ever see the 4-step one, through a versioned flag? The board is silent.
- Q5: The board draws no window title (today: `Welcome to Gancho`). Is a hidden or transparent title bar intended, or is this just board simplification?
- Copy rules, not blockers:
  - `⇧⌘V` in the step-4 body and button must come from the configured shortcut.
  - "10 minutes" must come from the configured lifetime.
  - `colours` is British; existing catalog strings use `colors`. Pick one spelling.

### GC-36 — iPhone first run explains "Sensed, not read" (UI)

**What changes**
- `IOSOnboardingView` becomes a two-page flow. Page 1 is today's content, unchanged. Page 2 is new and has:
  - a nav bar with `Back` / `2 of 2` / `Get started`
  - the explainer header
  - the example sensed row and the no-banner explainer
  - three optional set-up rows
  - a bottom paste button

**Code files (verified)**
- `Apps/GanchoiOS/IOSOnboardingView.swift`: single `NavigationStack` + `ScrollView`; `Get started` toolbar button `onboarding-done` at :62–72.
- `Apps/GanchoiOS/GanchoiOSApp.swift`:
  - :35 `@AppStorage("ios-has-seen-welcome")`
  - :115–124 sheet presentation; `onDone` → `model.completeOnboarding()` (`IOSAppModel+AppActions.swift:11–13`)
  - :46 `-skip-welcome-on-launch`
- Real sensed row: `Apps/GanchoiOS/PasteboardStatusRow.swift`:
  - chip `Sensed, not read` + `shield.lefthalf.filled` at :60–62; titles at :140–146 (`Link on your clipboard` …)
  - info popover with today's explanation at :85–99
  - It has **no tile**: the layout is chip + title + info button.
- Paste control: `PasteControlView` (`CaptureView.swift:447–477`), used at `CaptureShell.swift:180` with `model.ingest(providers:)` (`IOSAppModel.swift:1142–1145`).
- Extensions: keyboard `Apps/GanchoKeyboard` (`RequestsOpenAccess = true`); widget `RecentClipsWidget.swift:14–16` (`Recent Clips`, small/medium); share `Apps/GanchoShare` (text, URL, 1 image).
- In-app Settings (`IOSSettingsView.swift`) has **no** keyboard, widget or share section.
- Strings: `Apps/GanchoiOS/Localizable.xcstrings`.

**Exists vs new**
- Exists: page 1, the sensed copy, the paste control and ingest path, all three extensions.
- New:
  - the paging inside the sheet
  - page 2 layout
  - a static example row (tile variant)
  - `How` content
  - about 12 EN + ES strings
- The board's row is not pixel-identical to `PasteboardStatusRow` even though the note says "the exact row". Either reuse the real view with a fixed demo hint, or build the drawn variant.

**Persisted flag / migration**
- The iOS flag is `ios-has-seen-welcome` (bool, no version). It is set by `Get started` or by dismissing the sheet with a swipe (the binding setter at :118).
- Existing users will never see page 2. They already have the info popover on the real row.
- Showing page 2 to returning users would need a new key; not drawn (Q4).
- The sheet also appears on iPad, because the `Group` wraps `IPadSplitView`. GC-36 is labelled iPhone only.

**Dependencies**
- GC-V5-2 (green ink on light)
- iPhoneSurfaces board for widget and share copy consistency

**Verify**
- iOS UI test: launch without `-skip-welcome-on-launch` → page 1 → page 2 → `Back` → page 1 → `Get started` sets the flag.
- `paste-control` exists on page 2.
- Snapshot at 390 × 844.
- `LocalizationTests`.

**BLOCKED / questions**
- Q1: Page 1 is drawn "kept verbatim" with `Get started` as its only action. How does the user reach page 2? Either a new `Next`/`Continue` on page 1, or `Get started` moves to page 2 only. Not drawn.
- Q2: `UIPasteControl` draws its own system label ("Paste"); it cannot show `Try Paste now`. Should the label sit outside the control, or should the copy change?
- Q3: After a successful paste on page 2, does the sheet dismiss and land on the saved row, or stay open? Not drawn.
- Q4: What do `How` (keyboard, widget) show: an in-app sheet with steps, or a link out? The keyboard needs Full Access. Is `On` a status label (non-interactive)? Board note 2 says "with their path in Settings", but no path text is drawn.
- Q5: Should iPad get the same page 2?

### GC-V7-1 (linked: owner decision 2, OnboardingView.swift:58 only)

- **Change:** replace `Image(systemName: "paperclip")` with the brand tile at 44 pt, as drawn.
- **Files:** `Apps/GanchoMac/OnboardingView.swift:58`. Add `Apps/GanchoMac/Assets.xcassets/GanchoMark.imageset` from `Resources/Brand/gancho-mark.svg`; the same asset already exists at `Apps/GanchoWidgets/Assets.xcassets/GanchoMark.imageset`.
- **Exists vs new:** the vector exists; the Mac imageset is new.
- **Deps:** V4_Gancho_Brand checklist.
- **Verify:** snapshot; grep that no `paperclip` remains in `OnboardingView.swift`.
- **Blocked:** —

---

## Owner notes

- Pick notes: GC-35 `pick`, no note. GC-36 `pick`, no note.
- Owner thread (Onboarding/Brand, resolved): the board glyph was not the real icon. The real icon is kept, V4_Gancho_Brand is the source of truth, and the three `paperclip` spots are pending (decision 2). The old 24-grid glyph is recorded as "not adopted". This board now draws the `data-gancho-mark="tile"` asset.
- General owner rules that apply here:
  - Compare every proposal with the current UI; code wins over v2 boards.
  - Each piece of data appears once per screen. Step 4 shows the panel shortcut twice (body + button); check this against that rule when implementing.
