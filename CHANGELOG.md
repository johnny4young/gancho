# Changelog

All notable changes to Gancho are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
