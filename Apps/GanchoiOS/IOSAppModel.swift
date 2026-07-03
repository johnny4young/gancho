import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

@Observable
@MainActor
final class IOSAppModel {
    /// Raw loaded clips (recent page(s), a board, or search results). The kind
    /// filter is applied on top via `visibleClips` so it never disturbs the
    /// pagination offset.
    var captures: [ClipItem] = []
    /// Date-grouped sections (Pinned + Today/Yesterday/…) for the recent view,
    /// built from `visibleClips` via the shared `ClipSections` grouper.
    var sections: [ClipSectionGroup] = []
    private var reachedEnd = false
    private var isLoadingMore = false
    private static let pageSize = 100
    var hints = IntentionalPasteboardSource.ContentHints()
    /// The pasteboard `changeCount` of the last clip captured via the paste
    /// control. When it matches the current `hints.changeCount`, the copy on
    /// the clipboard has already been read — so the card says "Saved", not
    /// "not read yet". nil until the first capture this session.
    var lastCapturedChangeCount: Int?
    /// Transient feedback ("Saved" / "Already in your history").
    var saveNote: String?
    var query = ""
    var kindFilter: ClipContentKind?
    /// nil = "All clips"; otherwise the selected board (a higher axis than the
    /// kind filter). Boards are device-local collections of clips.
    var selectedBoardID: UUID?
    var boards: [Pinboard] = []
    /// Set by a widget deep link; `CaptureView` consumes it to push the clip.
    var deepLinkClipID: UUID?
    /// Cached, downsampled thumbnails for image clips (history rows + detail).
    let thumbnails: ClipThumbnailStore
    /// The "last clip ready to paste" Live Activity (Dynamic Island + lock
    /// screen); a no-op when the user hasn't enabled Live Activities.
    let clipActivity = ClipActivityController()

    /// Sync boundary: pull-to-refresh forces a cycle. The controller owns the
    /// engine lifecycle (make/start/stop/reset + the enabled flag); this model
    /// keeps only the status state below and its inline UI mapping. A
    /// `NoopSyncEngine` until the user is Pro on an iCloud-signed-in device; the
    /// adapter swaps in transparently — the pull-to-refresh contract is identical.
    let syncController: SyncController
    private(set) var syncStatus: SyncStatus = .idle
    /// The entitlement tier — readable so the Pro screen can show "free vs Pro"
    /// state, set only here from the purchase handler / debug toggle.
    private(set) var tier: UserTier = .free
    /// Bumped whenever a free-tier limit is hit, so the main screen can surface
    /// the Pro screen instead of letting a transient note dead-end the user.
    var proGateTick = 0
    private let purchases = StoreKitPurchaseHandler()

    /// Per-device on-device intelligence toggles (the iOS Intelligence screen).
    /// Device-local by design — they gate what runs HERE and never sync; the
    /// enriched results that ride the clip record (title/OCR/sensitive) do.
    var intelligence: IntelligencePreferences {
        didSet { intelligence.save(to: defaults) }
    }
    private let defaults = UserDefaults.standard

    init() {
        intelligence = IntelligencePreferences.load(from: defaults)
        // Resolve the capability handles once: feature code holds the facet
        // surface, only engine construction sees the concrete class.
        full = store as? any FullClipStore
        grdbForEngines = store as? GRDBClipboardStore
        thumbnails = ClipThumbnailStore(store: store)
        syncController = SyncController(
            store: store as? any SyncLocalStore,
            stateStoreURL: SharedStorageLocation.storeDirectory(
                appGroupID: SharedInbox.appGroupID
            ).appendingPathComponent("sync-state.plist"))
        // Sync status/idle mapping stays here (the views observe `syncStatus`);
        // the controller only drives the engine lifecycle and calls back.
        syncController.onStatus = { [weak self] status in
            guard let self else { return }
            let wasSyncing = self.syncStatus == .syncing
            self.syncStatus = status
            // A finished cycle may have pulled new boards/clips from iCloud.
            // Refresh the lists so they appear without having to background and
            // reopen the app.
            if wasSyncing, status != .syncing {
                await self.refreshBoards()
                await self.search()
            }
        }
        syncController.onIdle = { [weak self] in self?.syncStatus = .idle }
        purchases.onTierChange = { [weak self] tier in
            guard let self else { return }
            self.tier = tier
            self.syncController.configure(tier: self.tier)
        }
        Task {
            tier = await purchases.currentTier()
            #if DEBUG
                if DebugFlags.forcePro { tier = .pro }
            #endif
            syncController.configure(tier: tier)
        }
        // Log a data-loss-level storage failure eagerly (before any view reads
        // the diagnostics log), so the Privacy Center shows it the moment it
        // opens. The log isn't @Observable-tracked, so a later record wouldn't
        // refresh an open screen.
        recordStorageHealthIfNeeded()
    }

    /// Restores a prior Pro purchase (Universal Purchase on this Apple ID) and
    /// reconciles the tier + sync. Returns whether Pro is now active, so the Pro
    /// screen can confirm or explain "nothing to restore". A no-op for keys —
    /// the direct-download license lives on the Mac, not on this Apple ID.
    @discardableResult
    func restorePro() async -> Bool {
        let restored = (try? await purchases.restorePurchases()) ?? false
        tier = await purchases.currentTier()
        syncController.configure(tier: tier)
        return restored
    }

    #if DEBUG
        /// QA-only: flip Pro on/off without a purchase (iOS has no purchase UI
        /// and StoreKit testing doesn't span devices). Persists the flag and
        /// re-arms sync immediately. Compiled out of release builds.
        func setDebugForcePro(_ on: Bool) {
            UserDefaults.standard.set(on, forKey: "gancho-force-pro")
            Task {
                tier = on ? .pro : await purchases.currentTier()
                syncController.configure(tier: tier)
            }
        }

        /// QA-only: drop the saved CKSyncEngine state so the next cycle re-fetches
        /// every zone from scratch. Fixes a device whose token drifted ahead of
        /// what it actually stored (older records never re-arrive on an
        /// incremental fetch). Local rows are kept; remote records re-upsert.
        func resetSyncAndRepull() {
            syncController.reset(tier: tier)
        }
    #endif

    /// Telemetry — opt-out-first, buckets only; no sender when opted out so
    /// the SDK never initializes. Records the launch on construction.
    private let telemetry: TelemetryPipeline = {
        let optedOut = UserDefaults.standard.bool(forKey: "telemetry-opted-out")
        let sender: (any TelemetrySending)? =
            optedOut ? nil : TelemetryDeckSender(appID: GanchoTelemetryConfig.appID)
        let pipeline = TelemetryPipeline(sender: sender, optedOut: optedOut)
        pipeline.record(.appLaunched)
        return pipeline
    }()

    func forceSync() async {
        // Start = "run a sync cycle now" on the boundary; the CloudKit
        // adapter gives it real semantics during on-device verification.
        await syncController.forceSync()
        await refreshHints()
    }

    /// Pull the latest from iCloud (and push pending) when the app comes
    /// forward, so another device's recent clips appear without a pull-to-
    /// refresh — the engine only fetches on `start()` and gets no push to fetch
    /// on. The sync-status observer refreshes the list on settle. No-op off.
    func syncNow() {
        syncController.syncNow()
    }

    /// Foreground maintenance: purge expired history (the "auto-expires after
    /// 10 minutes" promise for secrets) and apply free-tier ceilings, then
    /// refresh the visible list. Mirrors the Mac's timer-driven pass — iOS has
    /// no retention-policy UI yet, so the policy loads its defaults until a
    /// settings surface exists.
    ///
    /// Throttled: foregrounding is frequent but the purge + tier pass (with
    /// its orphan-blob directory sweep) is not launch-critical, so it runs at
    /// most once per interval. The timestamp persists in UserDefaults so a
    /// relaunch doesn't reset the clock.
    private static let maintenanceInterval: TimeInterval = 10 * 60
    private static let lastMaintenanceKey = "ios-last-maintenance-at"

    func runMaintenance() async {
        guard let grdb = grdbForEngines else { return }
        if let last = defaults.object(forKey: Self.lastMaintenanceKey) as? Date,
            Date().timeIntervalSince(last) < Self.maintenanceInterval
        {
            return
        }
        let policy = RetentionPolicy.load(from: defaults)
        _ = try? await RetentionEngine(store: grdb).runPurge(policy: policy)
        // The purge tombstoned any synced victims; enqueue those deletions now
        // so they propagate immediately rather than at the next sync start().
        // Re-adding an already-pending deletion is a no-op in the engine, so
        // sweeping the whole tombstone table is safe.
        if syncController.isEnabled {
            let recordIDs = (try? await grdb.pendingDeletionRecordIDs()) ?? []
            let ids = recordIDs.compactMap { UUID(uuidString: $0) }
            if !ids.isEmpty { await syncController.engine.enqueueDeletion(ids: ids) }
        }
        _ = try? await TierEnforcement(store: grdb).enforce(tier: tier)
        defaults.set(Date(), forKey: Self.lastMaintenanceKey)
        await search()
    }

    /// Resolves a `gancho://clip/<id>` widget link: make sure the clip is in
    /// the list (so the detail destination finds it), then signal the view to
    /// navigate. A foreign or unknown link is ignored.
    func handleDeepLink(_ url: URL) {
        guard let id = WidgetClips.clipID(fromDeepLink: url) else { return }
        Task {
            if !captures.contains(where: { $0.id == id }),
                let item = try? await full?.item(id: id)
            {
                captures.insert(item, at: 0)
            }
            deepLinkClipID = id
        }
    }

    /// Refreshes home/lock-screen widgets after the recent list changes.
    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshBoards() async {
        guard let full else { return }
        boards = (try? await full.pinboards()) ?? []
    }

    /// Scope the history list to a board (or back to All clips) and refresh —
    /// the one path both the rail and the boards home go through.
    func selectBoard(_ id: UUID?) {
        selectedBoardID = id
        Task { await search() }
    }

    /// Total non-archived clips — the "All clips" count on the boards home.
    func clipCount() async -> Int {
        guard let full else { return 0 }
        return (try? await full.count()) ?? 0
    }

    /// How many clips a board holds — its count on the boards home.
    func clipCount(in board: Pinboard) async -> Int {
        guard let full else { return 0 }
        return (try? await full.count(inBoard: board.id)) ?? 0
    }

    /// Promote a clip to a reusable snippet — the peek's "Save as snippet".
    /// Honors the free-tier snippet limit and surfaces a note either way.
    func saveAsSnippet(_ item: ClipItem) async {
        guard let full else { return }
        let count = (try? await full.snippetCount()) ?? 0
        guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: tier == .pro) else {
            flashNote(String(localized: "Upgrade to Pro for more snippets"))
            return
        }
        try? await full.promoteToSnippet(id: item.id, title: nil)
        flashNote(String(localized: "Saved as snippet"))
        await search()
    }

    /// Creates a board and queues its metadata for sync, so it shows up on the
    /// user's other devices. The built-in Favorites board never counts against
    /// the free limit.
    func createBoard(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let full else { return }
        Task {
            let outcome = await BoardsController().createBoard(
                name: trimmed, filing: nil, store: full, engine: syncController.engine,
                isPro: tier == .pro,
                // Don't dead-end on a vanishing note: surface the Pro screen.
                onFreeLimit: { self.proGateTick += 1 },
                onAssigned: {})
            guard outcome != .blocked else { return }
            await refreshBoards()
        }
    }

    /// Create a board and file `item` into it in one step — the inline "+New
    /// board" path of the move-to-board sheet, where a clip is the reason the
    /// board is being made. Returns the new board's id so the sheet can refresh
    /// its checkmarks; nil if the board limit is hit or the create fails.
    @discardableResult
    func createBoard(named name: String, filing item: ClipItem) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let full else { return nil }
        let outcome = await BoardsController().createBoard(
            name: trimmed, filing: item, store: full, engine: syncController.engine,
            isPro: tier == .pro,
            onFreeLimit: { self.flashNote(String(localized: "Upgrade to Pro for more boards")) },
            onAssigned: {})
        guard case .created(let boardID) = outcome else { return nil }
        await refreshBoards()
        await search()
        return boardID
    }

    /// The boards a clip belongs to — drives the detail screen's checkmarks.
    func boardMembership(for item: ClipItem) async -> Set<UUID> {
        guard let full else { return [] }
        return (try? await full.boardIDs(forClip: item.id)) ?? []
    }

    /// Suggest the board this clip probably belongs to, by a semantic k-NN vote
    /// over how similar clips were filed (`BoardSuggester`). Only ever suggests;
    /// nil when the toggle is off, the clip is sensitive, there are no eligible
    /// user boards, or the neighborhood shows no clear home. 100% on-device.
    func suggestedBoard(for item: ClipItem) async -> Pinboard? {
        guard intelligence.autoBoard, !item.isSensitive, let full else { return nil }
        return await BoardSuggestionService().suggest(for: item, store: full)
    }

    /// Add or remove a clip from one board. Membership rides the clip's sync
    /// record, so the change propagates to other devices on the next cycle.
    func setBoardMembership(_ item: ClipItem, board: Pinboard, member: Bool) async {
        guard let full else { return }
        await BoardsController().setBoardMembership(
            item, board: board, member: member, store: full)
        await search()
    }

    /// Rename a user board and propagate the new name (no-op on Favorites — the
    /// store guards `isSystem`).
    func renameBoard(_ board: Pinboard, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let full else { return }
        Task {
            await BoardsController().renameBoard(
                board, name: trimmed, store: full, engine: syncController.engine)
            await refreshBoards()
        }
    }

    /// Delete a user board. When sync is on, tombstone it so the removal reaches
    /// the other devices; otherwise a plain local delete. Favorites is protected.
    func deleteBoard(_ board: Pinboard) {
        guard !board.isSystem, let full else { return }
        Task {
            await BoardsController().deleteBoard(
                board, store: full, engine: syncController.engine,
                syncEnabled: syncController.isEnabled)
            if selectedBoardID == board.id { selectedBoardID = nil }
            await refreshBoards()
            await search()
        }
    }

    /// The recent list (no query, no board) is the only date-grouped, paginated
    /// view; a board loads whole, search returns ranked results.
    var isGroupedView: Bool { query.isEmpty && selectedBoardID == nil }

    /// `captures` narrowed by the kind filter — what the list actually shows.
    var visibleClips: [ClipItem] {
        guard let kindFilter else { return captures }
        return captures.filter { $0.kind == kindFilter }
    }

    func search() async {
        if query.isEmpty {
            if let board = selectedBoardID, let full {
                captures = (try? await full.items(inBoard: board)) ?? []
                reachedEnd = true
            } else {
                captures = await loadRecentPage(offset: 0)
                reachedEnd = captures.count < Self.pageSize
            }
        } else {
            let kinds: Set<ClipContentKind>? = kindFilter.map { [$0] }
            captures =
                (try? await full?.search(
                    ClipSearchQuery(text: query, kinds: kinds, boardID: selectedBoardID),
                    limit: 50)) ?? []
            reachedEnd = true
        }
        rebuildSections()
    }

    /// Pinned-first then capture-time order, so the date buckets stay contiguous.
    private func loadRecentPage(offset: Int) async -> [ClipItem] {
        if let full {
            return (try? await full.recentForBrowse(offset: offset, limit: Self.pageSize)) ?? []
        }
        return (try? await store.items(offset: offset, limit: Self.pageSize)) ?? []
    }

    /// Append the next page as the list nears its end (infinite scroll). No-ops
    /// unless the grouped recent view has more to load.
    func loadMoreIfNeeded(_ item: ClipItem) async {
        guard isGroupedView, !isLoadingMore, !reachedEnd,
            let index = captures.firstIndex(where: { $0.id == item.id }),
            index >= captures.count - 20
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = captures.count
        let next = await loadRecentPage(offset: offset)
        guard isGroupedView, captures.count == offset else { return }
        captures.append(contentsOf: next)
        if next.count < Self.pageSize { reachedEnd = true }
        rebuildSections()
    }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    func rebuildSections() {
        sections = isGroupedView ? ClipSections.grouped(visibleClips, now: Date()) : []
    }

    /// 1-tap copy with haptic confirmation.
    func copyToPasteboard(_ item: ClipItem) async {
        guard let content = try? await store.content(for: item.id) else {
            // Silent before: the user tapped Copy, felt the (missing) result, and
            // pasted stale content. Say the load failed instead.
            flashNote(String(localized: "Couldn’t load this clip — try again."))
            diagnostics.record(
                String(localized: "Copy"),
                String(localized: "A clip’s content couldn’t be loaded."))
            return
        }
        switch content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .binary(let data, _):
            UIPasteboard.general.image = UIImage(data: data)
        case .fileReferences(let paths):
            UIPasteboard.general.string = paths.joined(separator: "\n")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Copying a clip is the truest "ready to paste" moment — it's on the
        // pasteboard now — so surface it on the Live Activity too.
        clipActivity.show(item, sync: ClipSyncBadge(syncStatus))
    }

    // MARK: - Smart paste (deterministic + on-device Apple Intelligence)

    private let smartPasteService = SmartPasteService()

    /// Available when the Smart Paste toggle is on. Deterministic actions such
    /// as PII redaction do not need Apple Intelligence, so model availability
    /// gates only model-backed rewrites and translations.
    var smartPasteAvailable: Bool { intelligence.smartPaste }

    /// Model-backed rewrites and translations require Apple Intelligence in
    /// addition to the user's Smart Paste opt-in.
    var smartPasteModelAvailable: Bool {
        intelligence.smartPaste && SmartPasteService.isAvailable
    }

    func smartPaste(_ text: String, action: SmartPasteAction) async -> String? {
        try? await smartPasteService.transform(text, action: action)
    }

    func smartTranslate(_ text: String, to language: String) async -> String? {
        try? await smartPasteService.translate(text, to: language)
    }

    // MARK: - Ask your clipboard (grounded on-device QA)

    /// A grounded answer plus the clips it was drawn from (for citing/copying).
    struct ClipboardAnswer: Identifiable, Sendable {
        let id = UUID()
        let answer: String
        let sources: [ClipItem]
    }

    var askAvailable: Bool { ClipboardQA.isAvailable }

    /// Ask-your-clipboard, via the shared `ClipboardQA` coordinator (the same one
    /// the Shortcuts `AskClipboardIntent` uses — retrieval + privacy filtering
    /// live there, not forked here). This layer only maps the outcome to the
    /// answer card's copy.
    func askClipboard(_ question: String) async -> ClipboardAnswer? {
        guard let full else { return nil }
        switch await ClipboardQA().answer(
            question: question, store: full, useSemantic: intelligence.semanticSearch)
        {
        case .unavailable:
            return nil
        case .noMatch:
            return ClipboardAnswer(
                answer: String(localized: "Nothing in your clipboard matches that."), sources: [])
        case .failed(let safe):
            return ClipboardAnswer(
                answer: String(localized: "Couldn’t answer that — try again."), sources: safe)
        case .answered(let text, let safe):
            return ClipboardAnswer(answer: text, sources: safe)
        }
    }

    func togglePin(_ item: ClipItem) async {
        guard let full else { return }
        try? await full.setPinned(id: item.id, !item.isPinned)
        // setPinned flagged the row for upload; enqueue pushes it now instead
        // of at the next sync start(). The engine builds the record from the
        // stored row, so only the id matters here.
        await syncController.engine.enqueue([item])
        await search()
    }

    func delete(_ item: ClipItem) async {
        if syncController.isEnabled, let full {
            try? await full.deleteForSync(id: item.id, now: .now)
            await syncController.engine.enqueueDeletion(ids: [item.id])
        } else {
            try? await store.delete(id: item.id)
        }
        await search()
        reloadWidgets()
    }

    private let source = IntentionalPasteboardSource()
    private let classifier = RuleClassifier()
    /// Durable store in the App Group container (shared family location);
    /// in-memory fallback keeps the app usable if the container is missing.
    let store: any ClipboardStore = {
        // Test hook: force the in-memory fallback so the "history isn't being
        // saved" path (and its diagnostics entry) is drivable by a UI test.
        if ProcessInfo.processInfo.arguments.contains("-force-ephemeral-store") {
            return InMemoryClipboardStore()
        }
        let directory = SharedStorageLocation.storeDirectory(
            appGroupID: SharedInbox.appGroupID)
        return
            (try? GRDBClipboardStore.encrypted(
                directory: directory,
                keychainAccessGroup: KeychainPassphraseStore.iosSharedAccessGroup))
            ?? InMemoryClipboardStore()
    }()

    /// Full first-party store surface, downcast once from `store`; nil on the
    /// in-memory fallback, in which case boards/search/snippets degrade to
    /// no-ops VISIBLY (`storageIsEphemeral` already drives the warning banner).
    /// Feature code reaches every capability through this instead of downcasting
    /// to the concrete class at each call site.
    let full: (any FullClipStore)?
    /// Narrow concrete handle kept ONLY to construct in-module engines
    /// (`GanchoArchive`, `RetentionEngine`, `TierEnforcement`) and to reach the
    /// sync-internal tombstone list — none of which belong in a client facet.
    private let grdbForEngines: GRDBClipboardStore?

    /// True when the durable store failed to open and the app fell back to
    /// memory — captures won't survive relaunch, so the list warns the user.
    var storageIsEphemeral: Bool { !store.isDurable }

    /// Content-free log of recent operational issues, shown in the Privacy
    /// Center for support — never any clip text.
    let diagnostics = DiagnosticLog()
    private var recordedStorageHealth = false

    /// Record the ephemeral-store condition once (the worst issue — data loss).
    func recordStorageHealthIfNeeded() {
        guard storageIsEphemeral, !recordedStorageHealth else { return }
        recordedStorageHealth = true
        diagnostics.record(
            String(localized: "Storage"),
            String(localized: "Couldn’t open secure storage — running in memory."))
    }

    /// Export a portable `.ganchoarchive` of the history (minus detector-flagged
    /// sensitive clips) to a temp dir for the system exporter to move into
    /// Files. Same format macOS reads/writes — device-to-device migration, no
    /// lock-in, never auto-uploaded.
    func makeBackupArchive() async -> URL? {
        guard let grdb = grdbForEngines else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-backup.ganchoarchive", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        // Detector-flagged secrets never leave the encrypted store via backup:
        // they carry a short expiry precisely so they don't persist, and an
        // archive in Files is permanent plaintext.
        guard
            (try? await GanchoArchive.export(
                from: grdb, to: dir, options: .init(excludeSensitive: true))) != nil
        else { return nil }
        return dir
    }

    /// Restore a `.ganchoarchive` (merge + dedupe by hash+device; checksummed,
    /// transactional). Returns the summary; refreshes the list on success.
    @discardableResult
    func restoreBackup(from url: URL) async -> GanchoArchive.RestoreSummary? {
        guard let grdb = grdbForEngines else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let summary = try? await GanchoArchive.restore(from: url, into: grdb) else {
            diagnostics.record(
                String(localized: "Backup"), String(localized: "A backup couldn’t be restored."))
            return nil
        }
        await search()
        return summary
    }

    /// Metadata-only refresh — safe on every activation, never alerts.
    func refreshHints() async {
        hints = await source.hints()
        await search()
    }

    /// The user-initiated read (system paste transparency applies).
    func saveClipboard() async {
        guard let capture = source.captureNow() else { return }
        await ingest(capture)
    }

    private func flashNote(_ text: String) {
        saveNote = text
        // The note is a transient overlay VoiceOver won't focus on its own; speak
        // it so a blind user gets the same confirmation a sighted one sees.
        UIAccessibility.post(notification: .announcement, argument: text)
        Task {
            try? await Task.sleep(for: .seconds(2))
            saveNote = nil
        }
    }

    /// Captures handed over by the share extension through the App Group.
    /// The extension already classified (tier 0); reuse its verdict.
    func drainSharedInbox() async {
        guard let inbox = SharedInbox.inAppGroup() else { return }
        for prepared in (try? inbox.drainPrepared()) ?? [] {
            await ingest(prepared.capture, precomputedKind: prepared.kind)
        }
    }

    /// UIPasteControl handoff: the system mediates the tap, so this path
    /// never shows an alert. Providers carry text, URLs, or images.
    func ingest(providers: [NSItemProvider]) {
        // Mark this copy as read (metadata only — the change counter), so the
        // capture card flips from "not read yet" to "Saved" until a new copy.
        lastCapturedChangeCount = UIPasteboard.general.changeCount
        Task { await refreshHints() }
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let png = (object as? UIImage)?.pngData() else { return }
                    Task { @MainActor in
                        await self?.ingest(
                            PasteboardCapture(
                                payload: .image(data: png, typeIdentifier: "public.png")))
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let text = object as? String, !text.isEmpty else { return }
                    Task { @MainActor in
                        await self?.ingest(PasteboardCapture(text: text))
                    }
                }
            }
        }
    }

    private func ingest(
        _ capture: PasteboardCapture, precomputedKind: ClipContentKind? = nil
    )
        async
    {
        let item = makeItem(from: capture, precomputedKind: precomputedKind)
        let content: ClipContent? =
            switch capture.payload {
            case .image(let data, let typeIdentifier):
                .binary(data: data, typeIdentifier: typeIdentifier)
            default:
                capture.textRepresentation.map { .text($0) }
            }
        // Dedupe-aware feedback: the store returns the EXISTING item when
        // the content hash matches — warn subtly instead of duplicating.
        let stored = try? await store.insert(item, content: content)
        if let stored { await syncController.engine.enqueue([stored]) }
        let isNew = stored?.id == item.id
        flashNote(
            isNew ? String(localized: "Saved") : String(localized: "Already in your history"))
        // Bounded like every other load — search() pulls the first page only.
        await search()
        reloadWidgets()
        // Surface the just-captured clip as "ready to paste" (masked if
        // sensitive) on the Dynamic Island / lock screen.
        if let stored { clipActivity.show(stored, sync: ClipSyncBadge(syncStatus)) }
        // Enrich only a genuinely new clip — a re-copy already carries its
        // title/OCR/embedding from the first capture.
        if isNew { enrich(item, content: content) }
    }

    /// On-device enrichment of a clip captured ON this iPhone — Apple
    /// Intelligence titles, OCR, and semantic embeddings — so an iOS capture is
    /// as rich as one synced from the Mac. Never blocks capture (utility
    /// priority); the shared `EnrichmentPlan` gates it (Pro + non-sensitive +
    /// per-stage toggles). Enriched fields that ride the clip record sync; the
    /// embedding stays device-local.
    private func enrich(_ item: ClipItem, content: ClipContent?) {
        let plan = EnrichmentPlan(
            content: content, kind: item.kind, isSensitive: item.isSensitive,
            hasTitle: !item.title.isEmpty, isPro: tier == .pro, preferences: intelligence)
        guard !plan.isEmpty, let full else { return }
        Task(priority: .utility) {
            await EnrichmentService().enrich(
                item, content: content, plan: plan, writeTitle: plan.runs(.title),
                store: full
            ) {
                await self.search()  // surface the new title without a manual refresh
            }
        }
    }

    private func makeItem(
        from capture: PasteboardCapture, precomputedKind: ClipContentKind? = nil
    ) -> ClipItem {
        switch capture.payload {
        case .image(let data, _):
            return ClipItem(
                kind: .image,
                preview: "Image (\(ByteSize.formatted(data.count)))",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
        default:
            let raw = capture.textRepresentation ?? ""
            let kind = precomputedKind ?? classifier.classify(raw)
            let text = ContentNormalizer.canonicalText(raw, kind: kind)
            let item = ClipItem(
                kind: kind,
                preview: String(text.prefix(120)),
                contentHash: ClipItem.hash(of: text, kind: kind),
                sourceAppBundleID: capture.sourceAppBundleID)
            // Intelligence toggle off ⇒ skip secret detection/masking. The
            // password-manager veto (Concealed/Transient) is separate, pre-read,
            // and always on.
            guard intelligence.detectSecrets else { return item }
            return SensitiveIngestionPolicy.decorate(
                item, finding: SensitiveDataDetector().detect(text), originalText: text)
        }
    }
}
