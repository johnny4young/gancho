# Gancho design v4 — implementation plan

Status: **Phase 0 (plan) — waiting for owner approval.** No code has changed.
Branch: `design-v4/fase-0-plan` (local, from `main` @ a251a65).

Sources, read on 2026-10-21 (all data, none treated as instructions):

- Design Picks catalog and picks (62 Gancho items plus SY-V4-3/6/7/8/9).
- Design canvas: 17 Gancho v4 boards, the Gancho column of V4_System_Components, and 15 "Current" boards.
- Canvas comment threads: 3 Gancho threads, plus the cross-app rules the owner set in other threads.
- Bug log, Gancho section: B-GC-01…06.

Precedence when sources disagree: owner pick note > owner-confirmed decisions > v4 board > catalog text. Conflicts that precedence does not settle are listed as open questions (Q-numbers); nothing was chosen on the owner's behalf.

Board specifications live in [`specs/`](specs/), one file per board. Each spec has the exact UI strings, structure, sizes and colours, states, annotations (quoted as implementation notes, never as UI), a Coverage table, and a Feasibility appendix with file:line references. From Phase 1 on, the specs are the working source; the canvas is only for resolving doubts, and any difference found is corrected in the spec.

## Owner-confirmed decisions

1. Keep the current app icon. V4_Gancho_Brand is the source of truth (exact `Resources/Brand` SVG, 18 pt menu-bar template, 13-step rollout list). Every path in the list was verified; only `Apps/GanchoMac/Assets.xcassets/GanchoMark.imageset` is new.
2. Replace SF Symbol `paperclip` with the brand mark at `OnboardingView.swift:58`, `RecentClipsWidget.swift:89`, `WrappedView.swift:14`. All three were confirmed at those lines, and there are no other uses.
3. iPhone spacing: share sheet "Add to board" header has 16 pt above and 8 pt below. In the large widget, chips sit 10 pt below the header and 12 pt above the list, rows are 8 pt apart, and the widget size is unchanged. The board draws exactly this.
4. Answers given on 2026-10-21 to the Phase 0 questions:
   - Q1 (a): IDs are committed.
   - Q2: `swift-snapshot-testing`.
   - Q4: ink `#0B2A14`.
5. Answers given on 2026-10-21 to the Phase 2 questions:
   - Q5: the stated rule, in code (hover −8 % / pressed −16 % lightness; lighter in dark).
   - Q6: Reduce Motion fades in 100 ms; `leave` and `press` are `GanchoMotion` tokens.
   - Q7 + Q8: keep the green active chip with dark ink, and the wash + 3 pt bar with no row lift.
   - Q9 (default): keep "Search your clipboard"; destructive buttons never show a key.
   - Q35 + Q42: dark ink on the Privacy hero; hex dark surfaces only in the opaque branch (glass stays when translucent).
6. Answers given on 2026-10-22 to the Phase 3 questions (all the recommended option):
   - Q19: the sync chip shows upload state ("Synced" / "Waiting to sync", hidden with sync off); the "title written on-device" caption is dropped; expiry becomes an amber chip in the header.
   - Q21: the scope chip shows the board's total.
   - Q10: image size is stored at capture (v27, lazy backfill, not synced); masked images stay masked; untitled rows read "Image · W × H · FORMAT", titled rows "FORMAT · W × H" under the title (default).
   - Q22: the hero takes a "decoded" chip only when it differs from the URL (its 4 pt kind stripe was removed on 2026-10-23: no left accent bars).
   - Q23 (default): the pins win; the "By meaning" row goes with GC-V4-1.
   - Q35: 7 % / 10 % is the wash's visible peak; the test is inverted.
   - Q26: "Shown once…" is an annotation and is not shipped.
7. Answers given on 2026-10-23 to the Phase 4 questions (all the recommended option):
   - Q20: the dock reads "Paste into <App>" with a target, "Paste" with none, "Copy" without Accessibility; the footer names the app only when there is one.
   - Q18 (Private Mode only): no default ⌥⌘P; the button and footer show the recorded shortcut, or "Turn off" with no hint.
   - Q25: auto-off after 15 min, 30 min, 1 h (default) or 2 h, or until turned off; "none read" is a fixed promise a test enforces.
   - Q24: "Older than 30 days" is dropped; the most results wins, ties Fuzzy > Meaning > All boards > Regex (Exact after Fuzzy); all zero highlights nothing.
   - Q63: ⌘S stays Save as snippet and ⇧⌘S saves the filter; #tag is dropped; Meaning is a fourth, exclusive mode.
   - Review round, same day: filter keys are offered from the second letter, and a new auto-off choice applies to the Private Mode already on (its deadline moves to start + the new duration).
8. Answers given on 2026-10-23 to the Phase 5 questions (all the recommended option):
   - Q28: the eyedropper samples the exact pixel of the original image, not the screen, and saves it as a colour clip; a dominant swatch click does the same; 1–3 swatches; Regions / Image only is a segmented control that defaults to Regions.
   - Q29: the dock is Paste into <App> · Plain · Convert ⇧⏎ · Pin · Board (GC-V4-2 wins over "Paste #008080"); contrast uses the real ratios, truncated to one decimal, graded AA / AA Large / below AA, with "Aa" in the colour on white and on #1C1C1E.
   - US spelling "color" in UI copy; the Swift format uses three decimals with trailing zeros dropped, and `opacity:` only when the colour has alpha.
9. Owner rule, 2026-10-23: no left accent bars anywhere (apps, website, mockups). The selected row is the accent wash inside a full 1 pt accent outline; the peek hero drops its 4 pt kind stripe and keeps the tinted wash; `DesignTokenGuardTests.noLeadingAccentBars` guards Swift and the site. This overrides the boards' leading bars and Q22's stripe.
10. Answers given on 2026-10-24 to the Phase 6 questions (all the recommended option):
   - Q33: the helper forwards a click and the main app opens its own menu under the icon (real tiles, ⌘1–5, ⌥ plain, stack row); the last-copied preview leaves the bridge, which is a plain plist outside the encrypted store; if the app doesn't answer in 0.5 s the helper opens its own command menu.
   - Q34: badges by precedence denied > paused (manual, share, lock) > private > ignore-next > stack; paused amber like the footer chip, private indigo, denied red, ignore-next grey with "−", stack count in ink; no syncing badge; dark glyph on amber and grey, white on the rest; the hook stays a template image with the badge on a layer above it.
   - The stack badge shows the count; "3/5" comes with the GC-10 cursor (Phase 15).
11. Answers given on 2026-10-24 to the Phase 7 questions (all the recommended option):
   - Q36 / Q-23a, b: in-app drags only (panel rows and Library cards); no refusal shake, since a protected clip can't be dragged and board membership has no Free cap; a clip already on the board says "Already in <board>" and writes nothing.
   - Q-23c: the row or chip pulses and the Library count ticks; the system drag image is not animated into the row.
   - Q-23d: rail chips keep no counts; the toast and the chip pulse confirm.
   - Q-23e: every assign toast names the board ("Added to <board>") with Undo; ⌘Z in the panel and the Library runs a visible toast's Undo (delete included), and the toast shows "Undo ⌘Z".
   - Found while building it, owner-approved: the panel no longer moves from any background; it moves from its top strip (search bar and toolbar background, title bar), so a row drag carries the clip.
12. Answers given on 2026-10-24 to the Phase 8 questions (all the recommended option):
   - Q13 (Library): a protected card shows the stored mask (`●●●● 4Q2v`) under the kind's name ("Secret") with its countdown; no stored prefix. Q12 for the Library: the card drops the "never synced" claim; whether sync skips sensitive clips stays with Phase 14.
   - Order: by copy date, a Pinned group first, then Today, Yesterday, … with counts; Oldest reverses both.
   - Cards carry board chips (one membership read per page), no per-card sync chip (the header keeps the sync state), a link as host + path, an image's format and size (stored since GC-V5-3), and no "⌘C copies" keycap.
   - Q37: the panel's kind set (All, Links, Code, Colors, Images, Secrets); search matches clips only (snippets are clips), placeholder "Search clips"; the List layout is the panel's row; the Grid / List choice persists; no Select button; a protected card offers no Copy.
   - Q38: the meter counts three ceilings (boards 3, pins 15, snippets 20), fills to the fullest, and its caption ends "Pro removes every limit", "Almost full" or "Limit reached" with the bar in accent, amber or red.
   - Phase 7 follow-up: with an Undo toast showing, typing that can be undone wins ⌘Z; the toast keeps its button.
13. Answers given on 2026-10-25 to the Phase 9 questions (all the recommended option):
   - Q39: the read-only timeline over the existing pickers ships, plus "Forget recent clips" (5 / 15 / 60 min, the count shown first, undoable); no policy migration and no Novel2 dial. Markers are ordered by lifetime and spaced evenly; a type on Use global folds into "everything else", a Forever global joins "never", and equal lifetimes share a marker.
   - Q41: tile 3 counts protected copies skipped in the last 7 days; the screen-share footnote names what the detector detects ("Zoom, Teams and Screen Sharing are detected.").
   - Q17: no "also concealed" chip; the concealed-types rule is a static card with no switch, and the denylist stays as built.
   - Q40: Verify runs on this Mac (SQLCipher version, a file that is not plaintext SQLite, a keyed read) and shows the result in the row; the sections the board does not draw stay below the drawn ones; Network is a Verify row; the last read shows its time only.
   - The Settings footnotes the board drops (masked secrets, Spotlight removal) stay, shortened; the receipt keeps "Protected copies are included in skipped captures."
14. Answers given on 2026-10-25 to the Phase 10 questions (all the recommended option):
   - Q43 (Mac): "Skip for now" on the Accessibility step moves to the next step; granted shows a check, "Granted · Gancho can paste for you" and Continue. "Change…" swaps the key caps for the inline recorder (with the conflict warning); an unset shortcut shows "Not set" and "Set…" (Q18: no default ⌥⌘V or ⌥⌘P). No versioned flag: returning users reopen it from the menu. Step 4's body says "press your panel shortcut" and only the button shows the recorded shortcut. The window title is hidden, as drawn.
   - Q44 (iPhone): page 1's "Get started" becomes "Next" and "Get started" moves to page 2; "Try Paste now" is a label above the system Paste control; a paste there closes the welcome and opens the saved clip; "How" opens in-app steps and "On" is a status label; iPad gets the same page 2.
15. Answers given on 2026-10-25 to the Phase 11 questions (all the recommended option):
   - Delivery: two PRs. 11a is the iPhone Home (GC-26, GC-V4-8, GC-V4-9, GC-V4-10, GC-V4-11); 11b is the flows (GC-27, GC-28, GC-V4-12, the iPhone half of GC-21).
   - Q45 (GC-26): the card keeps its ⓘ (44 pt). Unsensed kinds get a magnifying glass (search text), # (number) or a grey clipboard (anything else). An empty pasteboard keeps today's one-line row. After the 4 s of Saved · Open the card returns to Saved while the same copy is on the pasteboard. Images are out of scope.
   - Q46 (GC-V4-8): a row from another device shows a generic glyph and the stored device name, truncated, and drops the cloud glyph. Headers show a bare count only when their group is fully loaded (no new query); the active rail chip shows its scope's total.
   - Q47 (GC-V4-10): the chips sit under the rail; their Clear filters clears type and app, not the board; the active chip is dark; the whole chip is the 44 pt target.
   - Q48 (GC-V4-11): Related by meaning runs on its own while semantic search is on, silent when empty or unavailable; clips synced from another device are embedded in the background on device (Pro, as at capture); the answer card keeps tap-to-copy.
   - Q49 (GC-27): a new Markdown link action for links; the board suggestion is a chip with ×; Board and + Add both stay; Snippet is disabled, not hidden, when it doesn't apply and shows as set when the clip already is one. The iPad detail follows.
   - Q50 (GC-28, GC-V4-12): a board's subtitle says Synced or Waiting to sync (On this iPhone on Free); a new Snippets group lists keyword and title and opens the detail. Settings' keyboard and widget rows open the onboarding's How steps, the share sheet reads On, Paste is an info row; the path reads Settings › General › Keyboard › Keyboards; Pro on Pro reads "Pro · every limit removed"; the Spotlight footnote stays.
   - GC-21 (iPhone): the same Verify as the Mac; the group holds Encryption + Verify, iCloud sync (Off · Pro on Free) and Secrets masked now; the undrawn sections stay below; the receipt footnote stays; it is still pushed from Settings; the hero text is dark.
16. Answers given on 2026-10-25 to the Phase 12 questions (all the recommended option):
   - Delivery: two PRs. 12a is the sidebar and the history column (GC-33); 12b is drag-out (GC-34).
   - Q51 (GC-33): an app row shows a letter tile (the initial of its name on a colour its name always picks), never a bundled icon. Types are the Mac's five groups (Links, Code, Colors, Images, Secrets) plus All types, each with its tint and count; no "Text" group. Each section washes its active row in the accent at 16 % with a semibold name (All clips, All types, All apps included); "All apps" stays; no checkmarks. Paste lives in the docked card while the sidebar shows and returns to the history toolbar, with the status row, while it is hidden; never two at once. `Select` (multi-select) is out of scope and recorded as its own item.
   - Without asking (house rules and earlier answers): headers count like the iPhone's (Q46), Pinned stays first, `BoardIdentityMark` stays a circle, the docked card keeps every status state, the keyboard legend and Copy's ⌘⏎ show only with a hardware keyboard attached, and the detail drops its 680 pt cap.
   - Q52 (GC-34): the detail's hero (a link's card, an image) and the history rows both drag, with the Mac's rule (nothing masked lifts). The dashed hint first answered as a dismissible tip was dropped on 2026-10-26 under the owner's "no filler copy" rule: no helper text, the drag is the system's long-press lift.
17. Answers given on 2026-10-30 to the Phase 13 questions (all the recommended option):
   - Delivery: four PRs. 13a share sheet (GC-V4-15), 13b large widget + Live Activity (GC-V4-16, GC-V4-17), 13c text in image on iPhone (GC-V4-18), 13d the keyboard's inserted mark (GC-V4-19).
   - Q53 (GC-V4-15): the editable title is the one the sharing app hands over (a page title), with no model and no network in the extension. The app writes a sealed board snapshot to the App Group whenever boards change; the extension reads it and never opens the store. The sheet shows by default; "Save instantly from the share sheet" in Settings › Capture on iPhone brings back the blind save; Shortcuts and the Action Button stay instant.
   - No filler copy (owner rule, 2026-10-26): the share footer, "written on-device" and the text-in-image footer are dropped.
   - Q54 (GC-V4-16): the large widget's chips are All, Favorites and the user's boards in app order, as many as fit (at most four); a tap scopes the six rows. A masked row reads like the iPhone's (kind name, stored mask, lock, time left). Small and medium only swap the paperclip for the Gancho mark.
   - Q55 (GC-V4-17): "Copy again" is not offered for a sensitive clip; "Open in Gancho" stays. The activity ends when Gancho captures again, or at the next foreground when the pasteboard changed (its change count, never its content), besides the 3-minute dismiss.
   - Q32 + Q56 (GC-V4-18): on iPhone, text in an image is read when the clip opens, on device, and not stored; regions come from a fresh pass even when Pro has the text cached. Nothing is copied without a tap. A line with a secret stays out of "Copy all" until revealed, and Translate is hidden while one is held back.
   - Q57 (GC-V4-19): every row inserted into the current field is marked (tint + pill) until the document changes; images, which go to the pasteboard, are not marked.
18. Answers given on 2026-10-31 to the Phase 14 questions (all the recommended option):
   - Delivery: two PRs. 14a keeps secrets on the device (sync); 14b is the Mac peek for a secret.
   - Q12 (GC-09): sensitive clips never sync. They stop uploading, the ones already in iCloud are deleted there (the local rows stay), and a remote change never adds, edits or deletes a local secret.
   - Q14 (GC-09): the Mac peek reveals a secret with a "Reveal for 10 s" button, which masks it again after 10 s, when the panel closes or when it loses focus. No hold-⌥ (⌥↩ is Plain paste).
   - Q15 (GC-09): no "Keep 10 more min"; a secret's lifetime can still be shortened, never extended. The peek shows the countdown, the lifetime bar and Delete now.
   - Q16 (GC-09): settled by earlier answers. Widgets keep the masked row (Q54), the keyboard keeps excluding secrets, and the mask stays the stored `●●●● 4Q2v` (Q13).
   - Q3 (GC-09): Phase 14 ships without a flag; it extends shipped secret handling. The flag pattern stays for the Novel phases 15–24.
19. Answers given on 2026-10-31 to the Phase 15 questions (all the recommended option):
   - Delivery: two PRs. 15a is the run cursor, Skip / Back / Reset and the queue; 15b is the floating strip.
   - Q61 + Q18 (GC-10): no global ⌘V capture and no default shortcuts. "Paste from stack" stays the user's own; Skip and Back get recorders with no default; the strip has buttons for all of them and Reset.
   - GC-10: the queue fills only by ⌥⌘⏎ or "Add to paste stack"; selecting clips never enqueues them.
   - GC-10: a minimal non-activating strip near the menu bar shows a run while the panel is closed ("3 of 5", the next title, masked for a secret or while sharing, Skip / Back / Reset / close).
   - A run keeps what went in and ends after 2 minutes without a stack action or with a new copy on this Mac; ending drops the pasted entries and keeps the waiting ones.
   - Without asking: the status item keeps its count badge from Phase 6 (now the entries still waiting), and the `next` marker uses the accent, since indigo is Private Mode's.
   - Q3 (GC-10): Phase 15 ships without a flag; it extends the shipped stack.
20. Answers given on 2026-10-31 to the Phase 16 questions (all the recommended option):
   - Delivery: three PRs. 16a is the Transform ⌘T list and the step pipeline (GC-11); 16b is recipe paste, per-recipe shortcuts and ⌃⌘V; 16c is Describe the change with its diff and saved prompts (GC-12).
   - Q30 (GC-11): a row of the ⌘T list opens the pipeline with that step and a live before / after; "+ Step" chains more; nothing is pasted or copied without a key or a click. Recipes may paste through the same revalidated paste-back, and Copy stays; per-recipe shortcuts and ⌃⌘V get recorders with no default.
   - Q31 (GC-12): saved prompts are their own local list that never syncs; recipes stay deterministic.
   - Q27 (GC-12, decided per the board): ⏎ pastes the original and ⇧⏎ the result; esc first closes a result or a pipeline, then hides the panel.
   - Q12 / Q13 (Peek, without asking): the clip's own group comes first; "Format code" and a code "Minify" are not built, since the repo has no offline formatter; "Wrap in markdown fence" waits for 16b with the recipe steps.
   - Q3 (GC-11, GC-12): no flag.
21. Cross-app rules from the owner's threads:
   - Only propose what beats the current UI; code wins over v2 boards and site screenshots.
   - Each piece of data appears once per screen.
   - Canvas annotations are not UI.

## Counts

| Group | Expected (brief, 19 Oct) | Live sources (21 Oct) | Rows in table |
|---|---|---|---|
| Gancho catalog items | 62 (60 pick · 1 maybe · 1 skip) | 62 (60 pick · 1 maybe · 1 skip) | 62 |
| System items | SY-V4-3, 6, 7, 8, 9 | 5 (all pick) | 5 |
| Bugs (bug log, Gancho) | 6 | 6 (2 Alta · 1 Media · 3 Baja) | 6 |
| **Total rows** | 73 | 73 | **73** |

Live sources match the expected numbers exactly. Maybe: GC-V4-22, with owner note "no entiendo la utilidad de esto, pero siento que no es necesario". Skip: GC-V4-20.

By type: UI 29 · bug 6 · feature 31 · system 7.  
By status: blocked 6 · done 64 · in progress 1 · not implemented 1 · pending decision 1.

## Plan table

Type: UI / feature / bug / system. Pick is the Design Picks state. Phase refers to the phase list below. Status values: `pending`, `in progress`, `done`, `blocked: Q…` (owner question), `pending decision`, `not implemented`. Full detail per ID is in the board spec's Feasibility appendix.

| ID | Type | Pick | Owner note | Board(s) | What changes | Code files | Exists vs new | Deps | How verified | Phase | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B-GC-01 | bug | n/a (bug log) | — | MenuBarDark | Open panel menu item shows the recorded panel shortcut (or none); menu rebuilds on change, in helper and fallback | GanchoMenuBarCommand.swift:135,:147; GlobalShortcuts.swift:10-19; StatusItemController.swift:207-227; GanchoMenuBarHelper/main.swift:64-79; GanchoMenuBarBridge.swift | Recorder + setShortcut(for:) exist; bridge key + encoder for the helper are new | GC-V5-1 | Unit: shortcut encoder round-trip; UI: record ⌥⌘V → menu shows ⌥⌘V (-use-in-process-status-item) | 1 | done — a3750fa; MenuBarShortcutUITests + MenuBarKeyEquivalentTests |
| B-GC-02 | bug | n/a (bug log) | — | Settings, Panel | Accent green used as text ink replaced by a derived accent-ink ≥4.5:1 at every call site | GanchoColors.swift:68-79 (:72 system branch, :73 brand); ~20 call sites listed in specs/V4_Gancho_Settings.md | Accent + luminance helper exist; accentInk token + sweep new | GC-V5-2, SY-V4-3 | Unit: contrast ≥4.5 for brand + every system accent, light/dark; grep gate for accent-as-text; snapshots | 2 | done — c5acf25, 85c3dac; ContrastTokenTests (brand + adjusted system accents, light/dark) + DesignTokenGuardTests green-text gate + snapshots |
| B-GC-03 | bug | n/a (bug log) | — | Settings | Privacy Center hero passes AA (dark ink on the gradient) | PrivacyCenterView.swift:374,:382,:386-388 | Hero exists; ink change new | GC-V5-2 | Snapshot light/dark; contrast unit test | 2 | done — c5acf25 (Q42: dark ink on the gradient); ContrastTokenTests + snapshots privacy-center light/dark |
| B-GC-04 | bug | n/a (bug log) | — | Panel | Log entry is a misdiagnosis: the '...' row is a masked sensitive image (seed isSensitive), not an untitled image. Close or reframe under GC-V5-3 | Components.swift:155,:198,:244-245,:386-387; AppModel+UITestSeeds.swift:230-232 | Code works as designed | GC-V5-3 | — | 1 | done — closed as misdiagnosis (Q10 default); masked rows stay masked |
| B-GC-05 | bug | n/a (bug log) | — | Settings | Focus ring only on the keyboard-focused sidebar row; selection is the only fill | SettingsView.swift:121-153 | @FocusState + focusEffectDisabled + custom ring new | GC-V5-4 | UI: AppQualityUITests select Capture → only one row ringed; keyboard focus still visible | 1 | done — a2c887b; AppQualityUITests + snapshot settings-sidebar |
| B-GC-06 | bug | n/a (bug log) | — | Settings | Intelligence pipeline fits 520 pt (or wraps); Smart paste gets an icon | IntelligenceView.swift:89,:132,:172-195 | Small edits | GC-V5-5 | Unit: SF Symbol resolves; UI: IntelligenceCapabilityUITests node 5 hittable; snapshot | 1 | done — 9c2a429; testPipelineFitsInsideTheWindow + snapshot intelligence |
| SY-V4-3 | system | pick | — | System Components (+ all v4 boards) | Dark ink on brand-green fills, green-text token, tint, danger #D70015 light | GanchoColors.swift:21-42; ContrastingForeground.swift:19; PeekActionButton.swift:89; PanelView.swift:937; SettingsView.swift:140; prominent/.defaultAction buttons (8 sites); PrivacyCenterView.swift:382 | Brand/warning same; ink is black today; ink/green-text/tint tokens new; danger differs | GC-V5-2, B-GC-02/03, GC-04 | Unit: ContrastingForegroundTests ≥4.5 per state light/dark; snapshots | 2 | done — cc193f5, c5acf25; ContrastTokenTests (ink on rest/hover/pressed, green text, tint, danger #D70015 / #FF6961) + snapshots |
| SY-V4-6 | system | pick | — | System Components | Shared hover / pressed / disabled / focus rule (focus 2 pt gap + 2 pt ring in control hue) | new ButtonStyles in GanchoDesign; GanchoTokens.swift:27 (Stroke.focus 1.5→2); PeekActionButton.swift:59-120; PanelView.swift:930-954 | Hover washes + 1.5 pt ring exist; pressed, gap ring, derived steps new | SY-V4-3, B-GC-05 | Unit: step function; UI: focus ring visible on Tab; snapshots per state | 2 | done — cc193f5, 4efbece (Q5: −8 % / −16 % lightness in code); ContrastTokenTests stepping + snapshots; windows styled at the root keep the native focus ring |
| SY-V4-7 | system | pick | — | System Components | Elevation scale e0–e3 tokens; 1 px inset highlight in dark; replace ad-hoc shadows | new GanchoTokens.Elevation; PanelView.swift:543; PanelShortcutsOverlay.swift:63; ReuseSuggestionBanner.swift:55; PanelController.swift:405 | Radii/hairline same; shadow tokens new | GC-04 | Snapshots light/dark; source-scan for literal shadows | 2 | done — cc193f5, 4efbece, 85c3dac (Q8: wash + 3 pt bar, no lift); DesignTokenGuardTests shadow gate + snapshots |
| SY-V4-8 | system | pick | — | System Components, PanelStates | One saturated control per surface; secondary = surface + hairline; destructive filled only in confirmations | PanelView.swift:930-939; SettingsView.swift:137-145; PrivacyCenterView.swift:83,:178 | ContrastingForeground exists; secondary/tertiary/destructive styles new | SY-V4-3, SY-V4-6 | Per-surface audit checklist in PR; snapshots | 2 | done — c5acf25 (Q7: green active chip stays); per-surface audit in the PR + snapshots |
| SY-V4-9 | system | pick | — | System Components | Cross-app vocabulary: keycap inside primary button, hit targets 44/30/28/24, one command field, type/radius table incl. 12 pt step | PeekActionButton.swift:72-74; Components.swift:500-561; PanelView.swift:556; GanchoTokens.swift:30-35 | Radii same; FontSize tokens unused; 12 pt, keycap, ⌘F hint new | B-GC-01 | UI: peek-dock keycaps; unit: hit-target sizes; snapshot | 2 | done — 4efbece, 85c3dac, 7718cf5 (Q9: keep placeholder, no key on destructive); dock keys stay under the verbs per the Panel board; HitTargetTests |
| GC-V4-1 | feature | pick | — | Novel2, Panel | Search modes inside the field (Exact/Fuzzy/Regex/Meaning) + filter tokens app: type: board: device: before: #tag with Tab completion; save as filter | PanelSearchModel.swift:41-130; ClipSearch.swift:6; SmartCollections.swift:8; PanelView.swift:556; MeaningSearchControls.swift:9 | Modes, dates, filters exist; parser, device/tag filters new | GC-08, GC-V4-3, GC-V4-10 | Unit: parser + query plan; perf: 100k search budget; UI | 4 | done — b915b49 (Q63: ⌘S stays Save as snippet, ⇧⌘S saves the filter; #tag dropped; Meaning is an exclusive mode; a board token selects the rail, no chip); SearchTokensTests + PanelSearchTokenTests + DeviceAndDateFilterTests + SearchTokensUITests + MeaningSearchUITests + snapshots panel-search-tokens |
| GC-01 | UI | pick | — | Panel | Peek header carries source app, age, boards, sync chip; insight strip + hero 'Content' label removed; caption 'title written on-device' | ClipPeek.swift:280-284,:319-359,:362-416; AppModel.swift:1943 | App/age/boards exist; per-clip sync state and title-provenance flag new | GC-V5-6, GC-09 | UI: peek-source-app / peek-board-* ids; snapshot vs board | 3 | done — 5e6da43, bc4c9f6 (Q19: upload-state chip, no caption, expiry chip in header; Q22: stripe + decoded chip only; Q23: pins win); PanelProvenanceUITests + UploadStateProviding tests + snapshots |
| GC-V4-2 | feature | pick | — | Panel | Dock primary reads 'Paste into <App>'; footer chip names the frontmost app | ClipPeek.swift:781-817; PeekActionButton.swift:59-98; AppModel.swift:1033-1037; PasteBackWorkflow.swift:79-99 | Target bundle id read at paste; observable target while panel shown new | GC-V4-4 | Unit: label resolver (target / none / no Accessibility); UI: PeekDockUITests | 4 | done — 6385cf1 (Q20: 'Paste into <App>', 'Paste' with no target, 'Copy' without Accessibility); PanelCaptureChipTests + PanelBehaviourUITests + snapshots panel-link-peek |
| GC-V4-3 | UI | pick | — | Panel | Active scope chip shows count ('All clips · 128'); per-board count in hover help; app chip icon | PanelView.swift:911-942,:956-1031 | Colour dots, app icon, count()/count(inBoard:) exist; count cache new | GC-V5-6 | UI: board-all label; unit: count cache invalidation | 3 | done — bc4c9f6 (Q21: board total); PanelProvenanceUITests.testActiveScopeChipShowsTheBoardTotal |
| GC-V4-4 | UI | pick | — | Panel | Footer capture chip with colour + cause (green capturing, amber paused, indigo private, red denied) | PanelStatusFooter.swift:37-49,:106-111; PanelCapturePresentation.swift:46-78; StatusItemController.swift:247-269 | Causes + precedence exist; variants, indigo token new | GC-V4-2, GC-07, GC-25, B-GC-02 | Unit: state→chip mapping; UI: PanelUITests footer states | 4 | done — 6385cf1 (one pill per state and cause; storage trouble stays in the banner because an in-memory store still captures; undrawn copy 'Paused · screen locked' and 'Paused'); PanelCaptureChipTests + PanelBehaviourUITests + PanelUITests |
| GC-V5-3 | UI | pick | — | Panel | Untitled (non-sensitive) image rows say what they are | Components.swift:198-250; ClipItemFactory.swift:36-41; ByteSize.swift:15-18 | Size + type stored; pixel dimensions NOT stored (catalog claim wrong) | B-GC-04 | Unit: formatter; UI: PanelAppearanceUITests image filter; snapshot | 3 | done — 5e6da43, bc4c9f6, 1f70b67 (Q10: stored at capture, v27, lazy backfill, not synced; masked rows stay masked); ClipImageInfoTests + PanelAppearanceUITests + snapshot panel-ambient-image |
| GC-V5-6 | UI | pick | — | Panel | Chip text 10→11 pt (Small 9.9 / Large 12.65), height 20→22, glyph 12→13; footer, ⌘N badges, section headers, stack counters stay 10 pt (10 consequences in spec §5) | PanelView.swift:837-849,:916-927,:977-981; Components.swift:68-75; PeekActionButton.swift:100-104; ClipPeek.swift:293,:402; PanelTypography.swift | Style swaps only (iOS already 11 pt) | — | UI: PanelAppearanceUITests compact Spanish; PanelDisplayPreferencesUITests; snapshots ×3 text sizes | 2 | done — 4efbece, 1015741; snapshots panel-link-peek standard/small/large text + PanelAppearance/PanelDisplayPreferences UI |
| GC-05 | UI | pick | — | PanelStates | Empty panel: 'Import from Maccy or CSV…' button + three-key teaching card shown until the first paste | PanelResultsView.swift:193-292; PanelView.swift:1281; MigrationImportView.swift; GlobalShortcuts.swift:9 | Copy + importer exist; card + own 'first paste done' flag new | GC-V4-4, GC-V5-1 | Unit: show/hide rule; UI: card disappears after a paste; snapshot | 3 | done — bc4c9f6, 1f70b67 (Q26: 'Shown once…' is an annotation; footer wording stays with GC-V4-4); PanelFirstRunStageTests + PanelProvenanceUITests + snapshots panel-first-run |
| GC-07 | feature | pick | — | PanelStates, Settings | Private Mode in indigo: since HH:MM, N copies skipped (content never read), auto-off + minutes-left footer, 'Turn off' button, Settings → Privacy auto-off picker | PanelStatusFooter.swift:66-140; PanelCapturePresentation.swift; CapturePreferences.swift:17; CaptureLifecycleController.swift; MacPasteboardMonitor.swift:167; PrivateActivityReceipt.swift; PrivacySettingsTab.swift | Toggle, masking, receipt exist; timestamps, scheduler, picker, indigo token, change counter (changeCount only) new | GC-V4-4, GC-17, SY-V4-8 | Unit: clock-injected auto-off; counter never reads content; UI + snapshot | 4 | done — 6385cf1 (Q18: no default ⌥⌘P, the recorded shortcut or none; Q25: 15 min / 30 min / 1 h / 2 h / until off, default 1 h, 'none read' is a fixed promise); CaptureLifecycleControllerTests + ProductionMonitorTests + CapturePreferencesTests + PanelBehaviourUITests + SettingsPrivacyUITests + snapshots panel-private-mode, settings-privacy |
| GC-08 | feature | pick | — | PanelStates | No results runs the query in other modes/scopes, shows counts as buttons (best highlighted), previews it, ↓ applies | PanelResultsView.swift:262-291; PanelSearchModel.swift:297,:361-418; ClipSearch.swift:7-14; GRDBClipboardStore.swift:340 | Modes, Meaning, Clear filters exist; cancellable count probe + rows + ↓ new | GC-V4-1, GC-V4-3 | Unit: probe with fake source, cancellation; UI: ↓ applies; perf: probe within search budget | 4 | done — af7a8b5 (Q24: 'Older than 30 days' dropped; the most results wins, ties Fuzzy > Exact > Meaning > All boards > Regex); PanelSearchAlternativesTests + SearchTokensUITests + snapshots panel-no-results |
| GC-09 | feature | pick | — | Novel, PanelStates, Panel | Secrets masked everywhere; Mac peek countdown + lifetime bar + reveal + keep longer + delete now; never in widgets/keyboard/Spotlight/MCP | ClipPeek.swift:89-101,:381-390; Components.swift:162-293; RetentionEngine.swift:55-70; WidgetClips.swift:11; KeyboardClips.swift:16; MCPToolRunner.swift:116; LibrarySpotlightService.swift:60; SyncLocalStore.swift:208-221 | Keyboard/MCP/Spotlight exclude; widgets mask; iOS reveal exists; Mac reveal, keep, delete, bar new | GC-25, GC-20, GC-V4-9 | Unit: lifetime cap, reveal timer; privacy: no secret in widget/keyboard/MCP; UI; snapshot | 14 | done (Q12: secrets never sync, uploaded ones deleted from iCloud, remote changes never touch a local secret; Q14: the Mac peek reveals for 10 s and masks again on hide, when previews hide or on a new clip; Q15: no Keep longer; the peek shows the stored mask, a countdown on the row's timer, a lifetime bar on the effective deadline and Delete now); SyncLocalSecretsTests + DatabaseMigrationTests + SecretLifetimeTests + PeekSecretUITests + captures |
| GC-10 | feature | pick | — | Novel, PanelStates, Panel, MenuBarDark | Paste stack with a visible cursor (3/5), done items kept, floating strip, next/skip/back/reset, ends after idle | PasteStack.swift:15; AppModel.swift:1303-1335; GlobalShortcuts.swift:17; PasteStackStrip.swift; PanelSelectionContextBar.swift | FIFO consuming queue exists; cursor model, strip, bridge field, hotkeys new | GC-25, GC-24, GC-V6-8 | Unit: cursor model; UI select → ⌥⌘⏎ → queue; snapshot | 15 | done (Q61/Q18: no ⌘V capture, no defaults, Skip and Back recorders; the queue keeps pasted entries with a cursor, `next` in the accent; a run ends after 2 min idle or a new copy, keeping waiting entries; a non-activating strip under the menu bar shows "3 of 5", the next title masked for a secret or while sharing, Skip / Back / Reset / End run while the panel is closed); PasteStackTests + PasteStackRunUITests + captures |
| GC-12 | feature | pick | — | Novel2, PanelStates | Describe the change: on-device prompt → Was/Will paste diff, chips (Fix grammar…), coaching; hidden without Apple Intelligence (#available macOS 26) | SmartPasteService.swift:15-46,:184; IntelligenceCapability.swift; ClipPeek+SmartPaste.swift | Fixed rewrites + gate exist; prompt path, diff, coaching new | GC-11, GC-V5-5 | Unit: word diff, fake engine; UI: hidden on simulated macOS 15 | 16 | done (Q31: saved prompts are a local list that never syncs, kept only when within 300 characters and free of secrets; Q27: ⏎ pastes the original, ⇧⏎ the result, esc closes it first; "Describe the change…" in the ⌘T list, shown only with Apple Intelligence and for a text that fits one request, runs a frozen, sanitized prompt and shows Was / Will paste as a word diff; Coaching not built); PromptCatalogTests + WordDiffTests + TransformCatalogTests + DescribeChangeUITests (fixture model) + captures |
| GC-11 | feature | pick | — | Novel2, Peek, Panel | One Transform: ⌘T popover (groups + filter) and a reorderable step pipeline with before/after, save as recipe | ClipPeek.swift:569-584,:676-843; ClipPeek+SmartPaste.swift:38-83; PasteTransform.swift; DevActions.swift:56-90; TextRecipe.swift:41-66; TextRecipeExecutor.swift | Most transforms + recipes exist; popover, pipeline, new steps, shortcuts new | GC-12, GC-V4-2 | Unit: catalog group/filter, executor; UI: update PeekDock/TextRecipe/Translation tests | 16 | done (Q30: one Transform ⌘T list with the kind first, Text, Recipes and Smart paste; a row opens the step pipeline with before / after, + Step, drag to reorder, Paste result ⇧⏎ / Copy result / Save as recipe; recipes gain the developer actions, Paste result with Copy's revalidation, a per-recipe shortcut and ⌃⌘V "paste through last transform", all with no default; the clipboard read refuses protected types, secrets, masked kinds, a mid-read change and Private Mode); TransformCatalogTests + RecipeDeliveryTests + PeekDockUITests + TextRecipeUITests + TranslationCapabilityUITests + captures |
| GC-16 | feature | pick | — | Peek | 'Dominant ·' chip with 3 swatches; 'Pick colour · I' eyedropper saves a colour clip; Regions / Image only toggle | ClipThumbnailStore.swift:29-37,:99,:110,:217-258; ClipPeek.swift:189-227,:458-479; AppModel+ManualOCR.swift:192 | Only an average colour exists; palette, eyedropper, I key new | GC-V4-14, GC-01, GC-23 | Unit: palette + point→pixel mapping; UI: I + click → colour row | 5 | done — d3e4bbe, 9ac2ba8, 2c818c1 (Q28: the eyedropper samples the original image's pixel, a swatch click saves a colour clip, 1–3 swatches, Regions / Image only defaults to Regions); ImageColorsTests + PeekColorUITests + snapshots panel-ambient-image |
| GC-04 | UI | pick | — | MenuBarDark | Dark appearance contrast rules: surfaces #1C1C1E/#2C2C2E/#3A3A3C, 10 % white hairlines, 16 % selected wash + 3 pt bar, dark ink on #30D158, no shadows in dark | GanchoColors.swift:21; Components.swift:8-28,:323-338; PanelView.swift:543; PanelShortcutsOverlay.swift:63; PanelController.swift:405 | Bar, greens, materials exist; surface tokens, ink, 16 % wash, shadow gating new | GC-V5-2, SY-V4-3, SY-V4-7 | Unit: tokens + WCAG; dark snapshots | 2 | done — cc193f5, 4efbece (Q35: hex surfaces only in the opaque branch); ContrastTokenTests + dark snapshots; the 7 % / 10 % ambient wash stays with GC-23 |
| GC-23 | UI | pick | — | MenuBarDark | Ambient wash only behind the peek; 7 % dark / 10 % light; 220 ms; none for secrets / private mode | PanelDisplayPreferences.swift:61-87; PanelView.swift:288-292,:430-468; PanelAmbientTintTests.swift:36-39 | Toggle, a11y veto, fade exist; peek-only placement, opacities, secret veto new; existing test asserts the opposite opacity order | — | Unit: veto + opacities (update test); snapshot list untinted | 3 | done — bc4c9f6, 1f70b67 (Q35: 7 % / 10 % is the visible peak); PanelAmbientTintTests + snapshots panel-ambient-image light/dark |
| GC-24 | feature | pick | — | MenuBarDark | Status item menu as a mini-panel: header 'state · N clips · App in front', 5 recents with tiles, ⌘1–5, ⌥ pastes plain, masked secrets, paste-stack row | StatusItemController.swift:147-205; GanchoMenuBarHelper/main.swift:46-81; GanchoMenuBarCommand.swift:62-67; AppModel.swift:69,:899,:1303 | Recents exist only in in-process fallback; production helper is content-free | GC-10, GC-V4-2, GC-V4-3, GC-07, GC-V5-1, GC-25 | Unit: pure menu builder; UI with -use-in-process-status-item | 6 | done — bc420e4 (Q33: the helper forwards the click and the app opens its own menu under the icon; the bridge carries no clip any more); MenuBarMenuPlanTests + MenuBarUITests (menu rows, helper request with another app in front, forged nonce) |
| GC-25 | feature | pick | — | Novel, MenuBarDark, Panel | Hook keeps its shape + one state badge; ⌥-click pause, ⌥⇧-click ignore next; screen share hides previews with a banner naming the app + Show anyway | GanchoMenuBarCommand.swift:187-260; StatusItemController.swift:68,:247-269; GanchoMenuBarHelper/main.swift:32; ScreenShareDetector.swift; MacPasteboardMonitor.swift:92; PanelView.swift:439 | State source + template exist; badges, modifier clicks, sharing app name, preview hiding new | GC-V5-1, GC-24, GC-10, GC-07 | Unit: state→badge; image render test; UI with DEBUG share flag | 6 | done — bc420e4 (Q34: paused amber incl. sharing, private indigo, denied red, ignore-next grey, stack count; no syncing badge; dark glyph on amber and grey; count, not 3/5); MenuBarBadgeTests + MenuBarGlyphTests + MenuBarUITests (⌥ / ⌥⇧ clicks, screen share) + snapshots menu-bar-glyphs, panel-screen-share |
| GC-V5-1 | UI | pick | — | MenuBarDark | Menu shows the real panel shortcut (fix of B-GC-01) | see B-GC-01 | see B-GC-01 | — | see B-GC-01 | 1 | done — a3750fa |
| GC-V4-5 | feature | pick | — | Library | Toolbar search (⌘F), Grid/List toggle, visible New board button | LibraryWindowController.swift:18-26; LibraryView.swift:50; LibraryClipListModel.swift; AppModel+Library.swift:19; ClipSearch.swift | Search engine + New-board flow exist; toolbar, query in list model, List layout new | GC-V4-13, GC-V4-6 | Unit: LibraryClipListModel query; UI: VisualLibraryUITests search; snapshot | 8 | done — de38569, 8710ba1 (Q37: clips-only search with the scope and chip; Grid / List persists; New board in the toolbar); LibraryClipListModelTests + LibraryBrowseUITests + snapshot library |
| GC-V4-6 | feature | pick | — | Library | Cards with kind tile, host headline, board + sync chips, masked secret with expiry, meta line, hover Copy/Pin/Board, date groups | LibraryClipCard.swift; LibraryView+Browsing.swift:59-179; Components.swift; DateBucket.swift | Tile, monogram, countdown, date buckets exist; card layout, membership read, sync chip new | GC-V4-13, GC-V5-3, GC-V4-23, GC-09 | Unit: grouping/formatters; UI hover actions; privacy: masked card; snapshot | 8 | done — de38569, 8710ba1 (Q13/Q12: stored mask, kind title, no sync claim; Pinned group first; board chips; no Copy on protected cards); LibraryBrowseTests, MaskedTailTests, LibraryProMeterTests + LibraryBrowseUITests + snapshot library |
| GC-V4-7 | UI | pick | — | Library | Sidebar: saved-filter glyph + count, snippet keyword keycap, two-limit Pro meter from code constants | LibraryView+Sidebar.swift:50-219; BoardIdentityEditor.swift:7-37; UserTier.swift; Pinboards.swift:50-51; SnippetLibrary.swift:7 | Marks, badges, pressure() exist; filter count query, keycap, meter new | GC-28 | Unit: meter fraction from constants; UI sidebar; snapshot | 8 | done — de38569, 8710ba1 (Q38: three ceilings, escalating tail); LibraryProMeterTests + LibraryBrowseUITests + snapshot library |
| GC-17 | UI | pick | — | Settings | Privacy settings with four status tiles first, grouped sections, Privacy Center card at sidebar bottom | PrivacySettingsTab.swift:14-73; SettingsView.swift:99-116 | Controls + counts exist; tiles, card, size on disk, weekly skip query new | GC-07, GC-V5-2 | UI: SettingsPrivacyUITests new ids; snapshot | 9 | done — 32638ebf, c7579727 (Q41: protected skips over 7 days; truthful screen-share copy; footnotes kept, shortened); StoreHealthTests + SettingsPrivacyUITests + snapshot settings-privacy |
| GC-19 | UI | pick | — | Settings | Concealed-types rule as a static card (no toggle); Intelligence becomes a row | CaptureSettingsTab.swift:18-29; DenylistSettingsSection.swift:45-69; SensitivePasteboardTypes.swift:8-12 | Rule constants exist; card + strings new; 'also concealed' chip has no data source | GC-V5-2 | UI: DenylistUITests; snapshot | 9 | done — 32638ebf, c7579727 (Q17: no chip; the rule is a static card); DenylistUITests + snapshot settings-capture |
| GC-20 | feature | pick | — | Novel2, Settings | Stepped retention control with secret cap + 'Forget recent clips' (5/15/60 min, count first, undoable) | RetentionPolicy.swift:6-46; RetentionSettingsTab.swift; RetentionEngine.swift:25-65; DeletionCoordinator.swift:131 | Windows 24h…never + batch delete with undo exist; 30m/1h/8h, delete-by-time, preview count new | GC-17, GC-21, GC-09, GC-07 | Unit: policy decode (migration of stored windows), purge; UI | 9 | done — 32638ebf, c7579727 (Q39: timeline over the pickers + Forget recent clips, undoable); RetentionTimelineTests + StoreHealthTests + RetentionSettingsUITests + snapshot settings-retention |
| GC-21 | UI | pick | — | Settings, iPhoneFlows | Privacy Center opens with a 'Verify' group (Mac + iPhone) | PrivacyCenterView.swift:26-320; IOSPrivacyCenterView.swift:26-260; SyncEngine.swift:6-13 | Force sync, dates, last-read, MCP counts exist; Verify action, encryption-state flag new | GC-V5-2, GC-V4-12 | UI: PrivateActivityReceiptUITests + PrivacyCenterUITests order; snapshot | 9 | done (Mac) — 32638ebf, c7579727 (Q40: Verify runs on this Mac; undrawn sections stay below; last read shows its time); StoreHealthTests + PrivacyCenterVerifyUITests + snapshot privacy-center; iPhone half c58a868 (same Verify; Off · Pro on Free; undrawn sections kept) |
| GC-V5-2 | system | pick | — | Settings | Accent text and Privacy hero pass AA (fixes B-GC-02, B-GC-03) | see B-GC-02/03 | see B-GC-02/03 | SY-V4-3 | see B-GC-02/03 | 2 | done — see B-GC-02/03 |
| GC-V5-4 | UI | pick | — | Settings | Settings sidebar ring follows the selection (fix of B-GC-05) | see B-GC-05 | see B-GC-05 | — | see B-GC-05 | 1 | done — a2c887b |
| GC-V5-5 | UI | pick | — | Settings | Intelligence pipeline fits its window (fix of B-GC-06) | see B-GC-06 | see B-GC-06 | — | see B-GC-06 | 1 | done — 9c2a429 |
| GC-26 | UI | pick | — | iPhone | Pasteboard row becomes a status card: kind tile, 'Sensed, not read…', ↓Paste pointer, 'Saved · Open' for 4 s | PasteboardStatusRow.swift:47-146; CaptureShell.swift:301-312; IOSAppModel.swift:44,:48,:1045-1186; IntentionalPasteboardSource.swift | Hints + Saved state exist; card, Open (keep saved id), 4 s window new | GC-36, GC-V4-17 | Unit: hint→tile; UI: IntentionalCaptureUITests/CaptureFlowUITests; snapshot | 11 | done — 118e976 (Q45: keep ⓘ; empty and accessibility sizes keep the one-line row; back to Saved after 4 s); SensedClipboardTests + CaptureFlowUITests (Open) + captures |
| GC-V4-8 | UI | pick | — | iPhone | Counts on active rail chip + section headers; device glyph + name on rows from another device | CaptureView.swift:44-57,:206-310; IOSAppModel.swift:429-438; Components.swift (ClipCard sourceTimeLine); ClipItem.swift:24 | sourceDeviceName stored + synced; headers, device line new | GC-28, GC-V4-11 | Unit: show-device predicate + counts; UI seeded foreign device; snapshot | 11 | done — c9ada7f, 118e976 (Q46: stored device name on its own line, no cloud beside it; counts only when the group is complete); ClipCardPrivacyTests + HistoryListViewModelTests + HomeV4UITests |
| GC-V4-9 | UI | pick | — | iPhone | Secret rows show title, stored masked tail, source/time, orange expiry pill; widgets/lock screen unchanged | Components.swift (ClipCard previewsHidden split); SensitiveDataDetector.swift:258-289 | Mask + expiresAt exist; flag split, pill new | GC-09 | Unit: ClipCardPrivacyTests/ExpiryTests; WidgetClips still '•••'; snapshot | 11 | done — c9ada7f (Q13: kind as title, stored mask, source, expiry pill; widgets keep dots); ClipCardPrivacyTests + captures |
| GC-V4-10 | UI | pick | — | iPhone | Active type/app filters as removable chips + 'Clear filters'; Filters button tinted when active | HistoryFilterMenu.swift; CaptureView.swift:320-364; CaptureShell.swift:148-153 | Filters + clearFilters exist; chip row new (44 pt targets) | GC-V4-1 | UI: SourceAppFilterUITests; unit chip mapping; snapshot | 11 | done — 118e976 (Q47: chips under the rail; Clear keeps the board); HistoryFilterChipsTests + HomeV4UITests |
| GC-V4-11 | feature | pick | — | iPhone | Search shows answer card + 'Related by meaning' section | CaptureView.swift:119-190; IOSAppModel.swift:787-802; MeaningSearchState.swift; HybridRetrieval.swift | Answer card + shared retrieval exist; iOS MeaningSearchSource + section new | GC-V4-8 | Unit: HistoryListViewModelTests, MeaningSearchStateTests; UI seeded; snapshot | 11 | done — 873a6e5, 118e976 (Q48: automatic; synced clips backfilled on device for Pro; tap-to-copy kept); HistoryListViewModelTests + EmbeddingRefreshServiceTests + SemanticSearchTests + HomeV4UITests |
| GC-27 | UI | pick | — | iPhoneFlows | Clip detail: provenance pills, inline title, link hero chips, full-width Copy primary, Share·Pin·Board·Snippet row, chips | ClipDetailView.swift:135-158,:188-278,:339-527; ClipTitleEditor.swift:23; CaptureShell.swift:106-117 | All actions + ids exist; layout, hero, chips new (also iPad) | GC-V5-2, GC-33, GC-V4-18 | UI: existing detail tests + Copy primary; snapshot | 11 | done — 4a20d85 (Q49: Markdown link added; × on the suggestion chip; Board and + Add both stay; Snippet disabled, shown as set; no left bar on the hero); ClipLinkPartsTests + IOSFlowsV4UITests + detail tests unchanged + captures |
| GC-28 | UI | pick | — | iPhoneFlows | Boards with identity, counts, 'n of 3 · Free' from constants, Snippets group | BoardsHomeView.swift:146-155,:222-243,:270-297; Pinboards.swift:9-60; SnippetLibrary.swift:7,:44 | Colour, counts, swipe exist; limit header, sync state, Snippets list new | GC-33, GC-V4-7, GC-V4-12 | Unit: formatter from constant; UI -seed-sample-boards; snapshot | 11 | done — c58a868 (Q50: Synced / Waiting to sync / On this iPhone; Snippets group by keyword); BoardSyncStateTests + IOSFlowsV4UITests + captures |
| GC-V4-12 | UI | pick | — | iPhoneFlows | Settings with status subtitles and five capture-path rows | IOSSettingsView.swift:23-98; IOSAppModel.swift:98,:109; IntelligencePreferences.swift | Subtitle data exists; formatter + capture rows new | GC-28, GC-21, GC-36 | Unit: formatter; UI navigation; snapshot | 11 | done — c58a868 (Q50: static capture rows with How steps; Pro on Pro reads every limit removed); IntelligenceSummaryTests + IOSFlowsV4UITests + captures |
| GC-33 | UI | pick | — | iPad | Sidebar identity + counts, docked pasteboard card with its own Paste, toolbar search/Boards/Settings/count, counted date headers, keyboard legend | IPadSplitView.swift:18-214; CaptureShell.swift:154-174,:301; PasteboardStatusRow.swift; CaptureView.swift:446-460; BoardsHomeView.swift:291 | Split view, filters, shortcuts, counts exist; per-kind counts, docked card, headers, legend new | GC-28, GC-26, GC-V4-8, GC-V4-9, GC-27, SY-V4-3 | Unit: per-kind count; UI iPad sim; snapshot | 12 | done — 8d92338, f139c32, c9164cf, 04d1cd1 (Q51: letter tiles, the Mac's five type groups, a wash per section, Paste docked or in the toolbar, Select out); ScopeCountsTests + HistoryListViewModelTests + SourceAppTileTests + IPadSplitUITests + captures |
| GC-34 | feature | pick | — | iPad | Drag a clip into another app (detail hero card as drag source; masked clips advertise nothing) | ClipDragPayload.swift; ClipShareItem.swift; IOSAppModel.swift:668; IPadSplitView.swift:99-102 | Drag rules + Transferable exist; iOS drag source + URL rep new | GC-27, GC-33 | Unit: representations (masked → none); UI ids; manual Split View with Notes | 12 | done — e9a9224, 01bf098, 5d6371b (Q52: hero and rows drag on iPad; no hint under the no-filler-copy rule); ClipShareItemTests + ClipDragPayloadTests + IPadSplitUITests |
| GC-35 | UI | pick | — | Onboarding | Mac first run in four steps: privacy promise → Accessibility (with/without cards) → shortcuts → live first copy ending in the real panel; page dots | OnboardingView.swift:13-166; GlobalShortcuts.swift:10-17; ShortcutRecorder.swift; AppModel.swift:689,:1039-1044 | Window, live polling, live clips, importer, panel hand-off exist; privacy step, cards, dots, rows, status line new | GC-V7-1, GC-V5-2, GC-V5-1 | UI: update ActivationFunnelUITests + MigrationImportUITests; snapshots 520×420 per step | 10 | done — 1434f10, b41c455 (Q43: Skip for now advances; inline recorder; no versioned flag; the shortcut only on the button; Q18: unset shortcuts say Not set); OnboardingFlowTests + ActivationFunnelUITests + OnboardingUITests + MigrationImportUITests + snapshots onboarding-step1…4 light/dark |
| GC-36 | UI | pick | — | Onboarding | iPhone first run: page 2 explains 'Sensed, not read' with example row, keyboard/widget/share rows | IOSOnboardingView.swift; GanchoiOSApp.swift:35,:115-124; PasteboardStatusRow.swift; CaptureView.swift:447 | Page 1, copy, paste control exist; paging + page 2 new | GC-V5-2 | UI: iOS paging + flag; snapshot 390×844 | 10 | done — f9e0153 (Q44: Next on page 1; a label above the system Paste control; a paste opens the saved clip; iPad included); IOSOnboardingUITests + page 2 captures light/dark |
| GC-V4-13 | feature | pick | — | Library | Kind chips + Newest/Oldest sort in the scope header with a total count | ClipKindFilter.swift:7-32; LibraryView+Browsing.swift:27-33; GRDBClipboardStore.swift:441 | ClipKindFilter + chip UI exist; kind filter in query, ascending sort, total count new | GC-V4-5 | Store tests for order + count; UI chip test; snapshot | 8 | done — de38569, 8710ba1 (Q37: the panel's kind set; Newest / Oldest; the header reads the store total); LibraryBrowseTests + LibraryBrowseUITests + snapshot library |
| GC-V4-14 | feature | pick | — | Peek | Colour hero: swatch band, HEX/RGB/HSL/Swift rows with copy, contrast cards (on white / on #1C1C1E), Convert ⇧⏎; fix 8-digit hex parser mismatch found in DevActions | ClipPeek.swift:495-506; DevActions.swift:238-249,:546-630 (:551 bug); ContrastingForeground.swift; Color+Hex.swift | convertColor exists; Swift format, contrastRatio, ⇧⏎ new | SY-V4-3, GC-V4-2, GC-16 | Unit: formats, ratios (#008080 = 4.77/3.56), 8-digit hex parity; UI seeded colour clip; snapshot | 5 | done — 179ea87, d3e4bbe, 9ac2ba8, 2c818c1 (Q29: dock is Paste into <App> · Plain · Convert ⇧⏎ · Pin · Board; ratios truncated to one decimal, AA / AA Large / below AA; Swift with 3 trimmed decimals); ColorValueTests + ContrastTokenTests + DevActionsTests + PeekColorUITests + snapshots panel-color-peek |
| GC-V4-15 | feature | pick | — | iPhoneSurfaces | Share sheet shows what will be saved: preview, title, board chips + New board, Pin it, Save, footer; 'Add to board' header 16/8 pt; 'Save instantly' setting keeps today's path | ShareViewController.swift:15-101; SharedInbox.swift:63-66; IOSAppModel.swift:1061; IOSSettingsView.swift:51-57; project.yml:459 | Extraction + sealed inbox exist; sheet, PreparedCapture fields, drain, GanchoShare string catalog new | GC-V5-2 | Unit: PreparedCapture round-trip + drain; snapshot; device share; memory check | 13 | done — 41dfed7, 4cf1d95, e09f578 (Q53: the sharing app's title; a sealed board list; the sheet by default; no footer); ShareChoicesTests + ShareChoicesPlanTests + ShareSheetUITests (Safari end to end) + captures |
| GC-V4-16 | feature | pick | — | iPhoneSurfaces | Large widget: 6 rows, board chips (10 pt below header, 12 pt above list), rows 8 pt apart, sync age, masked countdown, Save + Open | RecentClipsWidget.swift:16-125; WidgetClips.swift:34-89 | Small/medium, masking, Save intent exist; large layout, chip intent, last-sync date new | GC-V7-1, GC-V6-8 | Unit: entry; snapshot .systemLarge measuring 10/12/8 | 13 | done — bf2dad9, a2671b6 (Q54: All + Favorites + first boards; the iPhone's masked row; small and medium unchanged); WidgetClipsTests + previews |
| GC-V4-17 | feature | pick | — | iPhoneSurfaces | Live Activity 'Copy again' + 'Open in Gancho'; ends on next copy | ClipLiveActivity.swift:17-77; ClipActivity.swift:10-26; ClipActivityController.swift:24-58 | Activity, masking, 3-min end exist; clip id in state, LiveActivityIntent new | GC-V6-8 | Unit: intent eligibility; device test | 13 | done — bf2dad9, f845cbd (Q55: no Copy again for a secret; ends on a pasteboard change; Copy again asks to unlock; on the lock-screen banner only, by the owner's 2026-10-30 call); device check done |
| GC-V4-18 | feature | pick | — | iPhoneSurfaces | Text in image on iPhone: regions, per-line copy, secret line held back, Copy all · N, Save text, Translate | ManualImageTextService.swift; ImageTextReading.swift; ManualOCRSession.swift; ClipDetailView.swift:287-306 | OCR stack exists in packages; iOS views + per-line hold-back new | GC-27, GC-V5-2 | Unit: per-line sensitivity; UI seeded; snapshot | 13 | done (Q32/Q56: read on open, fresh pass for the regions, held in memory only, no footer; nothing copied without a tap; a flagged line is held out of Copy all and Save until revealed; Translate hidden for any result with a secret, Mac parity); ManualOCRSessionTests + ImageTextReadingTests + ImageTextUITests + captures |
| GC-V4-19 | UI | pick | — | iPhoneSurfaces | Keyboard marks the inserted row until the text field changes | KeyboardModel.swift:154-178; KeyboardView.swift:168-287 | Rows + insert exist; inserted state new | GC-V6-8 | Unit: model; device test | 13 | done (Q57: every row typed into the current field keeps a green tint and an `inserted` pill until the field's document changes; an image, which goes to the pasteboard, is not marked); KeyboardInsertedMarksTests + a simulator run of the real keyboard + captures |
| GC-V4-20 | UI | skip | — | Archive (from Motion) | Panel arrives from the hook under 100 ms | — | Not implemented; current entrance stays | — | — | — | not implemented (SKIP) |
| GC-V4-22 | UI | maybe | no entiendo la utilidad de esto, pero siento que no es necesario | Motion | Paste press → check → hide → ⌘V (adds ~340 ms per paste) | PeekActionButton.swift:65-67; PanelController.swift:175-178; PasteBackWorkflow.swift:39,:90-96 | Order hide→⌘V exists | GC-V4-24 | — | — | pending decision (MAYBE, not implemented) |
| GC-V4-23 | feature | pick | — | Motion | Drop a clip on a board (panel rail chip, Library sidebar): ring + 1.04 scale, + badge, count tick, toast 'Added to <board>' + Undo ⌘Z | PanelView.swift:1009; LibraryView+Sidebar.swift:17-24,:103-124; ClipDragProvider.swift; ClipDragPayload.swift:29-49; AppModel.swift:1818-1836,:1970-1990; ToastPresenter.swift | Drag-out, membership write, Undo toast exist; in-app drag type, drop targets, ⌘Z new | GC-V4-24 | Unit: drop eligibility; UI: drag row onto board-<uuid> → gancho-toast/toast-undo | 7 | done — b3ffecc, 597b999 (Q36: in-app drags only, no refusals; already a member says so; row pulse instead of an AppKit shrink; every assign toast names the board with Undo and ⌘Z); BoardDropTests + BoardDropUITests (rail, Library, ⌘Z, field undo, panel stays put) + snapshots panel-board-drop-target |
| GC-V4-24 | system | pick | — | Motion | Motion tokens settle/arrive/swap + leave (140 ms ease-in) + press (.96, 80 ms); one Reduce Motion substitution policy; literal durations moved onto tokens | GanchoMotion.swift:5-36; GanchoMotionTests.swift; PanelView.swift:291,:309; PanelResultsView.swift:170; ClipPeek.swift:168; DenylistSettingsSection.swift:178; PeekImageText.swift:38,:41,:281,:395,:499; ClipDetailView.swift:67 (iOS); LibraryView+Sidebar.swift:118; PasteStackStrip.swift:26 | quick/smooth/replace + nil gate exist; leave, press, policy new | — | Unit per token × Reduce Motion; source-scan guard against literal durations | 2 | done — 4efbece, 85c3dac (Q6: 100 ms fade; leave/press are tokens); GanchoMotionTests + DesignTokenGuardTests motion gate |
| GC-V6-1 | feature | pick | — | Novel | Up next: one predicted clip above the list for the front app; ⌘↩; off by default | PasteBackWorkflow.swift:79; AppModel.swift:1033; GanchoDatabaseMigrator.swift; ReuseController.swift:114; IntelligencePreferences.swift; PanelView.swift:586 | Front app + use counts exist; per-paste table (migration), ranker, slot new | GC-V6-8, GC-25 | Unit: ranker + migration; UI seeded pastes; perf: panel open unchanged | 17 | done (Q58: the switch lives in Intelligence, off by default; local `paste_event` table (v29) written only while Up next is on and outside Private Mode, erased when it is turned off, 30-day window, cascades with the clip, never synced or exported, no secrets or masked kinds; heuristic ranker only, the slot needs two pastes into the front app and hides when it is already the first row, while searching or filtering, and while previews are hidden; ⌘↩ pastes it; no footer hint); PasteEventLogTests + UpNextRankerTests + UpNextUITests (seeded log, ⌘↩, switch-off erase) + captures |
| GC-V6-2 | feature | pick | — | Novel | Double-copy merge (second ⌘C within ~600 ms appends), splittable in the peek | MacPasteboardMonitor.swift; AdaptivePollingPolicy.swift:29; ClipRecordMapper.swift; ClipPeek.swift | No merge code; clip.parts column (migration + sync mapping) new | GC-25, GC-V6-3 | Unit: merge/split, fake pasteboard; sync round-trip; UI Split | 18 | in progress (Q59: double ⌘C on the same selection — same text, same app, the next change count, ≤600 ms — appends to the clip before it; off by default in Settings › Capture; 80 ms polls for 600 ms after a change only while on; parts sync encrypted; HUD + soft sound with opt-out, no haptic, no badge. 18a done: detection, merge, parts column + sync, switch; 18b: peek parts, separator chips, Split, HUD, sound); ClipPartsTests + DoubleCopyMergeTests + monitor/policy tests + DoubleCopyMergeUITests |
| GC-V6-3 | feature | pick | — | Novel | Copy-time action HUD (2 s, non-activating) for colour/address/tracking/OTP/URL; per-kind switches; hidden in private/sharing | RuleClassifier.swift:22; ClipContentKind.swift; DevActions.swift; PanelController.swift:348; CaptureSettingsTab.swift; SensitivePasteboardTypes.swift:18 | Kinds + actions exist; HUD window, OTP detector, prefs new | GC-25, GC-09, GC-V6-2 | Unit: show-HUD policy (never for vetoed copies); UI; snapshot | 19 | blocked: Q60 |
| GC-V6-4 | feature | pick | — | Novel | Notch shelf: drag toward the notch (or hook) → boards + Extract text / Resize / Strip location / New board | ClipDragProvider.swift; PanelController.swift:297; ImageTextExtractor.swift; AppModel.swift:1866,:1963 | Drag-out only; drop window, geometry, resize, EXIF strip new | GC-V4-23 | Unit: geometry + EXIF strip; UI drop; perf: no global drag monitor | 20 | blocked: Q62 |
| GC-V6-5 | feature | pick | — | Novel2 | Jump to context: ⌘J shows clips ±2 min around a result; esc returns | PanelSearchModel.swift; PanelView.swift:605; GRDBClipboardStore.swift:422 | createdAt indexed, ⌘J free; window query + mode new | — | Unit: window query; UI ⌘J/esc | 21 | blocked: Q64 |
| GC-V6-6 | feature | pick | — | Novel2 | Agent reads you can see: menu-bar dot + HUD with Revoke, client + scope on ledger rows, 'Exposed to agents' board badge | MCPAccessStore.swift:58; MCPToolRunner.swift:362; GanchoCLI.swift:48; GanchoMenuBarHelper/main.swift:117; IntegrationsSettingsTab.swift | Client on ledger exists; content-free cross-process notification, dot, HUD, badge new | GC-25, GC-24, GC-21 | Unit: payload is content-free; runner; UI | 22 | blocked: Q65 |
| GC-V6-7 | feature | pick | — | Novel2 | Suggested snippets (Keep/Never/Dismiss) + smart placeholders {clipboard offset=1}, {date +2d}, {cursor}, \| trim / \| uppercase | SnippetLibrary.swift:7-10,:236; SnippetTemplate.swift; SnippetFillSheet.swift; LibraryView+SnippetEditor.swift | One-shot suggestion + {field} exist; state table, grammar, use log new | GC-V4-7, GC-V6-1 | Unit: parser + state; UI; migration of existing placeholders | 23 | blocked: Q66 |
| GC-V6-8 | feature | pick | — | Novel2, iPhoneSurfaces | iPhone: Up next in the keyboard, capture state in Control Center, Live Activity stack position | KeyboardModel.swift; KeyboardClips.swift:5; SaveClipboardControl.swift; ClipActivity.swift:10; ClipActivityController.swift | Keyboard, control, Live Activity exist; shared Up next id, toggle control, fields new | GC-V6-1, GC-10, GC-09, GC-V4-19, GC-V4-17 | Unit: payloads; UI make test-ui-ios | 24 | blocked: Q67 |
| GC-V7-1 | UI | pick | — | Brand (+ Onboarding, MenuBarDark, iPhoneSurfaces) | Keep current icon; replace SF 'paperclip' with the brand mark at OnboardingView.swift:58 (tile), RecentClipsWidget.swift:89 (bare template 12 pt), WrappedView.swift:14 (bare mark, brandGreen); add Mac GanchoMark.imageset; byte-parity check of SVG copies | OnboardingView.swift:58; RecentClipsWidget.swift:89; WrappedView.swift:14; Apps/GanchoMac/Assets.xcassets (new GanchoMark.imageset); Resources/Brand/*.svg | 13-step list verified; all assets exist except Mac imageset; menu-bar template already = SVG | — | Unit: SVG copies byte-identical; grep no 'paperclip'; snapshots of the three spots | 1 | done — c470fdf; BrandAssetParityTests + snapshots onboarding/wrapped (widget: build only) |

## Completeness check

Run on 2026-10-21 against the text of all 17 Gancho v4 boards plus V4_System_Components (pattern `GC-…`, `B-GC-…`, `SY-V4-…`).

1. **Counts:** 73 rows = 62 Gancho items + 5 SY + 6 bugs, matching the expected numbers (see Counts).
2. **Every ID on a board is a row or explained:** 77 distinct IDs found; 57 are rows, 20 are not rows and all are explained below (Archive, shipped, folded or legacy). Unexplained: none.
3. **Rows whose ID is not written on any board text:** B-GC-01, B-GC-02, B-GC-03, B-GC-04, B-GC-05, B-GC-06, GC-V4-10, GC-V4-12, GC-V4-23, GC-V4-24, GC-V4-4, SY-V4-3, SY-V4-6, SY-V4-7, SY-V4-8, SY-V4-9. These are expected:
   - Bug IDs live only in the bug log and map to their item's board.
   - SY items are titled by rule name on V4_System_Components.
   - GC-V4-4, GC-V4-10, GC-V4-12, GC-V4-23 and GC-V4-24 are drawn on their catalog board under a card title instead of the ID.
   - Each spec maps these cards to their IDs (for example, specs/V4_System_Components.md §2–§4 and specs/V4_Gancho_Panel.md coverage).
4. **Every card and numbered pin is covered:** each of the 18 specs has a Coverage table that maps every card, frame and pin to an ID, "context only", "kept" or Archive. Drawn elements without an ID are raised as questions, not built silently:
   - Panel: the 4 pt hero kind stripe, URL part chips and new footer hints (Q22).
   - Peek: the Regions / Image only toggles (filed under GC-16) and the image footer hints (Q32).
   - Library and iPad: the `Select` button (Q37, Q51).

| ID found on boards | Boards | In table? | Explanation if not a row |
|---|---|---|---|
| GC-01 | Archive, Overview, Panel | yes |  |
| GC-02 | Archive, Overview | no | Dropped (Archive): panel minimum 720 pt; ⌘G gallery covers visual browsing. |
| GC-03 | Archive, Overview | no | Dropped (Archive): filmstrip; ⌘G gallery covers it. |
| GC-04 | Archive, MenuBarDark, Overview, Peek | yes |  |
| GC-05 | Archive, Overview, PanelStates | yes |  |
| GC-06 | Archive, Overview, Panel, PanelStates | no | Shipped: capture notice banner (paused · private · denied · screen share · storage); kept unchanged. |
| GC-07 | Overview, PanelStates, Settings | yes |  |
| GC-08 | Archive, Overview, Panel, PanelStates | yes |  |
| GC-09 | Archive, Novel, Overview, Panel, PanelStates | yes |  |
| GC-10 | Archive, Novel, Overview, Panel, PanelStates | yes |  |
| GC-11 | Archive, Novel2, Overview, Panel, Peek | yes |  |
| GC-12 | Archive, Novel2, Overview, PanelStates | yes |  |
| GC-13 | Archive, Overview, Peek | no | Shipped 0.9–0.10 (PeekImageText regions, per-line copy); kept on Peek. |
| GC-14 | Archive, Overview, Peek | no | Shipped 0.9–0.10 (PeekImageText); kept on Peek. |
| GC-15 | Archive, Overview, Peek | no | Shipped (PeekImageText translation + entity chips); moved to Archive in the 17 Oct pass. |
| GC-16 | Archive, Overview, Peek | yes |  |
| GC-17 | Archive, Library, Overview, Settings | yes |  |
| GC-18 | Archive, Overview, Settings | no | Shipped (DenylistSettingsSection: icon, bundle id, Add app menu, built-in exclusions); kept as built. |
| GC-19 | Archive, Overview, Settings | yes |  |
| GC-20 | Novel2, Overview, Settings | yes |  |
| GC-21 | Overview, Settings, iPhoneFlows | yes |  |
| GC-22 | Archive, Overview | no | Deferred (Archive): per-board sync needs schema work; sync stays one Pro toggle. |
| GC-23 | Archive, MenuBarDark, Overview | yes |  |
| GC-24 | Archive, MenuBarDark, Overview | yes |  |
| GC-25 | MenuBarDark, Novel, Overview, Panel | yes |  |
| GC-26 | Archive, Overview, iPhone | yes |  |
| GC-27 | Overview, iPhone, iPhoneFlows | yes |  |
| GC-28 | Library, Overview, iPhoneFlows | yes |  |
| GC-29 | Archive, Overview, iPhoneSurfaces | no | Folded into GC-V4-15 (share sheet). |
| GC-30 | Archive, Overview, iPhoneSurfaces | no | Shipped (keyboard board chips); the inserted mark is GC-V4-19. |
| GC-31 | Archive, Overview, iPhoneSurfaces | no | Small, medium and control widgets shipped; the large widget is GC-V4-16. |
| GC-32 | Archive, Overview, iPhoneSurfaces | no | Live Activity shipped without actions; the actions are GC-V4-17. |
| GC-33 | Archive, Overview, iPad | yes |  |
| GC-34 | Overview, iPad | yes |  |
| GC-35 | Archive, Onboarding, Overview | yes |  |
| GC-36 | Onboarding, Overview | yes |  |
| GC-37 | Archive, Overview | no | Legacy motion ID → GC-V4-20 (skip). |
| GC-38 | Motion, Overview | no | Legacy motion ID → GC-V4-21 (shipped, Archive). |
| GC-39 | Motion, Overview | no | Legacy motion ID → GC-V4-22 (maybe). |
| GC-40 | Archive, Motion, Overview | no | Shipped (iPhone swipe actions + context menu). |
| GC-41 | Motion, Overview | no | Legacy motion ID → GC-V4-23. |
| GC-42 | Motion, Overview | no | Legacy motion ID → GC-V4-24. |
| GC-43 | Archive, Overview | no | The catalog + the Archive board themselves; nothing to build. |
| GC-V4-1 | Archive, Novel2, Overview | yes |  |
| GC-V4-11 | Archive, Overview, iPhone | yes |  |
| GC-V4-13 | Archive | yes |  |
| GC-V4-14 | Archive | yes |  |
| GC-V4-15 | Archive | yes |  |
| GC-V4-16 | Archive | yes |  |
| GC-V4-17 | Archive | yes |  |
| GC-V4-18 | Archive | yes |  |
| GC-V4-19 | Archive | yes |  |
| GC-V4-2 | Archive | yes |  |
| GC-V4-20 | Archive, Motion | yes |  |
| GC-V4-21 | Archive, Motion, Overview | no | Shipped (shared selection geometry, blur-replace, numericText); moved to Archive. |
| GC-V4-22 | Motion | yes |  |
| GC-V4-3 | Archive, Overview, Panel | yes |  |
| GC-V4-5 | Archive | yes |  |
| GC-V4-6 | Library, Overview | yes |  |
| GC-V4-7 | Archive, Library, Overview | yes |  |
| GC-V4-8 | Archive | yes |  |
| GC-V4-9 | Archive | yes |  |
| GC-V5-1 | MenuBarDark, Overview | yes |  |
| GC-V5-2 | Overview, Settings | yes |  |
| GC-V5-3 | Overview, Panel | yes |  |
| GC-V5-4 | Overview, Settings | yes |  |
| GC-V5-5 | Overview, Settings | yes |  |
| GC-V5-6 | Archive, Overview, Panel | yes |  |
| GC-V6-1 | Novel, Novel2, Overview | yes |  |
| GC-V6-2 | Novel | yes |  |
| GC-V6-3 | Novel | yes |  |
| GC-V6-4 | Novel | yes |  |
| GC-V6-5 | Novel2 | yes |  |
| GC-V6-6 | Novel2 | yes |  |
| GC-V6-7 | Novel2 | yes |  |
| GC-V6-8 | Novel2 | yes |  |
| GC-V7-1 | Brand, Overview | yes |  |

## Feasibility summary

- **Ready now (no question blocks them):** .
- **Everything else** is blocked on at least one owner question (below). The specs say exactly which part exists and which is new.
- **Claims on the boards or in the catalog that the code contradicts.** Recorded so nobody builds on them:
  - B-GC-04 is a masked sensitive image, not an untitled one.
  - Image pixel dimensions are not stored, contrary to what GC-V5-3 assumes.
  - Sensitive clips synced to iCloud until Phase 14a (`SyncLocalStore.pendingUploads()` had no sensitive filter), while several boards said "never synced". Since 14a (Q12) they never sync.
  - Secrets are stored masked as `●●●● 4Q2v`, not `sk_live_••••4Q2v`.
  - Secret lifetime can only be shortened today, but the boards add "Keep 10 more min".
  - OCR holds back every line when any secret is found, not just the secret line.
  - No default shortcut exists for Private mode or for paste-from-stack.
  - The production menu-bar helper is content-free, which affects the GC-24 mini-panel. *(Resolved in Phase 6: the app draws the menu; the helper keeps no clip.)*
  - There is no ⌫ or ⌘. key binding in the panel, although Archive marks them shipped.
  - The keyboard extension has no snippet keywords.
  - iOS has no embedding backfill for clips synced from the Mac.
- **Real defect found outside the log — RESOLVED in Phase 5 (179ea87):** 8-digit hex is parsed two ways. `Color(hexString:)` reads `#RRGGBBAA`, but `DevActions.parseColor` drops the first two digits (`DevActions.swift:551`). The fix goes with GC-V4-14 (Phase 5). It must be fixed before the colour hero ships, or the swatch and the formats will disagree.

## Phases

One branch and one PR per phase: `design-v4/fase-N-<topic>`, from an up-to-date `main`. Each phase closes with:

- the build green, `make lint` and `make test` green;
- the UI tests for every flow it touches green (`make test-ui`, `make test-ui-ios`);
- snapshot tests for every changed screen, light and dark, at each device size;
- before/after captures in `docs/design-v4/screenshots/fase-N/`;
- `/code-review-pr-fix <PR> high` applied and every test re-run;
- PLAN.md updated, then a stop for owner review.

Snapshot tests use `swift-snapshot-testing` (Q2), with baselines per device size, light and dark.

Features from the Novel boards ship behind an off-by-default preference key (the existing pattern: hidden `UserDefaults` key, flipped by a DEBUG launch argument in UI tests; see Q3). Each must work with the key off.

| Phase | Topic | IDs | Risk | Data / migration | How it is tested |
|---|---|---|---|---|---|
| 1 | High bugs + small fixes + test/perf baseline | B-GC-01/GC-V5-1, B-GC-05/GC-V5-4, B-GC-06/GC-V5-5, GC-V7-1 (paperclip → mark), B-GC-04 (close/reframe), snapshot infrastructure, perf baseline harness | Low | Helper bridge gets a shortcut key (additive) | Encoder unit test; menu UI test; Settings focus UI test; Intelligence UI test; first snapshot baselines; baseline numbers for panel open, 100k search, paste dispatch |
| 2 | Shared visual base (System) | SY-V4-3, GC-V5-2 + B-GC-02 + B-GC-03, SY-V4-6, SY-V4-7, SY-V4-8, SY-V4-9, GC-04, GC-V5-6, GC-V4-24, shared Chip component | Medium (touches every surface) | None | Contrast unit tests (brand + every system accent, light/dark); motion token × Reduce Motion tests; source-scan guards (literal colours/durations); full snapshot sweep |
| 3 | Panel — design only | GC-01, GC-V4-3, GC-V5-3, GC-23, GC-05 | Low–medium | GC-V5-3 may add stored image dimensions (migration, Q10); GC-01 may add a title-provenance flag (Q19) | PanelUITests, PanelAppearance, ProductScreens; snapshots per state |
| 4 | Panel — behaviour | GC-V4-2, GC-V4-4, GC-07, GC-08, GC-V4-1 | Medium | GC-07 stores private-mode start/auto-off prefs (additive) | Resolver/probe/parser unit tests; PanelUITests; perf: search budget unchanged at 100k |
| 5 | Peek | GC-16, GC-V4-14 (+ hex parser bug) | Low | None | Palette, contrast, format unit tests; seeded colour/image UI tests |
| 6 | Menu bar | GC-24, GC-25 | Medium (two processes) | Bridge fields (additive) | Pure menu builder + badge mapping tests; in-process status item UI tests; image render tests |
| 7 | Drop on board | GC-V4-23 | Medium (AppKit drop targets) | None | Eligibility unit test; drag UI test → toast + Undo |
| 8 | Library | GC-V4-5, GC-V4-13, GC-V4-6, GC-V4-7 | Low–medium | None (count/sort queries) | Store tests; VisualLibraryUITests; snapshots |
| 9 | Settings + Privacy Center (Mac) | GC-17, GC-19, GC-20, GC-21 (Mac half) | Medium (privacy copy) | GC-20 may add retention windows (decode migration) | SettingsPrivacy, Denylist, RetentionPass, PrivateActivityReceipt UI tests; policy decode tests |
| 10 | Onboarding | GC-35, GC-36 | Low | Welcome flags unchanged unless Q43 asks for versioning | ActivationFunnel + MigrationImport UI tests updated; iOS paging test; snapshots |
| 11 | iPhone app | GC-26, GC-V4-8, GC-V4-9, GC-V4-10, GC-V4-11, GC-27, GC-28, GC-V4-12, GC-21 (iPhone half) | Medium | None expected | iOS UI tests (CaptureFlow, SourceAppFilter, PrivacyCenter…); Dynamic Type up to AX5 snapshots |
| 12 | iPad | GC-33, GC-34 | Medium | None | iPad simulator UI tests; drag representation tests; manual Split View check |
| 13 | iPhone surfaces (extensions) | GC-V4-15, GC-V4-16, GC-V4-17, GC-V4-18, GC-V4-19 | Medium–high (extension memory/time) | Share inbox payload gains fields (versioned) | PreparedCapture round-trip; widget entry tests; device runs with memory measured |
| 14 | Secrets everywhere (flag) | GC-09 | High (privacy) | Possibly sync filter for sensitive clips (Q12) | Privacy tests: no secret in widget/keyboard/MCP/Spotlight/logs; lifetime tests |
| 15 | Paste stack cursor (flag) | GC-10 | Medium | None | Cursor model tests; UI select → stack → paste |
| 16 | One Transform + Describe the change (flag) | GC-11, GC-12 | Medium | Recipe schema may gain a step kind (Q31) | Executor/diff tests; recipe/peek UI tests |
| 17 | Up next (flag) | GC-V6-1 | Medium | New per-paste table (migration + rollback note) | Ranker + migration tests; perf: panel open unchanged |
| 18 | Double-copy merge (flag) | GC-V6-2 | High | `parts` column + sync mapping (migration) | Merge/split + sync round-trip tests |
| 19 | Copy-time HUD (flag) | GC-V6-3 | Medium | Prefs only | Policy tests (never for vetoed copies) |
| 20 | Notch shelf (flag) | GC-V6-4 | High | None | Geometry/EXIF tests; drop UI test; perf check |
| 21 | Jump to context (flag) | GC-V6-5 | Low | None | Window query tests; ⌘J UI test |
| 22 | Agent reads visible (flag) | GC-V6-6 | Medium (cross-process) | None | Content-free payload test; runner tests |
| 23 | Suggested snippets + placeholders (flag) | GC-V6-7 | Medium | Suggestion state table + use log (migration); placeholder grammar compatibility | Parser + state tests; migration of existing snippets |
| 24 | iPhone Up next / Control Center (flag) | GC-V6-8 | Medium | Shared App Group fields | Payload tests; iOS UI tests |
| — | Not implemented | GC-V4-22 (maybe: pending decision), GC-V4-20 (skip) | — | — | — |

Phases 3–13 can start once their blocking questions are answered. Phase 2 must land before 3+, because every later surface uses its tokens. Phase 1 has no blocking question, except Q11 (brand sizes) for GC-V7-1.

## Open questions

These need the owner. The ones marked **★** block Phase 1 or 2.

### Process

- **Q1 — RESOLVED 2026-10-21: option (a).** `docs/design-v4/` is committed with IDs, and commits and PRs cite IDs. This is an owner override of the AGENTS.md rule for this effort only.
  - Original question: catalog IDs in committed text.
  - AGENTS.md says committed text never references internal ticket IDs. The brief, however, asks for `docs/design-v4/PLAN.md` and specs with IDs, and for commits and PRs that cite IDs.
  - The `check-product-truth.sh` gate does not match `GC-…` or `SY-…`, so CI would pass either way.
  - Options:
    - (a) Commit `docs/design-v4/` with IDs, and cite IDs in commits and PRs (an owner override of AGENTS.md for this effort).
    - (b) Keep PLAN.md and specs in `.planning/` (ignored), and describe functionality only in commits and PRs.
- **Q2 — RESOLVED 2026-10-21: add `swift-snapshot-testing`** to test targets only (Phase 1), recorded in DEPENDENCIES.md and both lock files.
  - Original question: the repo has no snapshot library. `ComponentRenderTests` only checks that components render. Options:
  - Add `swift-snapshot-testing` for test targets only. This needs DEPENDENCIES.md and both lock files.
  - Write a small in-house `ImageRenderer` baseline comparer.
- **Q3 — RESOLVED 2026-10-31 for Phase 14: no flag.** Is an off-by-default hidden `UserDefaults` key plus a DEBUG launch argument acceptable for Novel features?

### Design system

- **Q4 — RESOLVED 2026-10-21: ink `#0B2A14`.**
  - Assumption to confirm: this means the whole set drawn on the other boards, that is `#0B2A14` light, `#04210D` dark and `#1F7A3A` for green text.
  - For non-green system accents, the text ink is derived in code to reach ≥4.5:1.
  - Original question: ink on green; the boards disagree:
  - V4_System_Components draws ink `#062D12` and green text `#1C7A37`. `#062D12` on the pressed green `#2A9F47` is 4.42:1, which fails AA.
  - Every other v4 board draws `#0B2A14` (light), `#04210D` (dark) and text `#1F7A3A`. These pass everywhere they are drawn (pressed 4.54).
  - Which set is canonical? Note that system accents also fail as text on white (blue 4.02, orange 2.20), so the text ink should be derived in code from the accent rather than fixed.
- **Q5 — RESOLVED 2026-10-21: the rule, in code.** Hover/pressed steps. Follow the stated rule (−8 % / −16 % lightness) or the drawn hexes (RGB ×0.90 / ×0.80)?
- **Q6 — RESOLVED 2026-10-21: 100 ms fade; `leave` and `press` are tokens.** Reduce Motion. Today Reduce Motion means instant (`nil`); the board says "opacity 100 ms". Which one? Should `leave` (140 ms ease-in) and `press` (.96 / 80 ms) become `GanchoMotion` tokens, given Overview's "no third curve"?
- **Q7 — RESOLVED 2026-10-21: keep the green active chip.** Active chip fill. Does the active board/filter chip lose its green fill (the System board draws a white segmented pill)? Is the indigo "Turn off" next to the green Paste acceptable on one surface?
- **Q8 — RESOLVED 2026-10-21: keep the wash + 3 pt bar.** Selected row lift. The e2 elevation says a selected row lifts 2 px. Keep the shipped wash + 3 pt bar instead?
- **Q9 — RESOLVED 2026-10-21 (default): keep the placeholder; no key on destructive buttons.** Search placeholder and destructive keycap. Placeholder "Search, or type to filter" or the shipped "Search your clipboard"? Should "Delete ⌫" show a key, given the rule that destructive buttons never do?

### Bugs and brand

- **Q10 — RESOLVED (B-GC-04 closed 2026-10-21; size stored at capture 2026-10-22):** B-GC-04 is closed as a misdiagnosis, and masked rows stay masked. Width and height are stored at capture (v27); the format comes from the stored type.
  - Original question: B-GC-04 and GC-V5-3. B-GC-04 is a masked sensitive image, so the bug is wrong as logged. Should it be closed, and should GC-V5-3 apply only to non-sensitive untitled images?
  - Dimensions: store width, height and format at capture (a migration), or compute them lazily from the blob?
  - Format: "Image · 1200 × 800 · PNG", or a title plus "PNG · 1200 × 800"?
- **Q11 — RESOLVED 2026-10-21 (owner accepted the defaults):** onboarding tile 44 pt, widget mark tinted with `.tint`. The optional rows (iOS dark/tinted icon, README logo) are not done.
  - Original question: brand details.
  - Onboarding tile size (the board says 44–56 pt).
  - Widget mark ink: `#1D1D1F` as drawn, or `.tint`?
  - Do the optional rows (iOS dark/tinted icon, README logo)?
  - Should the iOS onboarding hero (`doc.on.clipboard.fill`) become the mark too?
  - Unverified risk: the iOS 1024 icon has an alpha channel.

### Privacy

- **Q12 — RESOLVED 2026-10-31: sensitive clips never sync.** (The Library card no longer claims "never synced"; the sync decision stays open for Phase 14.) They sync today, but the boards promise "never synced". Should sync skip sensitive clips (a privacy and data change), or should the copy change?
- **Q13 — RESOLVED for the Library 2026-10-24: stored mask, kind as title** (iPhone rows in Phase 11 follow the same rule). Secret display. Show the `sk_live_` prefix and a category title, which would need a new stored field? Or keep the stored `●●●● 4Q2v` with no title?
- **Q14 — RESOLVED 2026-10-31: "Reveal for 10 s".** "Hold ⌥" (catalog, Novel) or "Reveal for 10 s" (PanelStates, Panel)? Note that ⌥↩ is Plain paste.
- **Q15 — RESOLVED 2026-10-31: dropped.** It contradicts the shipped rule that a secret's lifetime can be shortened, never extended. Allow it?
- **Q16 — RESOLVED 2026-10-31: widgets keep the masked row, the keyboard excludes secrets.** Widgets: omit secrets or keep masking them? Keyboard: GC-V6-8 draws a masked secret, but the keyboard excludes secrets by design.
- **Q17 — RESOLVED 2026-10-25: no chip; the rule is a card.** "Also concealed" chip. Showing it per app needs per-app protected-copy data, which is aggregate-only by design today.

### Shortcuts

- **Q18 Default shortcuts — Private Mode RESOLVED 2026-10-23: no default, the recorded shortcut or none.** The rest stays open for the phases that own them. The boards draw these, but code has no such defaults:
  - Private mode ⌥⌘P.
  - Paste stack ⌥⌘V, which collides with your panel shortcut ⌥⌘V.
  - Copy text from screen ⇧⌘2 (the code default is ⌃⌥T).
  - ⌃⌘V (paste through the last transform).
  - ⌥⌘1 (recipes).
  - ⌥⌘⌫ and ⌥⌘←/→ (stack). These conflict with Finder and browsers.
  - Options: keep no defaults and always show the user's recorded shortcut (or "Set…"), or adopt defaults.

### Panel, Peek, Menu bar, Motion

- **Q19 — RESOLVED 2026-10-22: upload-state chip, no caption, expiry chip in the header.** GC-01. What does "Synced · Mac + iPhone" mean per clip? There is no per-clip device list, only `needsUpload`. Also: store a "title written on-device" flag, or drop that caption? And where does the expiry label go?
- **Q20 — RESOLVED 2026-10-23: Paste into <App> / Paste / Copy.** GC-V4-2. What does the dock label say with no target app, or without Accessibility (copy only)?
- **Q21 — RESOLVED 2026-10-22: the board's total.** GC-V4-3. Should the count be the scope total or the filtered result count?
- **Q22 — RESOLVED 2026-10-22 for the hero: stripe + decoded chip only (footer hints stay with GC-V4-4); the stripe was removed 2026-10-23 under the no-left-accent-bar rule.** Unassigned panel changes. The 4 pt kind stripe, the URL part chips and the new footer hints have no ID. Implement them under GC-01/GC-V4-4, or skip them?
- **Q23 — RESOLVED 2026-10-22 (default): the pins win.** Panel pins vs "kept" strip. The pins remove the insight strip and "By meaning", but the "kept" strip keeps them. Do the pins win?
- **Q24 — RESOLVED 2026-10-23: dropped; most results wins.** GC-08. What does "Older than 30 days" count? The panel has no date filter, and free archiving is 365 days. Is "best" the highest count or a fixed order?
- **Q25 — RESOLVED 2026-10-23: 15/30/60/120 min or until off, default 1 h; "none read" is a fixed promise.** GC-07. What are the auto-off options and the default? Is "0 read" a real counter or a fixed promise?
- **Q26 — RESOLVED 2026-10-22: an annotation, not shipped.** GC-05. Is "Shown once. It leaves after your first paste…" UI copy or an annotation?
- **Q27 GC-12 keys.**
  - Esc = Discard clashes with esc hiding the panel.
  - ⇧⏎ does not exist today.
- **Q28 — RESOLVED 2026-10-23: the image's own pixel; a swatch click saves a colour clip.** GC-16.
  - Sample the image pixel, or use `NSColorSampler` on the screen?
  - What does clicking a swatch do?
- **Q29 — RESOLVED 2026-10-23: real ratios (4.7 / 3.5, truncated); Paste into <App> stays primary.** GC-V4-14.
  - The board's contrast numbers are wrong: `#008080` is 4.77 / 3.56, not 4.6 / 3.1.
  - The primary "Paste #008080" contradicts GC-V4-2's "Paste into <App>". Which one?
- **Q30 GC-11 Transform.**
  - Does a popover row run immediately, or add a pipeline step?
  - What is the group order?
  - Should ⌃⌘V get a default?
  - Recipes are documented as copy-only. May they paste?
- **Q31 GC-12 saved prompts.** Saving a prompt as a recipe breaks the deterministic recipe contract. Add a new step kind, or a separate list of saved prompts?
- **Q32 OCR behaviour — RESOLVED for iPhone 2026-10-30: read on open, no auto-copy, per-line hold-back** (the Mac keeps ⇧⌘C). OCR runs only on ⇧⌘C and auto-copies; the boards show it read on peek open with "Clipboard unchanged". Also, the per-line hold-back is new. Which behaviour?
- **Q33 — RESOLVED 2026-10-24: the app opens its own menu at the helper's icon.** GC-24. The helper process owns the menu and is content-free. Which approach?
  - The main app shows its own menu at the helper's button.
  - Widen the bridge (this breaks its one-preview rule).
  - Show the mini-panel in the in-app fallback only.
- **Q34 — RESOLVED 2026-10-24: one merged set without syncing; dark glyph on amber; a count.** GC-25.
  - Novel and MenuBarDark draw different badge sets. Which one?
  - Template images can't carry colour, and white on amber or blue fails contrast.
  - Should the stack show "3/5" or a count?
- **Q35 GC-04 / GC-23 — RESOLVED: hex surfaces only in the opaque branch (2026-10-21); 7 % / 10 % is the wash's visible peak and the test is inverted (2026-10-22).**
  - Do the fixed dark hex surfaces replace Liquid Glass in dark, or apply only to the opaque branch?
  - Is the 7 % wash the layer opacity or the peak?
  - Light at 10 % above dark at 7 % reverses an existing test. Change the test?
- **Q36 — RESOLVED 2026-10-24: no refusals; in-app drags only; already-member toast.** GC-V4-23.
  - The "secret" and "Free limit" refusals have no basis in code. Drop them?
  - The panel chips show no counts, so the count tick only works in the Library.

### Library, Settings, Onboarding

- **Q37 — RESOLVED 2026-10-24: panel kind set, clips-only search, ClipCard list that persists, no Select, no Copy on protected cards.** Library.
  - Text chip vs Secrets chip.
  - The `Select` button (also on iPad) has no ID. In scope?
  - Does search also match board names and snippets?
  - The List layout is not drawn.
  - Should the Grid/List choice persist?
  - Where do pinned cards go?
  - "⌘C copies" assumes a focus model the Library doesn't have.
  - Copy on a masked card does nothing today.
- **Q38 — RESOLVED 2026-10-24: three ceilings, escalating tail.** Pro meter. Should the caption escalate as limits approach? It ignores the pins limit (15).
- **Q39 — RESOLVED 2026-10-25: timeline over the pickers + Forget recent clips.** GC-20 retention design. Settings draws a timeline over the pickers; Novel2 draws a dial plus "Forget recent clips" (the catalog title matches Novel2). Which one ships?
- **Q40 — RESOLVED 2026-10-25: a local check in the row; undrawn sections stay below.** GC-21 Verify.
  - What does "Verify" check?
  - Drop the six existing Privacy Center sections the board doesn't draw?
  - The catalog's Verify contents differ from the iPhone board's. Which one?
- **Q41 — RESOLVED 2026-10-25: protected skips over 7 days; truthful screen-share copy.** GC-17 tiles. The screen-share footnote names apps the detector doesn't detect. Does tile 3 count protected skips only, or all skips?
- **Q42 — RESOLVED 2026-10-21: dark ink as drawn.** Privacy hero. Dark ink as drawn, or a darker gradient as the PASS note says?
- **Q43 GC-35 onboarding — RESOLVED 2026-10-25: Skip for now advances; inline recorder; no versioned flag; the shortcut only on the button.**
  - Does "Skip for now" go to the next step or close onboarding?
  - "Change…": an inline recorder, or open Settings?
  - Re-show the new flow to returning users (a versioned flag)?
  - The shortcut is shown twice on step 4.
- **Q44 GC-36 iPhone onboarding — RESOLVED 2026-10-25: Next on page 1; a label above the Paste control; iPad included.**
  - How does the user reach page 2?
  - "Try Paste now" can't go inside the system Paste control.
  - Does iPad get page 2?

### iPhone, iPad, extensions

- **Q45 GC-26 — RESOLVED 2026-10-25: keep ⓘ; empty keeps the row; back to Saved.** Is the info button kept? What do undrawn kinds show? What happens after the 4 s?
- **Q46 GC-V4-8 — RESOLVED 2026-10-25: stored name; counts only when complete; no cloud beside a device.** Show the full device name or "Mac"? Do header counts need a store query? Drop the universal-clipboard glyph?
- **Q47 GC-V4-10 — RESOLVED 2026-10-25: under the rail; Clear keeps the board.** Do the filter chips replace the rail or sit under it? Does Clear reset the board too?
- **Q48 GC-V4-11 — RESOLVED 2026-10-25: automatic; synced clips backfilled on device (Pro).** iOS has no embedding backfill for clips synced from the Mac, so "Related by meaning" will be mostly empty. Should it auto-run?
- **Q49 GC-27 — RESOLVED 2026-10-25: Markdown link added; × on the suggestion; Snippet disabled.** Is "Markdown link" a new action? Is Snippet hidden or disabled when it doesn't apply?
- **Q50 GC-28 / GC-V4-12 — RESOLVED 2026-10-25: Synced / Waiting; static capture rows with How.**
  - Where does the per-board sync subtitle come from?
  - The keyboard and share-sheet state can't be detected. Show static rows?
- **Q51 GC-33 iPad sidebar — RESOLVED 2026-10-25: letter tiles; the Mac's five type groups; a wash per section; Paste docked, in the toolbar without the sidebar; Select out.**
  - iOS can't get other apps' icons.
  - 6 drawn types vs 17 kinds.
  - Where does Paste go in compact layouts?
  - Is `Select` in scope?
- **Q52 GC-34 — RESOLVED 2026-10-25/26: hero and rows drag; no hint (no filler copy).** Do rows drag too? Is the drag hint permanent or a one-time tip?
- **Q53 GC-V4-15 share sheet — RESOLVED 2026-10-30: the sharing app's title; a sealed board snapshot; the sheet by default.**
  - Where does the title come from inside the extension?
  - How does the extension read the board list?
  - What is the default of "Save instantly"?
- **Q54 GC-V4-16 — RESOLVED 2026-10-30: All + Favorites + boards that fit; the iPhone's masked row.** Which boards get chips? Masked row text?
- **Q55 GC-V4-17 — RESOLVED 2026-10-30: not offered for a secret.** "Copy again" for a secret from the lock screen: hide it, or require unlock?
- **Q56 GC-V4-18 — RESOLVED 2026-10-30: read fresh on open, nothing stored, no footer.** Pro enrichment already stores OCR text, so the footer "nothing is stored" is untrue. Change the footer or the behaviour?
- **Q57 GC-V4-19 — RESOLVED 2026-10-30: every row inserted into the current field.** Is one row marked inserted, or every inserted row?

### Novel features

- **Q58 GC-V6-1 — RESOLVED 2026-11-01: Intelligence, off by default; the table only while on, erased when off; heuristic ranker with a two-paste threshold; no footer.** Where does the toggle live (Intelligence is a window opened from Capture)? Approve the new per-paste table?
- **Q59 GC-V6-2 — RESOLVED 2026-11-01: double ⌘C on the same selection, off by default, parts synced encrypted, HUD + sound with opt-out.**
  - What exactly triggers a merge?
  - Is it on or off by default?
  - Polling at 250 ms / 1.5 s makes the 600 ms window coarse.
- **Q60 GC-V6-3.** "Forget in 60 s" is below the 5-minute minimum for sensitive clips. "Add to Colors" needs a board that doesn't exist.
- **Q61 GC-10.** Capture ⌘V globally? The hotkey conflicts (Q18).
- **Q62 GC-V6-4.**
  - Mac only?
  - Accept files dragged from Finder?
  - A thin drop window at the top edge, rather than a global drag monitor?
- **Q63 — RESOLVED 2026-10-23: ⇧⌘S saves the filter, no #tag, Meaning exclusive.** GC-V4-1.
  - ⌘S is already "promote to snippet".
  - Keep `#tag`? There is no tag feature.
  - Is Meaning exclusive or additive?
- **Q64 GC-V6-5.** Which timestamp anchors the ±2 min window?
- **Q65 GC-V6-6.**
  - The tool is named `search_clips`, not `search`.
  - The log keeps only the grant id, so it can't show the scope at access time.
- **Q66 GC-V6-7.**
  - "Pasted 5× in 2 weeks" needs a use-event log.
  - The existing `{clipboard}` / `{date}` placeholders would change meaning.
- **Q67 GC-V6-8.** iOS has no capture state and no paste stack. And the secrets-in-keyboard question (Q16).

## Gaps found while planning (to resolve in the phase noted)

- **Found in Phase 1, resolved there:** UI test bundles cannot link swift-snapshot-testing, because it imports Swift Testing. Comparison moved to the standalone `Tests/DesignSnapshots` package.
- **Found in Phase 1, resolved there:** element screenshots copy a screen region, so a window covering the app ended up in the image. Captures are now rendered by the app itself with `cacheDisplay`; nothing from the screen is ever captured.
- **Found in Phase 1, not caused by it:** `PanelUITests.testMenuBarAgentStaysResidentOnPlainLaunch` fails on this Mac with a helper Launch Constraint Violation, and `testMenuBarStatusItemOpensSettingsWindow` fails too. Both fail identically on `main` (control run), so this is environmental helper signing.
- **Found in Phase 2, resolved there:** borderless menus and button-style toggles paint their label in the tint and ignore `foregroundStyle`, so "Transform", "Smart paste" and "By meaning" stayed at 2.4:1 after the sweep. `ganchoInkTint()` fixes them; `DesignTokenGuardTests` now gates green text, literal shadows and literal curves.
- **Found in Phase 2, not caused by it:** the in-app render omits material vibrancy, so `.tertiary` text on a glass surface (the onboarding "Copy something…" line) captures as black. The app draws it correctly; the onboarding redesign (GC-35) replaces that line.
- **Found in Phase 3, resolved there:** the warning amber (2.2:1 on white) was still used as text and status glyphs (row expiry countdown, Privacy Center, MCP badges, sync and capture icons). `warningInk` fixes them and the token guard now covers warning.
- **Found in Phase 3, resolved there:** two migration tests wrote the current row shape into a store stopped at an older schema, so any new `clip` column broke them. They now seed with that schema's columns (`LegacySchemaSeed`).
- **Found in Phase 3, not caused by it:** several UI tests still attach `XCUIElement.screenshot()` evidence, which copies a screen region (Gallery, Ambient, SourceAppFilter, SettingsPrivacy, AppQuality and others). Design captures already render in-app; moving these attachments to the in-app render is its own change.
- **Found in Phase 2, kept on purpose:** Settings, Privacy Center and MCP Access apply `GanchoButtonStyle` at the window root, so their buttons keep the native focus ring. Turning it off window-wide would also remove the ring from toggles and text fields.

- **Resolved in Phase 5:** 8-digit hex parser mismatch, `DevActions.swift:551`. One parser, `ColorValue`, now feeds the swatch, the colour hero and Convert color; `#RRGGBBAA` is CSS order everywhere.
- **Found in Phase 5, resolved there:** a non-finite `hsl()` hue (`nan`, `inf`) would trap converting to `Int`, and the eyedropper decoded the full image. The parser rejects non-finite hues and the eyedropper samples a decode capped at 8,192 px per side.
- **Found in Phase 6, resolved there:** the menu-bar bridge stored the last-copied preview (masked only for sensitive clips) in a plain preferences plist, outside the SQLCipher store. The preview is gone and launch removes the old value.
- **Found in Phase 6 review, resolved there:** a share that started during a manual pause left previews visible (the rule keyed off the monitor's status); the paste-stack strip, ⌘Y and the combined-text / AI-context sheets ignored hidden previews (the strip also ignored secret masking, before this phase).
- **Found in Phase 7, resolved there:** the panel was movable by its whole background, so dragging a row moved the panel with the pointer: a drop could never reach a board chip, and drag-out likely suffered too. The panel now moves from its top strip; a UI test asserts a row drag leaves it in place.
- **Found in Phase 7, resolved there:** UI-test sample boards took their automatic colour from a random id, so any snapshot showing them changed colour between runs; the seed now pins palette colours. The drop ring also sat outside the 1.04 scale and on a continuous capsule, which left the chip's fill peeking past it.
- **Found in Phase 8, resolved there:** the Library header counted the loaded window (`clips.count`, at most 100), not the scope; it now reads the store's total. Board scopes paged by membership time while every other scope used capture time, so date groups could not hold; every scope now pages pinned first, then by capture time.
- **Found in Phase 8, kept on purpose:** the panel's ⌘G gallery reuses the Library card, so it gains the new card too; the List layout's rows mask a protected clip completely (the panel's own rule), while a grid card shows its stored mask.
- **Found in Phase 8, not caused by it:** the ambient-image panel snapshots no longer matched their baselines; `main` renders the same bytes as the branch, so their baselines were re-recorded. Library search also matches the text inside protected clips (a hit shows only the mask), as the panel's search already does.
- **Found in Phase 9, resolved there:** the screen-share footnote named Meet, FaceTime and QuickTime, which the detector does not detect; the Privacy settings now name only Zoom, Teams and Screen Sharing.
- **Found in Phase 11, resolved there:** the row's "Expires soon" label had no catalog entry in either app, so it read in English in Spanish; both catalogs have it now. The iPhone also had no Spanish for most kind names a row can title.
- **Found in Phase 11, resolved there (house rule):** the iPhoneFlows board draws the link hero with a 4 pt bar on its leading edge; that is a left accent bar, so the hero uses a light tint and a full outline instead.
- **Found in Phase 11, resolved there:** the iPhone Privacy Center would have said "Encrypted at rest" while the store had fallen back to memory; the row says "Not saved to disk" then. UI tests run on a plaintext throwaway store by design, so Verify there reports it isn't encrypted.
- **Found in Phase 11, kept on purpose:** iOS reports a generic device name ("iPhone") without the user-assigned-name entitlement, so a clip copied on another iPhone reads as this one; Mac names are the user's own and always show.
- **Found in Phase 12, not caused by it:** in the iPad history column (about 400 pt) a row's title, preview and source line truncate to a few characters, because the trailing meta column takes a fixed share; `main` truncates the same way. Recorded for a row-layout pass, not changed here.
- **Found in Phase 12, deferred (owner, 2026-10-25):** multi-select on iPad (the board's `Select`) has no design or code; it is its own item, not part of GC-33.
- **Found in Phase 12, not caused by it:** the iPad history marks its selected row with the system's full accent fill and white text, where the board draws a 14 % wash; the row's grey source line reads poorly on it. The List's native selection (which gives ↑↓ for free) is kept; restyling it is for the row-layout pass above.
- **Found in Phase 12, testing note:** the iPad simulator drops the first synthesized key event after launch (the same on `main`), so the ⌘F test sends the shortcut once more when focus has not arrived. iOS exposes keyboard focus to UI tests only through key-value coding.
- **Found in Phase 12, resolved there:** a link shared or dragged left Gancho as plain text only; it now goes as `public.url` first (a Notes link, a Mail anchor), its text after.
- **Found in Phase 13, kept on purpose (owner, 2026-10-30, after a device check):** "ready to paste" is ended at creation so it dismisses itself after three minutes even while Gancho is in the background, and iOS never shows an ended activity in the Dynamic Island. Copy again and Open therefore live on the lock-screen banner only; the board's expanded-island actions were dropped.
- **Found in Phase 13, hardened there (privacy review):** the large widget's protected row shows the stored mask (up to four real characters, as the app's rows do, by the owner's choice); the mask, its countdown and the board chips are marked privacy-sensitive so the system redacts them where it must, and Copy again on the Live Activity asks to unlock first.
- **Found in Phase 13, resolved there (privacy review):** the share sheet could have prefilled a secret as the title (some apps hand the shared text over as the item's content text) and previewed a plain-text key unmasked. The suggested title is now never the shared text, a secret the extension's detector sees previews masked and takes no title, and a protected clip takes no title or pin when the app applies the choices.
- **Found in Phase 13, resolved there:** the app published the board list only from one refresh path, so boards created by other paths missed the share sheet; it now publishes whenever its boards change.
- **Found in Phase 13, testing note:** XCUITest drives the share extension through Safari (its sheet shows up in Safari's element tree); a share sheet opened from Gancho's own Share button is not visible to XCUITest.
- **Found in Phase 12, kept on purpose:** on a link's card, a long press on the URL line selects text (part of a URL can still be copied); the rest of the card lifts the link. The drag test grabs the card by its host.
- **Found in Phase 12, not changed (privacy review note):** a link that carries credentials or a token in its query lifts and shares like any link, as its plain text already did; flagging such URLs belongs at capture time, not in drag.
- **Found in Phase 12, testing note:** XCUITest cannot drop into another app, so the drag test drops on Gancho's own search field (a system text field accepts text drops). A secret delivers nothing there; whether it lifts at all is covered by the drag rule's unit tests, since safe delivery also refuses it.
- **Found in Phase 12, resolved there:** a source app copied on the Mac and on the iPad (Safari's two bundle ids) is two rows; its letter tile takes its colour from the name, so both rows match.
- **Found in Phase 10, testing note:** recorded global shortcuts live in the standard defaults, outside the per-test defaults suite, so a capture showed this Mac's ⌥⌘V. The onboarding snapshots pin them through the argument domain (`-KeyboardShortcuts_toggle-panel`).
- **Found in Phase 10, not caused by it:** the Mac `-open-welcome-on-launch` launch flag is read outside `#if DEBUG`, unlike the other UI-test hooks (it only opens the welcome window). The iOS flag added in this phase is DEBUG-only.
- **Found in Phase 10, resolved there (owner, 2026-10-25):** step 4's status line claimed a clip's title "was written on-device" whenever the newest clip had a title, though nothing records whether a title came from auto-titling or the user. It now says only "Capturing".
- **Found in Phase 9, testing note:** the panel and Library snapshots depend on the displays attached (their windows fit the visible frame); with only the built-in display they render shorter than the baselines recorded with an external display, on `main` as well. Settings and Privacy Center snapshots have fixed sizes and are unaffected.
- **Found in Phase 8, testing note:** a container's accessibility identifier replaces the identifiers of the AppKit-backed controls inside it (the Library root renamed its search field `library`); the root now contains its children instead.
- **Found in Phase 7, testing note:** with the old movable panel a synthesized row drag moved the window and always dropped at its own start point, which first looked like drop targets inside the rail's scroll view not working; once the panel stopped moving, drops on each chip work directly.
- **Found in Phase 6 CI, resolved there:** a menu the app pops up for the helper isn't reliably in the accessibility tree (seen as 1 in 2 runs even when anchored to a view), so VoiceOver and keyboard presses on the icon open the helper's own native command menu; pointer clicks open the app's mini-panel.
- **Found in Phase 6, kept on purpose:** the badge sits beside the hook's curl, so a badged status item is a few points wider; a masked recent row reads "<kind> · masked" because the secret's type is not stored on the clip; a menu opened for the helper isn't in the app's accessibility tree, so its rows are tested through the in-process menu, which is the same `MenuBarMenu`.
- **Found in Phase 6, not caused by it:** `PanelUITests.testMenuBarStatusItemOpensSettingsWindow` fails on this Mac on `main` too (control run); the ambient-image snapshots drifted in colour on `main` as well, so their baselines were re-recorded.
- **Found in Phase 5, kept on purpose:** the Dominant chip sits under the image, not in the OCR text header, so it shows for images with no text. The spec's `peek-color-hero` id is not exposed: the colour hero is the peek hero's only child, and SwiftUI folds it into `peek-hero`; tests find its rows there.
- "Expires soon" label is missing from the string catalogs (LocalizationTests coverage of package sources) → Phase 1 or 11.
- **Resolved in Phase 2:** `GanchoTokens`, `Components` and `GanchoColors` cited design files that do not exist (`docs/design/tokens/colors.css`, a snippet-editor kit, DESIGN-SYSTEM.md); the comments now point at "Design tokens" in docs/ARCHITECTURE.md or name no file.
- **Resolved in Phase 4:** no ⌫ / ⌘. key bindings, although Archive marks them shipped. ⌫ now deletes the clip from the peek's actions, with Undo; the search field keeps ⌫ for its text. ⌘. stays unbound: it is the system Cancel and closes the panel like esc, so More actions stays on ↓ and Enter.
- **Found in Phase 4, kept on purpose:** `app:` and `type:` chips repeat the filter rail's active chip, as the board draws both; a `board:` token selects the board rail instead of adding a chip, because the rail already shows the scope. Chips are removed with their ×, as the spec's checks list; ⌫ in an empty field is not drawn and is not bound.
- **Found in Phase 4, resolved there:** the capture banner's accessibility id landed on its first text and hid the rest; the banner now keeps its children (`.contain`), and its icon is hidden from VoiceOver.
- Board drawing mismatches where code wins: Archive header 27 vs 26 shipped, iPhone "New" vs "New board…", denylist sample apps that are built-ins, and others. Recorded in the specs; no change.

## Review skills per phase

The skills available in this session that apply:

| Skill / agent | Used in |
|---|---|
| `swift-preflight` (before every PR) | all phases |
| `code-review-pr-fix <PR> high` (required) | all phases |
| `privacy-boundary-reviewer` agent (repo) | 1, 3, 4, 6, 9, 11, 13, 14, 17–24 |
| `security-review` | 9, 13, 14, 18, 22 |
| `swiftui-expert-skill` (repo `.agents`) | 2–16, 19–24 |
| `ios-accessibility` (repo `.agents`) | 2, 10–13, 24 |
| `swift-testing-pro` (repo `.agents`) | all phases (unit tests) |
| `swift-concurrency-pro` (repo `.agents`) | 4, 6, 13, 17, 18, 22 |
| `apple-on-device-ai` (repo `.agents`) | 12, 16, 17 |
| `engineering:testing-strategy` | 1 (snapshot and perf harness) |
| `engineering:documentation` | every phase that changes docs |
| `simplify` | after each phase's last commit |

## Documentation and website per phase

| Doc / page | What changes | Phase |
|---|---|---|
| CHANGELOG.md (Unreleased) | every user-visible change | all |
| docs/ARCHITECTURE.md | tokens, chip component, motion policy (2); menu-bar bridge fields (1, 6); flag pattern (14+) | 1, 2, 6, 14 |
| docs/ACCESSIBILITY.md | focus ring, contrast, Reduce Motion, 44 pt targets | 1, 2, 11 |
| docs/SECURITY-MODEL.md, docs/PRODUCT-TRUTH.md | secret display, sync of sensitive clips, agent reads | 9, 14, 22 |
| docs/SCREEN-OCR.md | per-line hold-back, iPhone text in image | 5, 13 |
| docs/TEXT-RECIPES.md | Transform pipeline, saved prompts | 16 |
| docs/SNIPPETS.md | placeholders, suggestions | 23 |
| docs/INTEGRATIONS.md | agent reads visibility | 22 |
| docs/LOCALIZATION.md | GanchoShare string catalog | 13 |
| README.md + site/ (screens, copy, colours) | new panel / peek / iPhone screenshots via ProductScreensUITests; token colours in site/styles.css if the green ink changes | 2, 3, 5, 11 |

## Performance method

Measured before and after each phase that touches these paths, with the same method:

- **Panel open:** an XCTest UI performance test with `XCTOSSignpostMetric` on the existing `panel-to-first-frame` signpost (Signposts.swift, `-measure-panel`).
- **Search:** `make bench`. It covers FTS over 100k clips: cold 150 ms, warm p95 50 ms.
- **Paste:** the `paste-dispatch` signpost.

The Phase 1 harness records the baseline. Baseline on 2026-10-21, after Phase 1 (Phase 1 does not touch these paths), Retina MacBook, Debug build, 10 iterations each:

- `panel-to-first-frame`: average 93 ms, relative standard deviation 17.6 %.
- `paste-dispatch`: average 95 ms, relative standard deviation 4.0 %. This includes the fixed 80 ms focus-return wait. Every later summary reports before and after numbers; no regression is accepted.

## Process per phase

1. Read this plan and the phase's specs.
2. For each ID: re-read its spec section and comment thread, implement exactly what is drawn (UI strings verbatim), and add or adjust unit and UI tests plus snapshots.
3. Build and run, then compare a capture with the board.
4. Update the row: files, test, capture, commit.
5. Remove the code, strings and assets the change leaves unused, checked with references, the compiler and the linter.
6. Open the PR, then run `/code-review-pr-fix <PR> high`, re-run all tests, and stop for owner review.
