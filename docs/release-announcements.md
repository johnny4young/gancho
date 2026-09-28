# Gancho release announcements

Ready-to-paste announcement texts for every published Gancho release, newest
first. One entry per release: a short post for X/Bluesky with its character
count stated, and for feature releases a Hacker News and a Reddit text. Every
text leads with the concrete thing that shipped and names the limits the
audience would find in five minutes anyway. Copy from here when posting; this
file is a working record, not the changelog.

Gancho: a local-first, encrypted clipboard history and snippet library for
Mac (iPhone and iPad apps in the repository, not distributed yet). Free and MIT
licensed; Pro is a one-time direct purchase. Site: https://gancho.app.

## v0.9.0 — 2026-09-28

The Mac history panel was redesigned: one toolbar, rows that show what each clip is, a peek with a hero card and an action dock, and nothing new that reads, stores or sends anything.

![The redesigned Gancho panel: one toolbar, kind-coloured rows and a link peek with an action dock](https://gancho.app/assets/v0.9.0-release.png)

### X / Bluesky — 274 characters

Gancho 0.9.0 (macOS): the clipboard panel redesigned. One toolbar, rows that show what each clip is, a peek with a hero card and an action dock, ⌘G gallery, optional ambient colour. Links are parsed on the Mac, never fetched. Free, MIT, encrypted history. https://gancho.app

### Hacker News

**Title:** `Show HN: Gancho 0.9 – open-source, local-first clipboard manager for Mac, panel redesigned`

**Text:**

Gancho is a clipboard history and snippet library for macOS (with iPhone/iPad apps that are not distributed yet). Everything stays on the machine: SQLCipher-encrypted history, no servers of ours, optional sync through the user's own private iCloud database. 0.9.0 is the first release since the panel was rebuilt, so this is mostly about the part you look at all day.

The design constraint that shaped it: the panel must never make a network request because of what you copied. So a copied link gets a hero card with its host and full URL parsed locally, no favicon, no metadata fetch. The row tile shows the host's initial instead. Same for images: the peek shows Live-Text regions from on-device OCR, nothing leaves the Mac.

What changed: three stacked toolbar rows became one (boards, type filters as glyph chips, source-app filter, saved filters). Rows carry identity in the tile: the real colour swatch, the image thumbnail, syntax-tinted code. The peek closes with an action dock (Paste, Paste plain, Copy text from image, Pin, Board) with keys, and Return still pastes. Motion sits behind one Reduce Motion policy, so every animation is instant when the OS says so. Two optional layouts are remembered: ⌘G shows the history as a grid of cards, and an ambient colour lays a faint field of the selected clip's colour under the list, never while Reduce Transparency or Increase Contrast is on.

Also in this release: the Library's snippet editor no longer loses the body you typed when a sync finishes or you click another snippet (it auto-saves on leaving, plus ⌘S), and the peek hides its hero and derived content in Private Mode.

Limits, honestly: the DMG is macOS 15.4+ and macOS only; the iOS apps exist in the repo but have no distribution path yet. Liquid Glass needs macOS 26; on 15.4 the panel uses an opaque fallback that I have not exercised on a Sequoia Mac for this redesign. Sync requires Pro and the signed two-Mac matrix is still pending, so treat sync as unverified. The screenshots on the site are captured by the app's own UI tests with synthetic clips, so no real clipboard content can appear in them; that is also why the footer in them says "Paused".

MIT licensed. Source, changelog and the release note are on GitHub; the DMG and the Homebrew cask ship the same notarized bytes.

### Reddit (r/macapps, r/opensource)

**Title:** `Gancho 0.9.0 — open-source clipboard manager for Mac, panel redesigned (local-first, encrypted, no network from your clipboard)`

**Text:**

Gancho keeps your clipboard history encrypted on your Mac and never sends what you copy anywhere. 0.9.0 redesigns the panel:

- One toolbar instead of three: boards, type filters, source app, saved filters.
- Rows show what each clip is: a link's host initial, the real colour swatch, the image thumbnail, code as code.
- The peek opens with a hero card (link host and URL parsed locally, never fetched; image with Live-Text regions; colour band; text) and closes with an action dock: Paste, Paste plain, Copy text from image, Pin, Board.
- ⌘G shows the history as a grid of cards; an optional ambient colour tints the panel with the selected clip's colour. Both remembered, both off by default.
- Everything respects Reduce Motion.
- Snippet drafts in the Library survive refreshes and save when you move on.

Limits: macOS 15.4+ only (iOS apps not distributed yet), Liquid Glass needs macOS 26, and cross-device sync is still unverified on a two-Mac matrix. Free and MIT; Pro is a one-time purchase for higher limits, on-device AI and iCloud sync.

### Platform notes

> macOS only. The iPhone and iPad apps are in the repository but have no App Store or TestFlight distribution yet. The macOS 15.4 fallback without Liquid Glass and the two-Mac sync matrix have not been exercised on the released bytes.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.9.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.8.4 — 2026-09-25

Every path that hands a clip to another app now treats JWTs, card numbers and secrets as protected, even when a clip lost its sensitivity flag.

### X / Bluesky — 274 characters

Gancho 0.8.4 (macOS): protected clips stay protected on every way out. Drag-out, the menu bar, the iOS keyboard, sharing and exports re-check a clip before handing it over; shares and iCloud changes only advance once saved; the panel keeps your selection. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.8.4
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.8.3 — 2026-09-20

Free local OCR from saved images or a screen region, read in place in the panel, and the first direct-download Pro purchase that ships without any signing key in the app.

![Text recognized from an image beside the panel preview](https://gancho.app/assets/screen-ocr-peek.png)

### X / Bluesky — 266 characters

Gancho 0.8.3 (macOS): copy text out of images or a screen region with free, local OCR, read in place in the panel. Pro on the direct download ships with no signing key in the app: Lemon Squeezy is the authority, 30 days offline grace. macOS 15.4+. https://gancho.app

### Hacker News

**Title:** `Gancho 0.8.3 – free on-device OCR for your clipboard, and a Pro licence with no signing key in the app`

**Text:**

Two things in this release of Gancho, an open-source, encrypted clipboard manager for Mac.

First, OCR. Copy text from any saved image, or select a screen region with a shortcut, and the recognized text shows beside the image in the panel's peek, one selectable region per line. It runs on Vision, locally, and saves nothing unless you ask: the recognized text is a transient review, not a new clip, and a recognized secret is never copied automatically. Automatic searchable-image indexing stays a Pro feature; the manual path is free.

Second, the licence. The direct-download build could not sell Pro before, because issuing an entitlement meant carrying a private signing key in the app, which anyone can extract. 0.8.3 makes Lemon Squeezy the entitlement authority instead: the app records the activation it issued, re-confirms it about weekly, tolerates 30 days offline, and can release a Mac's seat from Settings. A merely-valid key from someone else's Lemon Squeezy store used to pass the public License API; activation now requires the answer to name the live Gancho store and product.

Also: saved encrypted search filters, combining several text clips with a chosen separator before copying, visual Library cards, and the floor moved to macOS 15.4 (the on-device model tier still needs macOS 26). Large histories got cheaper: semantic search measured about 2× faster on a 100,000-clip test history, and applying a 400-record sync page about 2× faster.

Limits: cross-device sync acceptance on the signed build and real Sequoia testing were still pending at release, and the release note says so.

### Reddit (r/macapps, r/opensource)

**Title:** `Gancho 0.8.3 — free local OCR from images and screen regions in an open-source clipboard manager`

**Text:**

- Copy text from a saved image or a screen region; recognized locally with Vision, reviewed in the panel, saved only if you ask.
- Combine several text clips with a separator before copying; save encrypted search filters; visual Library cards.
- Pro on the direct download: buy through Lemon Squeezy, paste the key, 30 days offline grace, move the licence between Macs. No signing key ships in the app.
- Floor is now macOS 15.4; on-device AI features need macOS 26.
- ~2× faster semantic search at 100k clips.

Free and MIT. Cross-device sync was still unverified on real hardware at release.

### Platform notes

> macOS 15.4+. On-device model features (titles, Smart Paste rewrites, Translate, Ask) need macOS 26. iOS apps not distributed.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.8.3
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.8.2 — 2026-07-25

A filter that finds nothing no longer looks like an empty history, and the strings the automated check could not see are translated.

### X / Bluesky — 279 characters

Gancho 0.8.2 (macOS): a filter with no matches now says so and keeps Clear filters reachable (VoiceOver included) instead of showing the first-run message; Spanish strings the automated check missed are done; encrypted storage and input dependencies refreshed. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.8.2
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.8.1 — 2026-07-22

A lifetime Pro purchase stays unlocked through StoreKit's transient entitlement gaps, and CloudKit recovery decisions became deterministic.

### X / Bluesky — 225 characters

Gancho 0.8.1 (macOS): a lifetime Pro purchase no longer relocks when StoreKit briefly omits it from current entitlements; sync recovery and pending-work planning moved into deterministic, tested components. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.8.1
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.8.0 — 2026-07-20

Import a Maccy archive or CSV with a preview before anything is written, and give local AI clients least-privilege access to your clipboard.

![Gancho 0.8.0 on macOS](https://gancho.app/assets/v0.8.0-release.png)

### X / Bluesky — 278 characters

Gancho 0.8.0 (macOS): import your Maccy or CSV history with a dry-run preview (protected rows rejected, deduplicated in one transaction, exact totals). MCP clients now need an expiring, revocable grant with a board/time scope. The panel resizes and remembers. https://gancho.app

### Hacker News

**Title:** `Gancho 0.8 – switch clipboard managers with a preview, and least-privilege MCP access to your clipboard`

**Text:**

Gancho is an open-source, encrypted clipboard manager for Mac with a local MCP server so AI clients on your machine can search your clipboard. 0.8 is about two trust boundaries.

Switching from another manager: the Mac app accepts Maccy archives and CSV, previews what would be imported without writing, rejects protected or malformed rows, deduplicates in one transaction, supports cancellation and reports exact imported and skipped totals. Raycast is deliberately not a source: it does not document a portable export format, and I am not going to inspect its private data.

MCP: every client process now needs an expiring, revocable grant with an explicit board/time context and a read-only or read-write policy. Authorization is re-read on every call, filters fail closed, sensitive clips are excluded, and the access ledger stores metadata only.

Also: the Privacy Center shows content-free per-app capture and reuse totals from a bounded on-device receipt (13 rolling months, never synced), and the panel resizes from its edges, remembers its geometry and scales text.

This is also the first release built as a Developer ID, notarized DMG with a production CloudKit profile and a signed Sparkle feed. Limits: a fresh public install stays Free and its Pro-only sync transport is disabled until secure activation exists (that came in 0.8.3).

### Reddit (r/macapps)

**Title:** `Gancho 0.8.0 — import your Maccy history with a preview; local AI clients get scoped, revocable clipboard access`

**Text:**

- Import Maccy archives or CSV with a dry run first; protected rows are rejected, duplicates merged, totals reported.
- MCP clients need an expiring, revocable grant scoped to boards and time, read-only or read-write.
- Privacy Center shows per-app capture and reuse totals, content-free, never synced.
- The panel resizes from its edges and remembers.
- First notarized DMG with auto-update.

Open source (MIT), encrypted locally, no servers. Sync stays off on a fresh public install in this version.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.8.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.7.0 — 2026-07-16

Select several clips at once on the Mac and act on all of them, and find snippets from Spotlight without ever indexing a secret.

![Gancho 0.7.0 on macOS](https://gancho.app/assets/v0.7.0-release.png)

### X / Bluesky — 272 characters

Gancho 0.7.0 (macOS): shift/⌘-click to select several clips, then stack, file or delete them with one Undo; drag a file selection to Finder. Snippets and pins in Spotlight with secrets redacted first. Boards load in pages; search p95 under 30 ms at 10k. https://gancho.app

### Hacker News

**Title:** `Gancho 0.7 – multi-select for your clipboard history, and Spotlight indexing that cannot leak a secret`

**Text:**

Gancho 0.7 (open-source, encrypted clipboard manager for Mac) adds multi-selection to the history panel: Shift for a range, Command for a non-contiguous set, then one action bar to add the selection to the paste stack, file it into a board or delete it with a shared Undo. When every selected item is a file reference, dragging any row sends the de-duplicated file set to Finder.

The part I spent the most care on is Spotlight. Snippets and pinned clips are now searchable system-wide on Mac, iPhone and iPad. Only the curated Library is donated: raw history, secret and masked-credential clips and expiring clips never reach the index, and even inside an ordinary snippet, key- and card-shaped text is replaced with `[redacted]` before donation. A toggle removes everything at once; if that removal fails, a content-free entry lands in Recent issues instead of failing silently.

Same rule for the on-device model: text passes a deterministic structural redaction before it reaches any prompt, so a summary can no longer echo an API key hidden in an otherwise normal clip. The prompts live in a versioned catalog with an opt-in evaluation suite that fails if a change weakens this.

Numbers: boards now load in pages, so a board with thousands of clips opens like a small one; measuring semantic retrieval at 10k and 100k vectors showed the final sort dominating, and a bounded selection dropped the 10k search's 95th percentile to under 30 ms.

### Reddit (r/macapps)

**Title:** `Gancho 0.7.0 — multi-select and batch actions in the clipboard panel, snippets in Spotlight`

**Text:**

- Shift/⌘-click selection with one action bar: stack, board, delete, one Undo.
- Drag a selection of files straight to Finder.
- Snippets and pins in Spotlight; secrets never indexed, key-shaped text redacted first.
- Boards load in pages; semantic search faster at scale.
- The menu-bar icon always comes back if the helper dies.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.7.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.6.0 — 2026-07-14

Filter by the app a clip came from, edit titles and text, preview anything with ⌘Y, transform text on every device, and drag clips straight out of the panel.

### X / Bluesky — 272 characters

Gancho 0.6.0 (macOS + iOS): filter history by source app, edit clip titles and text, ⌘Y full read-only preview, offline text transforms (Title Case, sort lines, URL encode, SHA-256), boards with colour and emoji, drag clips out of the panel, ⌘B to file. https://gancho.app

### Hacker News

**Title:** `Gancho 0.6 – source-app filter, editable clips and offline text transforms in an open-source clipboard manager`

**Text:**

0.6 is the release where Gancho's history became something you shape rather than just search. On Mac, iPhone and iPad you can filter by the app a clip came from (a content-free filter that composes with text, kind, board and date), edit a clip's title and, for text-like clips, its content through an explicit Save/Cancel flow that only syncs after the durable local write succeeds.

A "Transform" menu applies pure, deterministic operations (Title Case, collapse spaces, sort and dedupe lines, URL encode/decode, SHA-256) and shows the result before you paste or copy; the original clip is never modified. ⌘Y opens a full read-only preview of text, code, colours, rich text, images or file references without writing temporary Quick Look files; sensitive and masked clips are refused before their payload is read.

Smaller things that add up: after a clip is reused a third time, Gancho offers once to save it as a snippet; boards get a colour and an emoji that follow them across devices; any row drags out of the panel; ⌘↑ recalls recent searches; results blend text relevance with your habits; ⌘B files the selected clip into a board without the mouse.

Under the hood the FTS index now accelerates short prefixes, and the 100k-clip performance gate measures cold startup and five warm rounds separately instead of one favourable query sequence.

### Reddit (r/macapps)

**Title:** `Gancho 0.6.0 — filter by source app, edit clips, transform text offline, drag clips out of the panel`

**Text:**

- Source-app filter on Mac, iPhone and iPad.
- Edit titles and text; changes sync only after the local write lands.
- Transform menu: Title Case, sort/dedupe lines, URL encode/decode, SHA-256, all offline.
- ⌘Y full preview; ⌘B file into a board; ⌘↑ recent searches.
- Boards with colour and emoji; drag clips out of the panel.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.6.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.5.0 — 2026-07-08

The free tier grew to one year and 10,000 items, the paste stack became visible, and the direct-download build finally saves history.

### X / Bluesky — 268 characters

Gancho 0.5.0 (macOS): the free history window grows from 30 days / 2,000 items to 1 year / 10,000. The paste stack is visible in the panel footer (⌥⌘Return to queue), clips about to expire show a countdown, and the notarized build now saves history. https://gancho.app

### Platform notes

> Before 0.5.0 the Developer ID build stored its encryption key in iCloud Keychain, which that build is not entitled to use, so history silently stayed in memory. 0.5.0 keys the store locally instead.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.5.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.4.1 — 2026-07-06

iCloud sync reacts to changes on other devices, and AI titles, OCR text and board membership travel with clips.

### X / Bluesky — 276 characters

Gancho 0.4.1 (macOS + iOS): a clip copied on one device shows up on the others without a manual refresh; AI titles, OCR text and board membership sync reliably; the type filter no longer stalls scrolling; content-free sync issues land in the Privacy Center. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.4.1
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.4.0 — 2026-07-06

Encrypted iCloud sync carries a clip's on-device enrichment with it, 18 offline Dev Actions, and a secret detector that knows eight more credential shapes.

### X / Bluesky — 280 characters

Gancho 0.4.0: encrypted iCloud sync (Pro) now carries AI titles and OCR text across devices. 18 new offline Dev Actions. The secret detector knows 8 more shapes (Slack webhooks, OpenAI keys, PGP blocks); exports skip sensitive clips and block formula injection. https://gancho.app

### Hacker News

**Title:** `Gancho 0.4 – clipboard exports that cannot run as spreadsheet formulas, and a detector for eight more credential shapes`

**Text:**

Two security changes in this release of Gancho (open-source, encrypted clipboard manager for Mac and iOS) that other clipboard tools might want to copy.

Exports: a CSV export of your clipboard history is a formula-injection vector. A clip that starts with `=`, `+`, `-` or `@` runs as a formula when the file is opened in Excel, Numbers or Sheets. 0.4.0 guards those cells. Backups and exports also leave detector-flagged sensitive clips out by default, because a plaintext export is permanent.

Detection: the secret detector now recognizes Slack webhooks, Google API keys, GCP service-account JSON, OpenAI keys, npm tokens, Azure connection strings, `Authorization: Bearer` headers and PGP private-key blocks. Detector-flagged clips refuse to be pinned, so a secret cannot be exempted from the short sensitive-items retention window by accident.

Features: encrypted iCloud sync (Pro) now carries the on-device enrichment a clip earned, so an AI title or OCR text produced on one device shows up on the others; 18 new offline, deterministic Dev Actions on text and code (slugify, epoch and ISO-8601 conversion, number bases and more); the CLI gained `boards`, `pin` and `unpin`; a manual language picker; an About screen.

### Reddit (r/macapps, r/privacy)

**Title:** `Gancho 0.4.0 — encrypted iCloud sync carries AI titles and OCR; exports guard against formula injection`

**Text:**

- Sync (Pro, end-to-end encrypted) now carries a clip's on-device titles and OCR text.
- 18 offline Dev Actions on text and code.
- Secret detector: 8 more credential shapes; flagged clips cannot be pinned.
- Exports skip sensitive clips by default and neutralize spreadsheet formulas.
- ⌘V pastes the selected clip; delete has a working Undo.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.4.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.3.2 — 2026-06-29

An Undo window for deleted clips on the Mac, a Pro screen on iPhone and iPad, and VoiceOver announcements for confirmations.

### X / Bluesky — 267 characters

Gancho 0.3.2: deleting a clip on the Mac now has an Undo window; iPhone and iPad get a Gancho Pro screen; VoiceOver announces confirmations; the sync indicator reads “Synced · N ago”; a licence that cannot reach the Keychain no longer looks active. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.3.2
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.3.1 — 2026-06-28

Gancho Pro became purchasable from the direct-download Mac app.

### X / Bluesky — 138 characters

Gancho 0.3.1 (macOS): Gancho Pro can now be purchased from the direct-download app's paywall. Local history stays free. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.3.1
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.3.0 — 2026-06-28

iPhone and iPad can back up and restore history, iPad gets hardware-keyboard shortcuts, and a content-free error log lands in the Privacy Center.

### X / Bluesky — 216 characters

Gancho 0.3.0: iPhone and iPad back up and restore your encrypted history from Settings; iPad hardware-keyboard shortcuts; a content-free “Recent issues” log in the Privacy Center on both platforms. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.3.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.2.0 — 2026-06-28

A more generous free tier, Shortcuts and Siri search, a taste of on-device AI for free users, and the release automation that every later version rides on.

### X / Bluesky — 260 characters

Gancho 0.2.0: free tier grows to 30 days / 2,000 items; the Search Clips intent takes a query for Shortcuts and Siri; the first 25 text clips get an on-device AI title for free; a ⌘/ shortcut cheat-sheet in the panel; tagged GitHub releases. https://gancho.app

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.2.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)

## v0.1.0 — 2026-06-27

The initial baseline: macOS capture, encrypted local storage, full-text search, retention, paste-back, pins, boards, snippets, and a local MCP/CLI, plus an iPhone/iPad companion.

### X / Bluesky — 274 characters

Gancho 0.1.0, first release: a privacy-first clipboard manager for Mac with encrypted local history, full-text search, retention, paste-back, pins, boards, snippets and a local MCP server + CLI. iPhone/iPad companion with share, keyboard and widgets. MIT. https://gancho.app

### Platform notes

> Pre-release baseline. The macOS ZIP of this version was unsigned; signed and notarized DMGs start with 0.8.0.

### Links

- Release: https://github.com/johnny4young/gancho/releases/tag/v0.1.0
- Site: https://gancho.app
- `brew tap johnny4young/tap && brew install --cask gancho`
- Direct download: signed, notarized DMG on the release page (macOS 15.4+)
