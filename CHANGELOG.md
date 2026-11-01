# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- One Transform list behind ⌘T in the peek replaces the Transform and Smart
  paste menus and More actions: type to filter the clip's own actions, text
  transforms, recipes and on-device Smart paste. Picking a transform opens a
  step pipeline with the text before and what will paste after; add steps,
  drag to reorder, then Paste result (⇧⏎) or Copy result.
- A paste-stack run keeps what already went in: the queue checks pasted
  clips, marks the next one and the footer reads "3 of 5". Skip, Back and
  Reset move through the run, with optional shortcuts in Settings. A run
  ends after two minutes without a stack action or when you copy something
  new; clips still waiting stay in the stack. While the panel is closed, a
  small strip under the menu bar shows the run and the next clip, with
  Skip, Back, Reset and End run, without taking focus from the app you are
  pasting into.
- A secret's peek on the Mac shows its masked value, how long it has left
  with a lifetime bar, "Reveal for 10 s" and "Delete now". A reveal masks
  itself again after 10 seconds or when the panel hides, and is off while
  the screen is shared or Private Mode is on.
- The peek header shows where a clip came from (app, age, boards), when it
  expires, and whether it has reached iCloud ("Synced" or "Waiting to sync").
- The active board chip shows how many clips it holds ("All clips · 128");
  every board shows its count in its tooltip.
- Image rows say what the image is: "Image · 1200 × 800 · PNG", or the format
  and size under a title.
- An empty panel offers to import from Maccy or a CSV and shows the three keys
  that make the whole loop, until your first paste.
- The paste button names where it pastes ("Paste into Mail"). It says "Copy"
  when Accessibility is off and the paste can only copy.
- The footer chip names the capture state and its cause in its own colour:
  "Capturing · Mail in front", "Paused · screen sharing", "Private mode · 58
  min left", "Access denied".
- Private Mode turns itself off after 15 min, 30 min, 1 h (the default) or
  2 h, or stays on until you turn it off (Settings › Privacy). Its banner says
  since when, how many copies it skipped without reading them, and when it
  ends, with a Turn off button.
- The search field has Exact, Fuzzy, Regex and Meaning modes. Typing
  `app:`, `type:`, `board:`, `device:` or `before:` adds a filter: Tab
  completes it, and its chip's × removes it. ⇧⌘S saves the field as a
  filter.
- When a search finds nothing, the panel shows how many clips the other modes
  (and all boards) would find, previews the best one, and ↓ switches to it.
- A color clip's peek shows the color with its HEX, RGB, HSL and SwiftUI
  values, each with a copy button, and how it reads as text on white and on a
  dark surface (contrast ratio and AA grade). Convert (⇧⏎) sits in its dock.
- An image's peek lists up to three dominant colors; clicking one saves it as
  a color clip. Pick color (I) turns the pointer into an eyedropper that saves
  the exact pixel you click. A Regions / Image only switch hides the text
  regions.
- The menu-bar menu is a mini-panel: the capture state with the clip count
  and the app in front, your five latest clips with their tiles (⌘1–⌘5 paste
  them, ⌥ pastes plain), the paste stack with what comes next, and the
  commands.
- The menu-bar hook carries a badge for the state: paused, Private Mode,
  access denied, next copy ignored, or how many clips wait in the paste stack.
  ⌥-click pauses or resumes capture; ⌥⇧-click ignores the next copy.
- While your screen is shared, the panel shows only each clip's kind and names
  the app that is sharing; Show anyway reveals previews for that share. The
  paste-stack strip, ⌘Y and the combined-text sheets hide content too, in
  Private Mode as well.
- Drag a clip onto a board — a chip on the panel's board rail or a board in
  the Library sidebar — to file it. The board lifts and rings while the clip
  hovers, and a clip already there says so.
- The Library has a toolbar: search your clips (⌘F) within the board or filter
  you are on, switch between Grid and List (remembered), and add a New board.
  The header gains the panel's kind chips and a Newest / Oldest sort.
- Library cards say what a clip is and where it lives: a link's host and path,
  a colour's swatch, an image's format and size, the boards it is on, and its
  kind, app and age. Hovering shows Copy, Pin and Add to board. A secret shows
  only its stored mask and its countdown, and offers no Copy.
- Saved filters show how many clips they hold and can be added from the
  sidebar; snippets show their keyword.
- Settings › Privacy opens with four tiles: whether Gancho is capturing (with
  the clip count and size on this Mac), whether history is encrypted, how many
  protected copies it skipped this week, and the sync state. A Privacy Center
  card sits under every Settings pane.
- Settings › Retention shows every lifetime on one timeline that moves with the
  pickers, and "Forget recent clips" removes what you copied in the last 5, 15
  or 60 minutes after showing how many; Undo brings them back. Pins, boards and
  snippets stay.
- The Privacy Center opens with "Verify, don’t trust": encryption with a Verify
  button that checks the database on this Mac, iCloud sync, the last content
  read, local AI agent access and the network boundary.
- On iPhone and iPad the welcome has a second page, "Sensed, not read": the row
  you will see at the top of your history, why iOS shows no paste banner, how
  to add the keyboard and the widget, and a Paste button to try it. A paste
  there closes the welcome and opens the clip it saved.
- On iPhone, a search lists clips related by meaning under its results, found
  on the device. With semantic search on, Pro also embeds clips synced from
  your other devices in the background, so they can be found by meaning too.
- The iPhone and iPad clip detail adds a Markdown link action for links, and
  boards list your snippets by keyword.
- The iPhone Privacy Center opens with "Verify, don’t trust": encryption with
  a Verify button that checks the database on the device, the iCloud sync
  state, and how many secrets are masked now.
- On iPhone, an active type or app filter shows as a chip under the boards;
  tap it to remove it, or Clear filters to remove both.
- The iPad sidebar says what each board, type and app holds: boards with
  their colour and count and how many Free boards are used, the Mac's five
  type groups (Links, Code, Colors, Images, Secrets) with theirs, and apps as
  a letter tile. The active row in each section is highlighted, and "New
  board…" sits under the boards.
- On iPad the clipboard card sits under the sidebar with its own Paste
  button, so the history starts with your clips; with the sidebar hidden,
  Paste and the card move back to the history.
- A large Gancho widget lists six recent clips, with board chips (All,
  Favorites and your first boards) that scope them, when Gancho last synced,
  and Save clipboard and Open Gancho. Passwords and keys show their kind, the
  stored mask and the time they have left.
- The "ready to paste" banner on the lock screen offers Copy again and Open
  in Gancho (never Copy again for a password or key), and ends once something
  else was copied.
- The Gancho keyboard marks each clip you insert with a green tint and an
  "inserted" pill, so a long message shows what already went in. The marks
  clear once you leave that text field; an image, which the keyboard copies
  instead of typing, is not marked.
- Opening an image on iPhone and iPad reads its text on the device: each line
  is numbered over the image and listed under it, with its own copy button.
  A line holding a password or key stays masked and out of "Copy all" until
  you reveal it. "Save text as clip" and Translate sit under the lines, and
  nothing is copied or saved until you tap.
- Sharing to Gancho on iPhone and iPad shows what will be saved: the item,
  its title (the page title the app hands over, editable), boards to add it
  to (or a new one) and a Pin switch. "Save instantly from the share sheet" in
  Settings brings back the one-tap save.
- On iPad, drag a clip from the history or its detail into the app beside
  Gancho: a link drops as a link, an image as a PNG, text as text. Passwords,
  keys and cards never lift.
- Sharing a link hands it over as a link (with its text after), so Messages
  and Notes treat it as one.
- The iPad history counts its date groups, shows its total under the title
  and keeps search in its toolbar. With a hardware keyboard attached, a legend
  lists ⌘F, ⌘⏎, ⌘1–9 and ↑↓, and Copy shows ⌘⏎.

### Changed

- Passwords, keys and other secrets no longer sync through iCloud: each one
  stays on the device that copied it until it expires. Secrets uploaded by
  earlier versions are deleted from iCloud; the copies on this device stay.
- The iPhone's clipboard row is a card: it names what is on the clipboard
  (a link, search text, a number) without reading it, points at the Paste
  button, and after a save offers to open the clip for a few seconds.
- iPhone rows name the device a clip came from when it wasn't this one; the
  active board chip and the section headers show how many clips they hold.
- iPhone rows for passwords, keys and cards show the kind, the stored mask
  (`●●●● 4Q2v`), where and when it was copied, and how long it has left.
  Widgets and the lock screen still show only dots.
- The iPhone's search answer says it was answered on the device and that its
  sources copy on tap.
- The iPhone and iPad clip detail leads with where a clip came from, its title
  (edited in place), a link as its own hero card, and one full-width Copy;
  Share, Pin, Board and Snippet sit in one row, smart actions and boards as
  chips.
- The iPhone boards sheet shows how many of the Free boards are used, whether
  each board is synced, waiting or on this iPhone only.
- iPhone Settings show at a glance your Pro usage, which Intelligence features
  are on, and what the Privacy Center counts, and list every way to capture on
  iPhone, with steps for the keyboard and the widget.

- The Mac welcome has four steps: the privacy promise (where clips live, when
  secrets expire, what is never read), the Accessibility permission with what
  works with and without it, the panel, paste-stack and Private Mode shortcuts
  as you recorded them (each changeable in place), and a live first copy that
  ends in the real panel. Page dots show where you are.

- The welcome window, the Recent clips widget and the Wrapped card show the
  Gancho mark instead of a generic paperclip symbol.
- Green text, links and status labels are darker in light mode and lighter in
  dark mode so they stay readable on every surface; text on green buttons is
  dark instead of white.
- Buttons share one look per role, with consistent hover, pressed, disabled and
  keyboard-focus states; destructive actions read in red.
- The opaque panel uses true dark surfaces in dark mode, with a subtle top edge
  instead of a shadow.
- Filter, type and board chips use a larger 11 pt label.
- With Reduce Motion on, previews and banners fade in 100 ms instead of sliding
  or scaling.
- The peek's title sits on its own row under the provenance header; the
  separate details strip and the "Content" label are gone, and links with
  escaped characters show a decoded reading.
- The optional ambient colour now sits only behind the peek, at a fainter
  10 % (light) / 7 % (dark), and never appears for masked clips or in Private
  Mode.
- Meaning is a search mode of its own: it lists only the clips related by
  meaning, instead of adding them under the other results. The "By meaning"
  button is gone.
- Adding clips to a board names the board in the confirmation ("Added to
  Work") and offers Undo; while such a toast shows, ⌘Z in the panel or the
  Library undoes it, as it does for Deleted.
- The panel moves from its top strip (the search bar and toolbar background)
  instead of from anywhere, so dragging a row drags the clip.
- Library clips are grouped Pinned first, then by the day they were copied,
  each group with its count; the panel's ⌘G gallery uses the new card.
- The Library's Pro card is a meter of every Free limit (boards, pins and
  snippets) that turns amber when one is almost full and red when one is
  reached.
- Settings › Capture states the concealed and transient copy rule as a card
  with nothing to turn off; Intelligence is a single row.
- Privacy settings are grouped by question (Capture control, Searches and
  Spotlight, Diagnostics) with shorter notes under each control.
- With an Undo toast showing, ⌘Z in a text field you have typed in undoes your
  typing; the toast keeps its Undo button.
- The menu-bar icon keeps the hook in every state instead of swapping to a
  pause or warning symbol.
- The selected row shows as a tinted, outlined card instead of a green bar
  on its left edge, and the preview card no longer has a colored stripe on
  its left.
- Private Mode is indigo instead of amber. The list sits under "Before
  private mode", and the peek says previews are hidden and pasting still
  works.

### Removed

- Support for Intel Macs and macOS 15. Gancho now needs an Apple Silicon Mac
  with macOS 26 or later. Macs that can't run it stay on 0.10.2 and aren't
  offered the update.

### Fixed

- Warning text and status icons (expiry countdowns, denied requests, sync and
  capture status) are readable on light surfaces instead of pale amber or
  green.
- The menu-bar menu shows the panel shortcut you recorded (or none) instead
  of always showing ⇧⌘V.
- Choosing a Settings section moves keyboard focus with it, so the first row
  no longer keeps its focus ring while another row is selected.
- All five stages of the Intelligence pipeline fit inside the window, and the
  Smart paste row shows its icon again.
- Panel scope counts update when you delete a clip, undo the delete, or add a
  clip to a board or remove it, instead of waiting for the panel to reopen.
- The screen-share note in Privacy settings names the apps Gancho detects
  (Zoom, Teams and Screen Sharing) instead of apps it does not.
- The Library header counts every clip in the scope, not just the first 100
  loaded.
- A board's list, its chip count and its Library count agree: archived and
  expired clips no longer appear in the board while being left out of its
  count.
- Type, status, detected-secret and snippet-field pills keep their text at
  4.5:1 contrast on their own tinted background.
- An 8-digit hex color (`#RRGGBBAA`) converts with the same channels the
  swatch draws; Convert color read the first two digits as alpha.
- An `hsl()` color whose hue is `nan` or `inf` no longer crashes Convert
  color.
- Dragging a row in the panel no longer drags the whole panel along with it.
- The menu-bar helper no longer keeps a preview of your last copy in a
  preferences file outside the encrypted store; the old value is removed at
  launch.
- Convert color reads `rgb()` channels written as percentages
  (`rgb(100%, 50%, 0%)`) or decimals, and alphas written as percentages,
  instead of misreading or rejecting them.
- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.10.2 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

## [0.10.2] - 2026-10-16

### Fixed

- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.10.1 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

- Re-seal a stored image or file when copying the same bytes again finds a
  copy left under an encryption key from an earlier store reset, so the new
  clip can be pasted and synced. Privacy Center now counts clips whose content
  was lost that way and offers to remove them.

- Restore synced clips whose stored content was sealed under an earlier
  encryption key: when sync starts, Gancho fetches their iCloud copy again,
  which rewrites the content under the current key. Privacy Center counts the
  synced clips iCloud could not restore separately, and removing unreadable
  clips no longer leaves a deletion that sync would carry to iCloud.

- Check for unreadable clips once per store and afterwards recheck only the
  clips that check found, instead of opening every stored image and file each
  time the Privacy Center opens.

- Refresh the Mac panel after removing unreadable clips, and record a failed
  check for unreadable clips in Recent issues instead of showing none.

## [0.10.1] - 2026-10-16

### Fixed

- Keep iCloud uploads moving when one clip's saved data can't be read on this
  Mac. That clip is skipped and counted in Recent issues, instead of every
  upload stopping behind it with a repeating sync error.

- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.10.0 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

- Stop describing text recipes, selected context and meaning suggestions
  (shipped in 0.10.0) and copying text from the screen (shipped in 0.8.3) as
  unreleased in the documentation.

## [0.10.0] - 2026-10-15

### Added

- Go back from later welcome steps with a new Back button; Skip and the manual
  paste fallback stay available.

- Explicit, off-by-default meaning suggestions in a separate panel section, with
  cancellation and index-coverage status while conventional results remain
  intact.

- Add scoped, bounded hybrid retrieval with pre-limit privacy and metadata
  filters, deterministic related ranking and real bilingual relevance
  evaluation.

- Locally encrypted, reviewed text recipes with an editor, three conservative
  presets, bounded background execution and explicit clipboard-safe copying.
  Definitions are not synced and originals remain intact.

- Versioned, bounded deterministic text action and recipe contracts, reusing
  existing transforms and the selected-context formatter.

- Prepare explicitly selected text as reviewed, bounded Markdown, with optional
  selected-ID, read-only MCP access expiring after one hour.

- Restore deleted default text recipes from the recipe editor without touching
  recipes you kept or edited.

### Changed

- Update SQLCipher to 4.19.0 and Sparkle to 2.10.0. KeyboardShortcuts stays
  at 3.0.1 because 3.1.0 repeats a shortcut pressed while a menu is open.

### Fixed

- Keep Library scopes, counts, and snippets current after confirmed mutations;
  preserve loaded pages and drafts, and offer recovery when reads fail.

- Reject stale iOS pages and superseded previews, thumbnails, and snippet
  templates; retain kind filters when secure storage falls back to memory.

- Improve accent contrast, icon hit areas, and accessible Settings and board
  actions; keep long-template actions and the iOS Paste toolbar reachable.

- Preserve transparency in eight-digit color previews and bound long-text
  preview work without splitting composed characters.

- Record a shortcut Gancho already uses again in Settings or onboarding,
  instead of the recorder staying stuck waiting for input.

- Import CSV records with CRLF line endings and preserve combining-mark text
  and quoted newlines while retaining formula protection when exporting and
  importing clips.

- Refresh exact snippet keyword matches before pasting after a search
  invalidation, while preserving the selected row and loaded pages for an
  unchanged search.

- Preserve queued iCloud deletions when an older upload conflict or automatic
  retry finishes after the local deletion.

- Scroll the history panel without redrawing every thumbnail, and copy without
  re-indexing Spotlight or refreshing a closed Library each time.

- Toggle several boards in a row with Return in the board picker, and keep the
  ⌘/ shortcut hint in the footer's Keyboard shortcuts tooltip.

- Never show a preview, thumbnail or snippet body that changed or became
  protected while it was loading, and explain why a stale snippet suggestion
  does not insert.

- Keep a board you deleted gone while iCloud sync is still sending the
  deletion, instead of letting an incoming copy of the board, or a clip that
  was still in it, bring it back. The clip's other boards are kept.

- Correct a clip on iCloud right away when an incoming copy of it still lists
  a board you deleted, instead of waiting for the next full sync.

- Send a clip to iCloud with the text and details of the same edit, even when
  you change it while sync is preparing the upload.

- Never let a generated title or a background semantic vector computed for
  older text land on a clip whose text has since changed.

- Queue snippet edits made through the public snippet API for sync, and drop
  the stale semantic vector when the text changes.

- Paste with Return or ⌘V from the results of the search you just typed, never
  from rows left over from the previous query.

- State on the website that the iPhone and iPad apps are not available yet,
  and make its secondary text easier to read.

- Preview CSV imports without keeping an extra copy of every row in memory.

- Keep a clip's image from being deleted as an orphan while another process is
  saving the same image, and recover an unreadable store by setting aside the
  whole database, its journals and its images together, resuming safely after
  an interruption.

- Build each backup in a private folder and publish it only once it is
  complete, so a failed export never damages a previous backup, and replace
  only a folder that is already a Gancho backup or is empty.

- Re-activate a Pro license after signing out or a revocation without
  restarting Gancho, ignore late replies from superseded license requests and
  release the seat a superseded activation used.

- Fail safely on a malformed database key in the Keychain instead of deleting
  it, which could also remove a valid synced key and force store recovery.

- Keep MCP search inside the exact reviewed clip revisions. Changed clips no
  longer expose new previews or displace unchanged matches from a limited search.

- Read MCP clip policy and content from one database snapshot, so an intervening
  edit cannot pair previously approved metadata with an unreviewed body.

- Detect a credit card even when an earlier order or reference number fails
  its checksum, or when the card is followed by its security code or preceded
  by a phone number, so mixed clipboard text still gets masking and short
  expiry. Phone numbers, dates and order ids keep their normal handling.

- Keep the panel's hidden ⌘V, ⌥⌘V, ⌘Y, ⌘G and ⇧⌘C shortcuts away from a field
  being edited, the board picker and the shortcuts sheet, and stop list keys
  acting behind that sheet. Escape cancels a title or content edit.

- End the open-time newest-clip selection as soon as you scroll, edit, move into
  the peek, open the board picker or use ⌘P, ⌘S or ⌘B, and keep an unsaved
  inline edit across a trip to another app. More actions is reachable from the
  keyboard, a failed developer action says so, and the gallery's arrow keys
  follow the grid you see.

- Show "Results" or "Filtered" instead of "Recent" above searches and filters,
  resize the panel from Settings only when you pick a size, confirm backups and
  report a settings file that couldn't be imported. Toasts and the shortcuts
  sheet follow the solid panel preference.

- Keep a stopped iCloud sync engine stopped, order sync restarts and resets, and
  tombstone already-synced clips and boards deleted while sync is off so they
  don't come back.

- Hide expired clips from lists, search, counts, content reads and MCP right
  away instead of waiting for the next purge, and treat archived clips as
  missing over MCP. Metadata-scope MCP search matches only titles and previews,
  and selected-context grants stop serving a clip changed after review.

- Remove blobs, thumbnails and semantic vectors together with their clip,
  including remote deletions, and sweep orphaned blobs after launch on the Mac.

- Keep secret-looking automatic OCR text out of the store, stop OCR from
  re-uploading images it can't sync, and drop a capture whose pasteboard
  changed during the read.

- Guard the CLI: `gancho save` refuses detected secrets unless `--allow-secret`
  is passed, `gancho copy` needs `--reveal` for sensitive clips and refuses
  expired ones, and `gancho export --out` writes owner-only files. Gancho's CSV
  export can be imported back, and restored archives repair malformed ids.

- Record failed captures in the Privacy Center, ignore a stale tier lookup at
  launch, and swap in a freshly encrypted store atomically with recovery of a
  leftover copy.

- Give iPad the iPhone shell (paste control, settings, sheets, deep links,
  pagination, row actions), reset the detail pane per clip, make the Type
  filter work without a query, keep the iPhone peek live, reload widgets after
  changes, confirm board deletion, and use thumbnails for history rows.

- Cancel superseded keyboard searches, keep shared images in their original
  format, mask the Live Activity like widgets, show readable kind names in
  English, localize diagnostics, and align the keyboard's Full Access privacy
  copy with onboarding.

- Open the panel on the newest clip with the search field focused, instead of
  the row and filter rail the previous session ended on. Arrow keys move
  between rows without a cross-fade, and board suggestions and translation
  checks wait until the selection settles.

- Make the panel solid by default, with a "Translucent background" option, and
  show which panel size preset is active. The panel answers the shortcut on
  key down, is prepared ahead of the first open, and appears at once without
  the open entrance animation.

- Keep developer actions behind "More actions" so each peek shows the
  essentials first; the choice is remembered.

- Inject device-name reads from the app and capture-extension shells, keeping
  platform UI imports and real host-name discovery out of the provenance core
  and its tests. Existing provenance, deduplication and sync metadata are
  unchanged.

- Keep recipe review headings and delivery controls visible while scrolling longer eight-step definitions.

- Bound selected-text row previews by Unicode scalars, so oversized combining
  sequences cannot make a visually short excerpt expensive to render. Full
  reviewed text and delivery limits are unchanged.

- Keep panel sizing under AppKit control to avoid redundant whole-view size
  measurement delaying translation results, while preserving resize bounds and
  display preferences.

- Show installed native translation destinations independently of Apple
  Intelligence, with an unavailable-engine message instead of an empty result.

- Queue edited snippet titles and text for synchronization while keeping
  keyword-only edits local and preserving uploads that were already pending.
  Local keyword edits no longer outrank newer remote title/body changes. Edits
  carrying protected content are refused with an inline notice.

- Preserve modified snippet drafts when their original is removed; recover them
  explicitly as a new classified snippet or discard them without restoring it.
  Library loading and safe copying remain available with the in-memory fallback
  store, which does not support snippet persistence.

- Use native mouse click counts for panel double-click paste while preserving
  immediate single-click selection, context menus and file dragging.

- Make macOS UI fixtures await ephemeral capture ingestion before showing the
  panel, and keep opt-in Library evidence on the primary display without
  changing normal window placement. Timer views import Combine explicitly.
- Scope native UI attachments to Gancho components and add supplemental
  ten-iteration hosted macOS and iOS interaction stress runs; full platform
  validation remains separate. Translucent component captures require an
  isolated synthetic desktop.

- Select exact semantic top-K results with a shared bounded heap instead of
  re-sorting retained candidates, keeping clip-ID tie order. The in-memory
  reference index uses the same selector and rejects non-finite or overflowing
  vectors.

- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.9.1 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

## [0.9.1] - 2026-09-29

### Fixed

- The panel's Text size preference (Settings › Panel) now changes the text,
  tiles and dock glyphs it promised: it had been wired to a mechanism macOS
  does not honour, so Small, Standard and Large rendered identically. On
  iPhone and iPad, history rows keep following the system text size.
- Two sync failures no longer pass in silence: saved sync state that can no
  longer be read now leaves a content-free entry in the Privacy Center's
  Recent issues before the engine starts a fresh fetch, and a restart that
  fails after the iCloud account changed is recorded instead of dropped.
- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.9.0 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

## [0.9.0] - 2026-09-28

### Added

- An optional ambient colour for the Mac panel (Settings › Panel › Ambient
  color, off by default): a faint field of the selected clip's colour under
  the list and the peek — an image's own average colour, otherwise its kind's
  tint — that crossfades as you move. It never shows when Reduce Transparency
  or Increase Contrast is on.
- A gallery layout for the Mac panel (⌘G, remembered): the history as a grid
  of visual cards — thumbnails, colour swatches, code and text previews —
  with the same date sections, ⌘1–9 badges and peek beside it. ↑↓ (and ⇧↑↓
  for a range) move by a row of cards, ←→ step within one, → at the end of a
  row still opens the peek, and ↓ from the last row wraps to the top of its
  column.

### Changed

- The Mac history panel has one toolbar instead of three stacked rows: boards
  on the left, type filters as glyph chips that expand to their name when
  active, the source-app filter and Save filter on the right. Compact layouts
  wrap the toolbar without clipping controls, and keyboard navigation scrolls
  boards into view. Filtering and reordering keep row selection and quick-paste
  badges aligned with the current clips. The search field
  sits directly on the panel glass at a larger size, with autocorrection and
  text suggestions disabled for literal queries. Rows carry their identity
  in the tile (a link's host initial, the real colour swatch, the image
  thumbnail), code previews are syntax-tinted, and the source app and a
  minute-granular capture time sit in a trailing column; iPhone and iPad history
  rows share the same layout. The selection highlight glides between rows and
  section counts roll instead of flicking; both respect Reduce Motion.
- The panel's peek opens with a hero card per kind — the image with its
  Live-Text regions, a link's host and complete URL (parsed on the Mac,
  never fetched), a colour band, or the text — and closes with an action
  dock: Paste, Paste plain, Copy text from image, Pin and Board, each with
  its key. Developer actions wrap as chips above the dock. The insight line
  now also names the boards a clip is in and refreshes after membership changes.
  The dock stays visible in compact panels while its content scrolls, and its
  shortcuts work while the peek owns focus. Return still pastes and ↑↓ still
  walk the actions in the same order.
- The panel now moves the way it reads: it settles in on open, the peek
  swaps with a soft blur when you change clips, the active board and type
  chip glides to your choice, rows and actions light up under the pointer,
  and the pin glyph bounces once when you toggle it. Everything above is
  instant when Reduce Motion is on.

### Fixed

- The Library keeps what you type in a snippet's body while it refreshes
  itself (a finished sync, a new or renamed board) and saves it when you move
  to another snippet or board, the way the title and keyword already saved on
  leaving their field. ⌘S saves without leaving.
- A row's hover highlight no longer stays on a row that scrolled out from
  under a still pointer: it clears while the list moves and returns with the
  next pointer move.
- The Mac peek masks sensitive titles and hides its hero and derived content in
  Private Mode. The board picker takes keyboard focus when opened from the peek
  or search, without requiring an extra click. Returning from a completion
  window no longer redirects inline editing into the search field.
- Align post-release documentation, the bilingual website, the Sparkle feed
  mirror and Homebrew cask metadata with the published v0.8.4 DMG.
  Physical-device acceptance remains pending; the published app, tag and
  checksum are unchanged.

## [0.8.4] - 2026-09-24

### Security

- JWTs, credit-card numbers and secrets stay protected whenever a clip leaves
  Gancho, even if a clip lost its sensitivity flag: dragging clips out on Mac,
  the menu bar's "Last copied" line and fallback menu, the iPhone and iPad
  keyboard, iOS sharing, and JSON, CSV and archive exports that exclude
  sensitive clips all apply the same rule. Drag-out, the keyboard and sharing
  re-check a clip right before handing it over, so one that was deleted,
  expired or became protected in the meantime is never delivered. Private
  Mode now also hides the fallback menu's previews.
- On iPhone and iPad, a paste gesture no longer overrides the markers that
  password managers and one-time-code sources put on the clipboard. The paste
  button, Save Clipboard action, Control Center control and keyboard refuse
  such content — including when the marker sits on another item of the same
  paste — and say why.

### Fixed

- Sharing a clip from iOS sends its full content instead of a truncated
  preview, and images as PNG; rich text shares its plain text unless that text
  classifies as protected.
- The keyboard and the Save Clipboard action save through the app's own
  classification, duplicate handling and sensitive-clip lifetime, and only
  confirm "Saved" once the clip is actually stored. The keyboard lists only
  clips it can still deliver and says when one is no longer available.
- Items shared into Gancho from other iPhone and iPad apps leave the shared
  queue only after they are durably saved. A share that fails to save waits for
  the next pickup, a replayed share never re-creates a clip you deleted, and a
  large queue is imported in one pass.
- iCloud sync no longer skips changes after an incomplete download: the
  checkpoint only advances once a page is applied, one record that cannot be
  read no longer blocks later changes, and a receive problem no longer holds
  back this device's uploads.
- An upload confirmation that arrives after a newer edit — including a board
  deletion — no longer marks that edit as synced, an interrupted identity reset
  after an account change or a deleted iCloud zone resumes after a restart, and
  one clip that cannot be packaged no longer blocks the rest of the upload.
- The history panel keeps the selected clip, and a multi-selection, when the
  list refreshes after a new copy, an edit or a deletion, instead of jumping
  back to the first row. A scrolled list keeps its loaded rows, and a page
  requested during a refresh loads once it finishes.
- Align post-release documentation, the bilingual website and Homebrew cask
  metadata with the published v0.8.3 DMG.

## [0.8.3] - 2026-09-20

### Security

- Activating or re-validating a direct-download license now requires Lemon
  Squeezy's answer to name the live Gancho Pro store and product and to not be
  a test-mode key. The public License API accepts keys from every Lemon
  Squeezy store, so a merely-valid key for someone else's product could
  previously have unlocked Pro. An answer that names no store at all still
  never revokes an existing activation — only an explicit answer can.
- On iPhone and iPad, clips you share into Gancho from another app are now
  sealed with the key that encrypts your history while they wait in the shared
  container for Gancho to pick them up. They previously sat there as plaintext
  until the app next came to the foreground. If that key cannot be read, the
  share fails with an error haptic instead of falling back to plaintext, and a
  queued share that cannot be read yet is kept for the next pickup instead of
  being discarded.

### Added

- Copy text from a selected screen region with a configurable shortcut, a
  fused hook-and-crosshair cursor, local recognition and transient review.
  Entering Private Mode cancels pending selection and recognition.

- Review, reorder and copy selected text clips together with a configurable
  separator, without saving a new clip or pasting automatically.

- Save and edit local encrypted search filters, preserving type, app, board,
  mode and pinned-only predicates.

- Visual Mac Library cards with lazy image thumbnails, readable color swatches,
  and code previews. Protected clips stay masked and the quick panel stays compact.
- Free manual image OCR on Mac, read in place: the history panel's peek shows
  the recognized text beside the image, with one selectable region per line on
  the thumbnail (Live Text style). Copy one line or all of it, edit inline, and
  save it as a separate clip only when requested; a recognized secret is never
  copied automatically. Other entry points keep the review window. Automatic
  searchable-image indexing remains Pro. No network or automatic paste.
- The history panel's list and peek now share one surface separated by a
  hairline, instead of two floating panes with a gap.
- Entity chips under the recognized image text: links open in the browser
  (http and https only) and email addresses open a mail draft, named by host;
  when the text reads in another language and an on-device engine can run, a
  Translate chip renders the translation beside the original with Copy and
  Paste. Nothing appears for a recognized secret.

- **The source now targets macOS 15.4 (Sequoia).** The Foundation Models tier
  requires macOS 26: below it, clip titles fall back to the deterministic
  heuristics, while model-backed Smart Paste rewrites, Translate, and Ask
  your clipboard are unavailable — exactly as when Apple Intelligence is
  switched off. Deterministic PII redaction keeps working everywhere, the
  Intelligence screen states the OS requirement explicitly, and the interface
  uses an opaque material where Liquid Glass does not exist. Capture,
  encrypted history, search (exact, fuzzy, regex, and semantic), boards,
  retention, sync, Pro, and updates target Sequoia; real oldest-runtime and
  cross-device acceptance remain pending after publication.
- **Clips remember which device they were copied on.** Every new capture is
  stamped with the capturing device's name (as the OS reports it), the name
  travels with the clip when sync is enabled, and the iOS clip detail shows
  it. Clips captured before this release carry no origin — provenance is
  known from capture time onward.
- **Buy and activate Pro from the direct download.** Purchasing on the direct
  channel now works end to end for the first time: buy through the Lemon
  Squeezy checkout, paste the key, and Pro unlocks. Previously the purchase
  controls were hidden, because the build could not issue an entitlement
  without carrying a private signing key.
- **Pro keeps working offline.** An activated license is confirmed with Lemon
  Squeezy about once a week and keeps working for 30 days without a reachable
  network, so a trip or a long stretch offline never takes away what you paid
  for. If that window does pass, Gancho says the license needs reconnecting —
  and offers to check again — instead of asking you to buy it a second time.
- **Move your license to another Mac.** Settings → Pro can release this Mac's
  activation, so replacing a machine no longer uses up your activations with no
  way to reclaim them.

### Changed

- Lemon Squeezy is now the authority on who is entitled. Gancho records the
  activation it issued and re-confirms it, rather than minting its own signed
  token — so the app ships with no license-signing key to extract, and refunds
  or revocations reach an install that is already running.
- Removed the obsolete local token signer, its embedded key wiring, the install
  fingerprint, and the keypair generator from the distributed source and build
  configuration.
- Translate now uses Apple's built-in Translation engine whenever the language
  pair is already installed on your device, which is noticeably faster than
  the on-device model once it is warm. Every other pair still falls back to
  the model. Both paths redact secrets before translating, and Gancho never
  downloads language assets on its own.
- Large histories do less work. List pages no longer load clip bodies they
  never show, the Mac panel no longer rebuilds its visible list for every row
  it draws, finding source apps uses an index instead of scanning the whole
  history each time the panel opens, semantic search reads stored vectors in
  place instead of copying every one into memory first, and incoming sync
  changes are committed once per page instead of twice per record. Semantic
  search measured about twice as fast on a 100,000-clip test history, and
  applying a 400-record sync page about twice as fast.
- Gancho enriches at most two new clips at a time with on-device intelligence,
  so a burst of copies waits its turn in order instead of starting a model
  session for every clip at once.
- History backups are written out as they are produced instead of holding the
  entire history in memory twice.
- Local AI clients connected over MCP now get tool descriptions that match what
  each tool does: which fields a search returns, how an out-of-range limit or an
  unknown search mode is handled, and how a withheld clip body differs from a
  refused request.

### Fixed

- The history panel's glass now fills its window edge to edge, so no outline shows
  around it, and the shortcut card, board picker and consent prompt dim only the
  panel instead of revealing the window's transparent shell.
- Sensitive clip cards now mask titles and thumbnails as well as text previews.
- Combined-text review avoids repeated composition, and MCP content tools and
  search exclude intrinsically masked clips even when an optional flag is absent.
- iOS capture status distinguishes saved, limit and failure outcomes, and its
  system paste control remains accessible to the hosted UI runner.

- A Lemon Squeezy outage, rate limit, or gateway error can no longer revoke an
  activated license: only a decodable answer that explicitly denies the key
  does. An explicit denial on any non-outage status still revokes promptly
  (429 and 5xx are never read as answers), and deactivating a Mac whose slot was already released from the dashboard
  now reports a clean release instead of a false network error.
- Backups are safer end to end: export refuses to write an archive with a
  corrupt payload and the Mac app now says so (and cleans up the partial file)
  instead of failing silently; restore accepts backups from earlier versions
  that skipped a missing payload, verifies exactly the bytes it imports, and
  its safety ceilings sit far above anything Gancho itself produces.
- Sparkle updated to 2.9.6, which hardens the update installer: it now rejects
  a package-based install whose signature validation failed, guards how the
  downloaded archive is moved into place, and stops copying its progress tool
  for the root user.
- A response Gancho cannot recognize no longer counts as Lemon Squeezy denying
  a license, so a change to their reply format cannot revoke Pro for everyone
  at once; only an explicit rejection does, and an unreachable service falls
  back to the offline grace window.
- Updating a saved direct-download activation now uses an in-place Keychain
  update, so an intermittent write failure cannot delete the previously
  confirmed entitlement before its replacement is stored.
- A revoked license drops to Free for the session even if clearing the stored
  record fails, and a clock set backwards no longer postpones the next license
  check indefinitely.
- Gancho's windows now open centered on the screen. Settings, Welcome, Privacy
  Center, Intelligence, MCP Access, Clipboard Access and Gancho Pro used to
  open with their left edge at the middle of the screen, so on a narrow
  display, such as a scaled one 1024 points wide, part of the window sat
  off-screen. In MCP Access, that hid the Revoke buttons.
- With iCloud sync on, a clip whose delete fails on this device is no longer
  removed from your other devices. The failed delete used to go out anyway, so
  the clip vanished everywhere else while surviving here, with nothing to put
  it back. Only deletes that land locally are sent now, and a failure is
  reported instead of passing silently.
- On iPhone and iPad, clips flagged sensitive now expire when you leave Gancho,
  and iOS may also run that cleanup in the background, instead of waiting for
  the app to be opened again. The background run happens at the system's
  discretion, so it is an extra opportunity, not a schedule.
- On the Mac, exporting settings, saving a support bundle, changing local AI
  client (MCP) access, buying or restoring Pro, turning off Remember searches,
  and editing a snippet now report a failure instead of looking like they
  worked. Cancelling a purchase stays silent.
- The Mac no longer lets a board be created or renamed with a blank name. Board
  names are trimmed the way they already were on iPhone and iPad.
- The Library refreshes once a board rename or delete has actually landed,
  instead of after a fixed delay that could read the list too early, and a
  delete that fails no longer moves the selection to All clips.
- Gancho's app, its extensions, and the command-line tool now wait up to two
  seconds for one another when the history database is busy, instead of
  failing a write immediately.
- The `gancho` command-line tool ignores a blank `GANCHO_STORE_DIR` instead of
  looking for your history in the current directory and reporting an empty
  clipboard, and it strips control characters from board names, paths, and
  echoed arguments so they cannot break its output or reach the terminal raw.
- The license key field in Gancho Pro is now translated into Spanish.

## [0.8.2] - 2026-07-25

### Changed

- Split the macOS history panel by responsibility: capture status, the
  selected-clip preview session, selection actions, results rendering, and the
  modal layer now live in focused views and tested app-layer policies, while the
  panel keeps one navigation owner for focus, keyboard semantics, and paging.
- Refreshed the encrypted storage stack to GRDB 7.11.1 and SQLCipher.swift
  4.17.0 through the minimal hand-rebased fork, without changing Gancho's
  database schema or encrypted-store format.
- Updated Sauce to 2.5.2, incorporating its corrected keypad Enter mapping
  while preserving Gancho's layout-aware paste-back behavior.
- Migrated global shortcut recording and delivery to KeyboardShortcuts 3.0.1,
  preserving stored shortcuts and adding signed launch coverage for persisted
  hotkey registration.
- The localization gate now reads interpolated copy and strings declared
  directly as localized keys, so translations missing from those forms fail a
  test instead of reaching a release.

### Fixed

- Spanish now covers four strings that still rendered in English: the paste
  stack's VoiceOver label on macOS, and the Share action, the copy-last-URL
  confirmation, and the clear-sensitive-clips result on iOS.
- A filter that empties the history panel no longer looks like an empty
  history. Narrowing to a kind, board, or source app with no search text used to
  show the first-run message and offer no way back; it now reports no matches
  and keeps Clear filters reachable, including for VoiceOver.

## [0.8.1] - 2026-07-22

### Changed

- CloudKit recovery decisions and pending-work planning now live in focused,
  deterministic components, reducing the sync engine's stateful surface while
  preserving its existing retry and restart behavior.
- Release validation now keeps macOS and iOS UI result bundles and can export
  their screenshots and attachments as reproducible review evidence.

### Fixed

- Lifetime Pro purchases remain unlocked when StoreKit temporarily omits a
  valid non-consumable purchase from its current-entitlements snapshot.
- Hosted UI validation now verifies final state and relative window behavior
  instead of depending on transient accessibility flags or display-specific
  pixel dimensions.

## [0.8.0] - 2026-07-20

### Added

- **Import an existing clipboard history with a safety preview.** The Mac app
  accepts Maccy archives and CSV, previews what can be imported without writing,
  rejects protected or malformed source rows, deduplicates in one transaction,
  supports cancellation, and reports exact imported and skipped totals.
- **Approve local AI clients one at a time.** Every MCP process now requires an
  expiring, revocable client grant with an explicit board/time context and an
  independent read-only or read-write policy. Authorization is re-read on every
  call, database filters fail closed, sensitive clips remain excluded, and the
  access ledger contains metadata only.
- **Understand activation without tracking content.** Gancho records a closed
  set of local, content-free first-value milestones before diagnostics consent.
  If the user later opts in, diagnostics receives one coarse aggregate rather
  than a replay of pre-consent actions.
- **Review private activity on every device.** The Mac and iOS Privacy Centers
  show per-app capture, reuse, ignored/protected-copy, and sensitive-expiry
  totals from a bounded on-device receipt. It retains 13 rolling months, never
  syncs or exports, and can be cleared without deleting history.
- **Fit the Mac panel to your workspace.** The history window now resizes from
  its edges, offers Compact, Standard, and Large shortcuts, remembers manual
  geometry across relaunches, and scales every semantic text style with a
  persistent Small, Standard, or Large preference.

### Changed

- Extracted Spotlight reconciliation, launch maintenance, UI-test fixtures,
  store-change routing, and one-shot hint policy from the macOS application
  facade into focused, testable collaborators.
- Added content-free panel-to-first-frame instrumentation and a deployment-floor
  inventory so future compatibility decisions use measured runtime evidence.
- Made the public DMG lane fail closed: a tag now requires Developer ID signing,
  notarization, an embedded production CloudKit/Push provisioning profile, a
  signed Sparkle appcast, and mounted-artifact QA. Public builds reject the
  legacy private license signer. Until secure activation exists, a fresh public
  direct install remains Free and its Pro-only sync transport stays disabled.

### Fixed

- History imports now preserve cancellation and protected-content semantics,
  including source-file safety checks and atomic duplicate handling.
- Store-change reconciliation now coalesces updates through one restart-safe
  path instead of creating unbounded debounce work.
- Onboarding UI automation now waits for real transitions and foreground
  activation instead of racing the next screen.

## [0.7.0] - 2026-07-16

### Added

- **Work with several clips at once on the Mac.** Shift-click/Shift-arrow now
  selects a range and Command-click builds a non-contiguous selection. A compact
  action bar can add the whole selection to the paste stack, file it into a
  board, or delete it with one shared Undo. When every selected item is a file
  reference, dragging any selected row sends the complete de-duplicated file
  set to Finder or another file drop target; mixed selections safely keep the
  one-row drag behavior.
- **Find your snippets from Spotlight.** Snippets and pinned clips now appear
  in the system-wide Spotlight search on Mac, iPhone, and iPad. Opening a
  result jumps straight to the clip on iPhone and iPad, and brings up the
  history panel on the Mac. Only the curated Library is indexed: raw history,
  secret and masked-credential clips, and expiring clips never reach the
  system index — and even inside an ordinary snippet, key- and card-shaped
  text is replaced with `[redacted]` before anything is donated. A new toggle
  in Settings turns this off and removes everything from Spotlight
  immediately; if that removal ever fails, Gancho records a content-free
  entry in Recent issues instead of failing silently.

### Changed

- **Big boards open instantly.** A board's clips now load in pages — in the
  history panel, the iOS list, the Library, and the keyboard — instead of
  loading the whole board at once, so a board with thousands of clips opens as
  fast as a small one and keeps scrolling smoothly.
- **Semantic search survives model upgrades.** Every stored search vector now
  records which embedding model produced it; after a future model upgrade,
  Gancho quietly re-indexes older clips in the background (only while the
  device is idle-friendly: not thermally stressed and not in Low Power Mode)
  instead of mixing incompatible results.
- Updated the Sparkle auto-updater framework to 2.9.4.
- **Semantic search got faster at scale.** Measuring retrieval phase by phase
  at 10k and 100k stored vectors showed the final sort dominating; results are
  now picked with a bounded selection instead — the same top results, with the
  10k search's 95th percentile dropping to under 30ms.

### Fixed

- **AI features can no longer echo a secret that hides inside ordinary text.**
  Live evaluation of Gancho's on-device prompts showed that a "faithful"
  summary, key-points list, or clipboard answer could reproduce an API key or
  card number embedded in an otherwise normal clip. Text now passes a
  deterministic structural redaction before it ever reaches the on-device
  model — keys, tokens, card numbers, and private-key blocks become
  `[redacted]` — so the model cannot echo what it never saw. Every shipped
  prompt now lives in a versioned catalog with frozen wording and an opt-in
  evaluation suite that fails if a future prompt change weakens these
  guarantees.

- **The menu-bar icon always comes back (macOS).** If the menu-bar helper ever
  died — a crash, or a quit that didn't fully take — Gancho could stay running
  in the background with no icon and no window, leaving no way to reach it short
  of force-quitting the process. Gancho now guarantees a menu-bar affordance:
  after launching the helper it verifies the icon actually appeared, and if it
  didn't, falls back to a built-in menu-bar icon. Clicking Gancho in Finder or
  the Dock re-establishes the icon the same way, so you can always reach the
  menu (and "Quit Gancho") without touching Activity Monitor.
  If every menu-bar affordance is removed anyway, the app terminates instead of
  leaving clipboard history resident in an unreachable background process.
- **JWT tokens no longer show in the clear in the history list.** A bare JWT
  copied to the clipboard is recognized as a token but wasn't flagged as a
  detected secret, so its row preview appeared unmasked in the history list
  (the peek and full preview already masked it). Its stored preview is now
  masked like other credential kinds. The token stays in your history and
  remains fully usable — Decode JWT and paste still work — it just isn't shown
  in the clear at a glance.

## [0.6.0] - 2026-07-14

### Changed

- **Fuzzy search stays responsive as history grows.** The local FTS index now
  accelerates the short prefixes produced while typing, with existing indexes
  upgraded transactionally. The 100k-clip performance gate separately measures
  cold startup cost and five reproducible warm rounds instead of depending on
  one favorable query sequence.

### Added

- **Filter history by the app it came from.** macOS, iPhone, and iPad now show
  recent source apps as a content-free filter that composes with text, kind,
  board, and date filters. Clearing it restores the previous search without
  creating a second query or selection model.
- **Turn proven clips into snippets at the right moment.** After a clip is
  reused for the third time, Gancho offers one local, dismissible promotion to
  save it as a snippet. Secrets and archived clips are excluded, and clips
  already organized in a board take priority over the prompt.
- **Name and refine the text you keep.** Clip titles can now be edited on Mac,
  iPhone, and iPad. Text-like clips also gain an explicit Edit → Save/Cancel
  flow that preserves exact content, refreshes search, invalidates stale
  semantic data, and only syncs after the durable local write succeeds.
- **Open a full, privacy-safe preview on macOS.** Press Command-Y to inspect
  complete text, code, colors, rich text, images, or file references in a
  resizable read-only window. Sensitive and intrinsically masked clips are
  rejected before their stored payload is read, and no temporary Quick Look
  files are written.
- **Give every board a recognizable identity.** User boards can now choose from
  a fixed accessible color palette and an optional emoji on both Mac and
  iPhone/iPad. The appearance editor is keyboard- and VoiceOver-friendly,
  previews changes before saving, and uses the existing durable sync path so
  the same identity follows the board across devices. Existing boards keep
  their stable automatic color until customized.
- **Text transforms that work on every device.** A new "Transform" menu in the
  macOS peek and the iOS clip detail applies pure, deterministic text
  operations — Title Case, collapse spaces, sort/dedupe lines, URL encode and
  decode, SHA-256 — with the result shown for review before you paste or copy
  it. The panel's "Paste as…" menu gains the same new options. No Apple
  Intelligence required, nothing leaves the device, and the stored clip is
  never modified.
- **The never-capture app list is easier to manage (macOS).** Excluded apps in
  Settings → Capture now show their real name and icon (with the bundle id as
  a caption), built-in exclusions carry a "Default" tag, and you can add apps
  straight from /Applications with "Choose from Applications…" — no bundle-id
  typing, and no need for the app to be running. If you removed a built-in
  exclusion, "Restore default exclusions" brings them all back with one click.
- **Drag clips straight out of the panel (macOS).** Any history row — and the
  peek's title bar or image preview — can be dragged into another app: text
  lands as text, links as links, images as PNG, and a copied file as the file
  itself (a multi-file clip drops its first file; the full path list travels
  as text). The panel stays open while you drag, so pulling several clips
  into a document is one drag each. Clips marked sensitive can't be dragged;
  revealing a secret stays an explicit action.
- **Recall your recent searches with ⌘↑.** A search that led to a paste is
  remembered; press ⌘↑ in the panel's search field to bring it back (and again
  for older ones, ⌘↓ to walk forward — shell-style). Kept only on this Mac,
  capped at 50, and the new "Remember searches" toggle in Settings → Privacy
  erases them all the moment you turn it off.
- **Search learns your habits.** Results now blend text relevance with how
  often — and how recently — you actually paste each clip, so the snippet you
  use every day surfaces above a slightly-better text match you haven't touched
  in months. The boost decays over ~a month, applies to search only (the
  recent list stays chronological). Usage counts stay local; last-used
  timestamps follow Gancho's existing sync metadata policy.
- **The panel shows whether Gancho is capturing.** A small "Capturing" indicator
  in the panel footer (and "Paused" when it isn't), so if you copy something and
  don't see it you can tell at a glance whether Gancho is watching. When capture
  is paused — manually, by Private Mode, while screen sharing, or because
  clipboard access is off — the empty-state names the reason and points to the
  one-tap fix in the notice above, instead of an unhelpful "⌘C to start."
- **File clips into boards without the mouse (macOS).** Press **⌘B** on the
  selected clip to open a board picker: type to filter, ↑↓ to move, Return to
  toggle membership, ⌘Return (or the "New board" row) to create a board and file
  the clip into it, Esc to close. **⇧⌘B** repeats the last board you used, so
  curating many clips into one board is a keystroke each.

### Fixed

- **Preview and edit state stays with its clip.** Moving quickly between rows
  can no longer show a late body load, editability state, or unsaved title draft
  from the previously selected clip. Each selection owns a fresh preview state,
  and asynchronous reads are discarded when their clip is no longer selected.
- **Board changes now reflect durable database results.** A failed board-count
  read no longer bypasses the free-tier limit, failed edits are recorded as
  content-free diagnostics, and a board deletion is only queued for sync after
  its local tombstone commits. On iPhone and iPad, a failed deletion also keeps
  the active board filter intact.
- **Curation limits and confirmations now agree across devices.** Pinning on
  iPhone and iPad now honors the same 15-pin free-tier limit as Mac and
  Shortcuts. Saving a snippet only shows success after the database write
  succeeds; failed pin or snippet writes are recorded as content-free
  diagnostics instead of being presented as successful actions.

## [0.5.0] - 2026-07-08

### Fixed

- **The direct-download Mac app now saves your history.** On the Developer ID
  build, the encrypted store's key was stored in iCloud Keychain, which that
  build isn't entitled to use — so it silently fell back to in-memory and showed
  "History isn't being saved," losing everything on quit. The key is now stored
  device-local when a build can't use iCloud Keychain (it never leaves the Mac,
  which is arguably more private), and a store left keyed by an unreachable key
  is safely re-initialized instead of stranding the app.
- **Quitting Gancho fully quits it, and reopening brings the icon back.**
  "Quit Gancho" no longer leaves the agent running headless after the menu-bar
  icon disappears, and clicking Gancho again re-launches the menu-bar helper if
  it went away — no more needing to kill the process by hand.

### Added

- **A live expiry countdown on clips about to age out.** When a clip is within
  an hour of expiring — sensitive clips especially, which get a short lifetime —
  its row now shows a small orange "expires in" timer, so you can act before it
  goes. Appears on both Mac and iPhone/iPad rows.
- **The paste stack is now visible (macOS).** Queue several clips and paste them
  in order — the queue shows as a compact strip in the panel footer with the
  next items at a glance. Click it to reorder (drag), remove an item, or clear
  it; press **⌥⌘Return** on a selected clip to add it to the stack, and your
  paste-stack shortcut pastes the front item each time. The queue is
  session-local and never leaves your Mac.

### Changed

- **A far more generous free tier.** The free history window grows from
  30 days / 2,000 items to **1 year / 10,000 items**. The local basics —
  capture, search, paste-back — should never be the wall; Pro keeps unlimited
  history, unlimited pins/boards/snippets, full on-device AI, and encrypted
  iCloud sync. As before, nothing is deleted at the ceiling: overflow is
  archived and comes back instantly with Pro.

## [0.4.1] - 2026-07-06

### Fixed

- **Reactive iCloud sync between your devices.** A clip copied on one device now
  arrives on the others on its own, both directions — the Mac no longer needs a
  nudge to pull. Root causes: the macOS push entitlement used the wrong
  per-platform key (silently dropped at signing), neither app requested its push
  token at launch, and `CKSyncEngine` only auto-fetches zones a push flagged —
  so the menu-bar agent, which isn't a reliable push target, now also pulls from
  the server directly on a light cadence.
- **AI titles and OCR text sync across devices reliably.** The enrichment a clip
  earns a moment after capture is a second save that could lose a race with the
  first and get silently dropped; the conflict is now resolved and the update
  re-queued, so the title/searchable-text always follows the clip.
- **Board membership syncs.** Filing a clip into a board (or removing it) now
  propagates to your other devices, so the same board set follows each clip.
- The type filter no longer stalls infinite scroll: a narrow filter keeps
  loading more history as you reach the end of the visible list.

### Changed

- The Privacy Center's **"Recent issues"** now records content-free sync trouble
  (a change that couldn't be applied, a failed upload, an out-of-storage pause),
  so a sync hiccup is diagnosable at a glance — still never any clip content.

## [0.4.0] - 2026-07-05

### Added

- **Encrypted iCloud sync** now carries a clip's on-device enrichment with it:
  the AI title and searchable OCR text a clip earns on one device show up on
  your other devices, not just the raw clip. A Pro feature, end-to-end
  encrypted.
- An **About** screen in Settings — version and build, author, MIT license, and
  links to the website and source.
- A manual **Language** picker (System / English / Español) in Settings, applied
  live without a relaunch.
- **18 new Dev Actions** on text and code clips, all offline and deterministic:
  SHA-256/SHA-1/MD5 hashes, URL encode/decode, HTML-entity encode/decode,
  JSON-string escape/unescape, case conversion (camel/snake/kebab/title),
  slugify, epoch ↔ ISO-8601 date conversion, number-base conversion
  (dec/hex/bin/oct), sort/dedupe/reverse lines, and line/word/character counts.
- The `gancho` CLI grew **`boards`, `pin`, and `unpin`**: list your boards
  (`--json` for scripts) and pin or unpin a clip by id without leaving the
  terminal. Detector-flagged sensitive clips refuse to pin, so a secret can't
  be exempted from the short "Sensitive items" retention window by accident.

### Changed

- **Faster launch**: the one-time preview backfill for clips saved by older
  versions now runs in the background after your history opens, instead of
  holding up the open itself.
- The built-in "Never capture from these apps" suggestions now also cover
  Strongbox, KeePassium, MacPass, NordPass, Venmo, and Cash App out of the box.

### Fixed

- **⌘V pastes the selected clip** from the panel (like Enter), instead of the
  keystroke landing in the search field.
- Selecting a clip with the mouse is instant now, and the list never leaves
  several rows — or none — highlighted at once.
- The detail peek no longer clips its action list or crowds out the text
  preview on clips with many available transforms; the search-field placeholder
  no longer cuts off its first characters.
- Deleting a clip hides it immediately with a working **Undo**, and the Undo
  toast now appears on the display you're actually using.
- A clip you re-copy earns its smart title even when its first capture predated
  on-device titling.

### Security

- **Backups and exports now leave detector-flagged sensitive clips out by
  default** — the macOS and iPhone/iPad "Back up history" archives and
  `gancho export` alike. A secret the detector gave a 10-minute expiry no
  longer becomes permanent plaintext the moment you export; pass
  `--include-sensitive` to the CLI when you really want a full dump.
- CSV exports now guard against **spreadsheet formula injection**: a clip
  starting with `=`, `+`, `-`, or `@` can no longer run as a formula when the
  export is opened in Excel, Numbers, or Sheets.
- The secret detector recognizes **eight more credential shapes**: Slack
  webhooks, Google API keys, GCP service-account JSON, OpenAI keys, npm
  tokens, Azure connection strings, `Authorization: Bearer` headers, and PGP
  private-key blocks.
- The database-encryption dependency (the SQLCipher-enabled GRDB fork) is now
  **pinned to an exact revision**, so the encryption layer can never silently
  change under a dependency re-resolve.

## [0.3.2] - 2026-06-28

### Added

- An **Undo window** for deleting a clip (macOS): the clip disappears at once,
  but the destructive removal — and the iCloud tombstone that propagates it to
  your other devices — only commits after a few seconds, with a "Deleted · Undo"
  toast. A mis-tap never loses history, and pins, boards, and timestamps all
  survive an Undo intact.
- A **Gancho Pro screen on iPhone/iPad** (Settings → Gancho Pro): it shows what
  Pro unlocks, whether you're on the free or Pro plan, and a Restore Purchase
  button — and it now opens automatically when you reach a free-tier limit,
  instead of a note that vanished with no way forward.
- **VoiceOver announcements** for action confirmations across the Mac app, the
  iPhone app, and the keyboard: copy, paste, save, pin, delete, and "Synced"
  are now spoken aloud, not just shown.

### Changed

- The Mac panel's sync indicator now reads **"Synced · &lt;time&gt; ago"** with a
  live relative timestamp, so a finished sync reads as current rather than stale.
- Activating a Pro license on the Mac now explains **exactly why** a key didn't
  take — a wrong or used-up key, no network, or a save failure — instead of one
  generic message, and a successful activation shows a "Welcome to Pro" moment.
- Count labels are grammatically correct in English and Spanish now ("1 clip",
  not "1 clips").

### Fixed

- A valid Pro license that couldn't be saved to the Keychain no longer shows a
  false "Welcome to Pro": activation confirms the license actually persisted
  before unlocking, and reports a clear error otherwise (direct-download Mac).
- Deleting your most-recent clip no longer leaves the menu-bar "Last copied"
  preview pointing at the clip you just removed.

## [0.3.1] - 2026-06-28

### Added

- Gancho Pro is now purchasable from the direct-download Mac app: the paywall
  opens the checkout and activates your license key on the spot (it previously
  showed "Pro is coming soon"). The Mac App Store build keeps using in-app
  purchase.

## [0.3.0] - 2026-06-28

### Added

- iPhone/iPad can now **back up and restore your history** from Settings → Your
  history, using the same portable `.ganchoarchive` format as macOS — so a
  backup made on one device imports on another. The export goes through the
  system file picker (save anywhere in Files), restore merges and de-dupes by
  content, and the archive is checksummed and never auto-uploaded.
- iPad **hardware-keyboard shortcuts**: with a Magic Keyboard or Smart Keyboard
  Folio attached, ⌘F focuses search, ⌘1–9 copy the first nine clips, and ⌘↩
  copies the selected clip (↑↓ already walk the list) — the macOS panel's
  keyboard-first flow now reaches iPad.
- A content-free **error log** ("Recent issues") in the Privacy Center on both
  macOS and iPhone/iPad: records operational failures — storage that wouldn't
  open, a sync that failed (macOS), a clip that couldn't load to copy or a
  backup that wouldn't restore (iOS) — with no clip text, a fixed in-memory
  cap, nothing persisted or uploaded, and a "Copy for support" button. Backed
  by a shared `DiagnosticLog`.

### Changed

- On iPad, the clip detail pane no longer stretches its action row and text
  edge-to-edge across a wide pane — it's capped to a readable column and
  centred, instead of reusing the iPhone sheet's full-width shape.

## [0.2.0] - 2026-06-28

### Added

- Shortcuts/Siri automation grew: the **Search Clips** intent now takes a
  **type filter** (Any / Text / Link / Code / Color / Image / Secret) and a
  **maximum results** count; a new **Ask Your Clipboard** intent answers a
  question grounded only in your history (on-device, secrets filtered out); and
  Search Clips, Copy Last URL, and Ask Your Clipboard are now offered as
  Siri/Spotlight app shortcuts (previously only Save Clipboard and Clear
  Sensitive were). The ask retrieval is shared with the in-app feature via a
  new `ClipboardQA` coordinator — no logic fork.
- Free taste of on-device AI: the first 25 text clips a free user copies get a
  real AI title (titles only — semantic search and OCR stay Pro). It is now
  surfaced where users can read it — the paywall's free column, the onboarding,
  and a one-time tappable nudge when it runs out — so the sample is a deliberate,
  enticing feature rather than a silent one.
- Settings → Pro shows how many clips Gancho is keeping for you.
- Keyboard shortcut cheat-sheet in the panel (press ⌘/ or the footer "?"):
  surfaces the power shortcuts the footer can't fit — ⌘P pin, ⌘S snippet,
  ⌥⏎ paste-plain, ⌘1-9 quick-paste.
- In-panel capture notice: when capture is paused (Private Mode), off (no
  clipboard access), or paused while screen sharing, the panel now says so —
  with a one-tap Resume / Fix — so a copy that doesn't appear reads as
  "paused", not "broken".
- Onboarding now points to the menu-bar home and offers a "Show in Dock"
  toggle, so a Dock-less app stays discoverable even if you forget the shortcut.
- A first-run welcome on iPhone/iPad explains Gancho's novel capture model up
  front — there's no background clipboard watching, so it walks through the
  three ways to save (the Paste button, the share sheet, and Shortcuts/Action
  Button) before dropping you on an empty list.
- macOS app icon — the Gancho hook mark.
- Release automation foundation: version-sync checks, a tagged GitHub Release
  workflow, macOS app ZIP packaging, artifact QA, and GitHub Pages deployment.

### Changed

- More generous free tier: 30-day / 2,000-item history (was 7-day / 500), and
  15 pins across 3 boards (was 10 pins, 1 board) — the free plan is the
  distribution engine, so it should feel complete on its own.
- The Library shows a live used/limit count next to Boards and Snippets for
  free users, and the Pro footer escalates (neutral → "almost full" → "limit
  reached"), so the upsell forewarns instead of ambushing at the ceiling.
- Retention settings now explain how the windows stack: a per-type limit
  overrides the global one, and a callout makes clear that detected secrets
  always follow the shorter "Sensitive items" limit — even when history is set
  to keep everything longer — so "Forever" never silently keeps a password.
- The "Never capture from these apps" denylist gains an "Add a running app…"
  picker (no need to know an app's bundle identifier) plus a format hint, so
  the feature is usable without hunting for bundle ids.
- The panel's Smart Paste menu now states the rewrites run on your Mac and
  nothing leaves the device — the reassurance lands right where a privacy-
  conscious user hesitates.
- The snippet editor now explains how snippets work up front: type the keyword
  in the panel to insert one, and add `{field}` placeholders to fill in before
  pasting (previously the `{field}` hint only appeared after you'd typed one).
- Plainer snippet wording: "Save as snippet" / "Move to history" replace the
  jargon "Promote to Library" / "Remove from Library" (and the demote action no
  longer wears a destructive red trash icon — it doesn't delete anything).
- The panel's no-results state now offers a "Clear filters" button when a type
  or board filter is narrowing the list, replacing a hint that wrongly told you
  to "press esc to clear the search" (esc hides the panel).
- On iPhone/iPad, search and filters now show a context-aware empty state —
  "No clips match …" when a search misses, or "No clips in this filter" with a
  Clear filters button — instead of the generic "Nothing captured yet" that
  appeared even mid-search.
- On iOS, Smart Paste actions sit one tap from the clip's Smart Actions section
  instead of inside a nested menu (Translate stays a submenu for its languages).
- Saving from the iOS share sheet now plays a success haptic when a clip lands —
  the sheet used to disappear with no confirmation that anything was captured.
- Accepting a board suggestion in the macOS peek now offers a one-tap Undo in
  the confirmation toast, so a mis-file is reversible without the board menu.
- Tapping an image clip on iOS opens it full screen with pinch- and
  double-tap-zoom (loading the full image, not the 340pt preview) — screenshots
  of small text are finally legible.
- The iOS keyboard's compact strip ends with a chevron that expands it to the
  full, searchable list — the control-bar toggle alone wasn't discoverable.
- The active filter and board pills now carry a checkmark and the "selected"
  accessibility trait, so the selection reads without relying on the accent
  colour alone (WCAG 1.4.1) and announces correctly in VoiceOver.
- Toasts that carry an action (e.g. Undo) now stay up long enough to read and
  reach the button instead of vanishing after the fire-and-forget 2.4s.
- "My Clipboard, Wrapped…" is now reachable from Settings, not just the
  menu-bar command, so the shareable stats card is actually discoverable.
- The iOS Recent Clips widget's empty state now says how to fill it ("Copy or
  share to Gancho") instead of a bare "Nothing yet".
- Distinct icon for "Smart paste" in the Intelligence list (it shared the
  "sparkles" glyph with "Smarter titles"), and the internal "Developer actions
  run" counter is now hidden from the release Privacy Center (DEBUG-only).
- Settings → Integrations now explains how to actually use the MCP server: a
  "Connect an agent" section with the CLI install + `claude mcp add` command,
  and a note that scope changes apply the next time `gancho mcp` starts —
  enabling the toggle alone never started a server.

### Fixed

- Data-loss warning: when the encrypted store can't open, Gancho now shows a
  prominent "History isn't being saved" banner (panel + iPhone/iPad history
  lists + Privacy Center) instead of silently running on a throwaway in-memory
  store and losing every clip on quit.
- On iOS, tapping Copy when a clip's content can't be loaded now says so
  ("Couldn't load this clip — try again") instead of silently leaving stale
  content on the pasteboard; a paused or failed sync gains a Retry button.
- On iPad, selecting a clip and then searching/filtering no longer leaves a
  ghost detail pane, and the history column shows an empty state when there's
  nothing to list.
- The Privacy Center's "Secrets masked" stat now counts detected sensitive
  clips (via a new `sensitiveCount()`) instead of a fragile match on the masked
  preview string, and it warns when storage is ephemeral (its counters would
  otherwise all read 0).
- The MCP access log shows relative timestamps ("3 hours ago") so yesterday's
  access is distinguishable from this minute's.
- "Add to board → New board…" from a clip now prompts for a name and files the
  clip into the board it creates, instead of silently making a board literally
  named "Board".
- Deleting a board now asks for confirmation first — the clips always stay in
  your history; only the board is removed.
- The iOS clip detail sheet now has a Done button — previously it could only be
  dismissed by dragging it down, with no visible affordance.
- The paywall and StoreKit test product copy no longer present iCloud sync as a
  shipped Pro benefit — it's marked "coming soon", and the Settings Pro note
  now separates what Pro unlocks today (unlimited history, pins, boards) from
  what arrives with launch (sync), so nobody upgrades expecting sync that isn't
  there yet.
- The direct-download paywall no longer dead-ends every license key on "That
  license key could not be activated" when the build ships without a signing
  key — it shows an honest "Pro is coming soon — purchases aren't open in this
  build yet" instead of a field that can never succeed.

## [0.1.0] - 2026-06-25

### Added

- Initial pre-release baseline for the privacy-first clipboard history system:
  macOS capture, encrypted local storage, FTS search, retention, paste-back,
  pins and boards, snippets, local MCP/CLI integration, and content-free
  telemetry boundaries.
- iPhone/iPad companion app with share, keyboard, widgets, App Intents,
  encrypted App Group storage access, and iCloud sync plumbing through
  `CKSyncEngine`.
- StoreKit entitlement plumbing and owner-gated launch surfaces for future
  public distribution.
- XcodeGen project, Swift 6 strict-concurrency package layout, localization,
  privacy, accessibility, and performance gates.
