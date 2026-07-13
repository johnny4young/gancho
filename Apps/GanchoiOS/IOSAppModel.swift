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

// IOSAppModel mirrors the iOS composition root; split persistence/sync/history
// wiring separately so this SwiftLint adoption stays behavior-preserving.
// swiftlint:disable type_body_length

@Observable
@MainActor
final class IOSAppModel {
    // swiftlint:enable type_body_length
    /// The search + list state (captures, sections, query, filters, paging,
    /// grouping) lifted into `HistoryListViewModel` so its logic is unit-testable
    /// — the iOS analog of macOS's `PanelSearchModel`. This model owns one and
    /// forwards `captures`/`sections`/`query`/… to it, so the views and their
    /// bindings are unchanged.
    @ObservationIgnored lazy var history = HistoryListViewModel(
        source: HistoryStoreSource(store: store, full: full))
    /// Raw loaded clips — see `HistoryListViewModel.captures`.
    var captures: [ClipItem] {
        get { history.captures }
        set { history.captures = newValue }
    }
    /// Date-grouped sections — see `HistoryListViewModel.sections`.
    var sections: [ClipSectionGroup] {
        get { history.sections }
        set { history.sections = newValue }
    }
    var hints = IntentionalPasteboardSource.ContentHints()
    /// The pasteboard `changeCount` of the last clip captured via the paste
    /// control. When it matches the current `hints.changeCount`, the copy on
    /// the clipboard has already been read — so the card says "Saved", not
    /// "not read yet". nil until the first capture this session.
    var lastCapturedChangeCount: Int?
    /// Transient feedback ("Saved" / "Already in your history").
    var saveNote: String?
    @ObservationIgnored private var saveNoteTask: Task<Void, Never>?
    /// One non-modal curation action produced at the exact third successful use.
    /// Metadata only; exact-threshold dismissal needs no persisted state.
    var reuseSuggestion: ReuseSuggestion?
    /// Search field text — see `HistoryListViewModel.query`.
    var query: String {
        get { history.query }
        set { history.query = newValue }
    }
    /// Active kind filter — see `HistoryListViewModel.kindFilter`.
    var kindFilter: ClipContentKind? {
        get { history.kindFilter }
        set { history.kindFilter = newValue }
    }
    /// nil = "All clips"; otherwise the selected board (a higher axis than the
    /// kind filter). Board identity and membership sync when iCloud is enabled.
    var selectedBoardID: UUID? {
        get { history.selectedBoardID }
        set { history.selectedBoardID = newValue }
    }
    /// nil = all apps; otherwise the source-app filter selected in history.
    var selectedSourceAppBundleID: String? {
        get { history.selectedSourceAppBundleID }
        set { history.selectedSourceAppBundleID = newValue }
    }
    /// Content-free recent app options and aggregate counts.
    var sourceApps: [ClipSourceApp] { history.sourceApps }
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
    let telemetry: TelemetryPipeline
    private(set) var telemetryConsent: TelemetryConsent {
        didSet {
            telemetryConsent.save(to: defaults)
            telemetry.setConsent(telemetryConsent)
            if telemetryConsent != .notAsked {
                isTelemetryConsentPromptPresented = false
            }
        }
    }
    var isTelemetryConsentPromptPresented = false

    #if DEBUG
        /// UI-test-only consent pin (see init). Nil when the launch argument
        /// is absent or malformed, so a normal launch reads real defaults.
        private static var uiTestTelemetryConsentOverride: TelemetryConsent? {
            guard let index = CommandLine.arguments.firstIndex(of: "-telemetry-consent"),
                CommandLine.arguments.indices.contains(index + 1)
            else { return nil }
            return TelemetryConsent(rawValue: CommandLine.arguments[index + 1])
        }
    #endif

    /// CloudKit stays at the platform composition root; GanchoAppCore receives
    /// only this transport-neutral factory closure.
    private static let syncEngineFactory: SyncController.EngineFactory = {
        store, tier, iCloud, entitled, state, onStatus, diagnostics, pollState in
        SyncEngineFactory.make(
            store: store,
            tier: tier,
            iCloudAvailable: iCloud,
            hasCloudKitEntitlement: entitled,
            stateStore: state,
            onStatus: onStatus,
            diagnostics: diagnostics,
            pollStateStore: pollState)
    }

    init() {
        let forceFreeTier = CommandLine.arguments.contains("-force-free-tier")
        intelligence = IntelligencePreferences.load(from: defaults)
        var telemetryConsent = TelemetryConsent.load(from: defaults)
        #if DEBUG
            // UI-test hook: `-telemetry-consent <notAsked|enabled|disabled>`
            // pins the state so consent-flow tests don't depend on whatever a
            // previous run left in the runner's real defaults.
            if let override = Self.uiTestTelemetryConsentOverride {
                telemetryConsent = override
            }
        #endif
        self.telemetryConsent = telemetryConsent
        telemetry = TelemetryPipeline(
            consent: telemetryConsent,
            senderFactory: { TelemetryDeckSender(appID: GanchoTelemetryConfig.appID) })
        // Resolve the capability handles once: feature code holds the facet
        // surface, only engine construction sees the concrete class.
        full = store as? any FullClipStore
        grdbForEngines = store as? GRDBClipboardStore
        thumbnails = ClipThumbnailStore(store: store)
        syncController = SyncController(
            store: store as? any SyncLocalStore,
            stateStoreURL: SharedStorageLocation.storeDirectory(
                appGroupID: SharedInbox.appGroupID
            ).appendingPathComponent("sync-state.plist"),
            hasCloudKitEntitlement: { CloudKitEntitlements.currentTaskAllowsSync() },
            makeEngine: Self.syncEngineFactory)
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
        // Content-free sync-trouble trail → the Privacy Center's "Recent issues"
        // (fetched records that fail to decode/apply, non-transient save errors).
        syncController.diagnostics = diagnostics
        purchases.onTierChange = { [weak self] tier in
            guard !forceFreeTier, let self else { return }
            self.tier = tier
            self.syncController.configure(tier: self.tier)
        }
        Task {
            if forceFreeTier {
                tier = .free
            } else {
                tier = await purchases.currentTier()
                #if DEBUG
                    if DebugFlags.forcePro { tier = .pro }
                #endif
            }
            syncController.configure(tier: tier)
        }
        // Log a data-loss-level storage failure eagerly (before any view reads
        // the diagnostics log), so the Privacy Center shows it the moment it
        // opens. The log isn't @Observable-tracked, so a later record wouldn't
        // refresh an open screen.
        recordStorageHealthIfNeeded()
        seedSampleClipsIfRequested()
        seedSampleBoardsIfRequested()
        seedSourceAppsIfRequested()
        seedReuseSuggestionIfRequested()
        telemetry.record(.appLaunched)
        #if DEBUG
            if CommandLine.arguments.contains("-show-telemetry-consent") {
                requestTelemetryConsentAfterFirstValue()
            }
        #endif
    }

    /// UI-test hook: seed a few KNOWN synthetic clips through the normal capture
    /// pipeline so the history list is deterministic for the automated flows.
    /// Strictly gated on BOTH the launch arg and the ephemeral store, so a real
    /// user's durable history is never touched and a normal launch (no arg) is a
    /// byte-for-byte no-op. The seed content is synthetic and non-secret.
    private func seedSampleClipsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-sample-clips"),
            storageIsEphemeral
        else { return }
        Task {
            for capture in [
                PasteboardCapture(text: "seed alpha"),
                PasteboardCapture(text: "https://seed.example/one"),
                PasteboardCapture(text: "seed beta")
            ] {
                await ingest(capture)
            }
        }
    }

    /// UI-test hook: seed known boards into a throwaway SQLite store so the
    /// appearance flow exercises the real durable write and refresh path. Both
    /// arguments are required; a normal launch can never touch user storage.
    private func seedSampleBoardsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-sample-boards"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full
        else { return }
        Task {
            for index in 1...PinLimits.freeMaxPinboards {
                _ = try? await full.createPinboard(
                    name: "Seed board \(index)", sfSymbol: "square.stack")
            }
            await refreshBoards()
        }
    }

    /// UI-test hook: seed synthetic source-app rows into a throwaway durable
    /// store. Both launch arguments are mandatory, so real history is untouched.
    private func seedSourceAppsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-source-apps"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full
        else { return }
        Task {
            let entries: [(text: String, app: String, kind: ClipContentKind)] = [
                ("Safari source alpha", "com.apple.Safari", .text),
                ("Safari source link", "com.apple.Safari", .url),
                ("Xcode source sample", "com.apple.dt.Xcode", .code)
            ]
            let identifiers = [
                "00000000-0000-4000-8000-000000000201",
                "00000000-0000-4000-8000-000000000202",
                "00000000-0000-4000-8000-000000000203"
            ]
            for (index, entry) in entries.enumerated() {
                guard let id = UUID(uuidString: identifiers[index]) else { return }
                let item = ClipItem(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                    kind: entry.kind, preview: entry.text,
                    contentHash: "ios-ui-source-\(index)", sourceAppBundleID: entry.app)
                _ = try? await full.insert(item, content: .text(entry.text))
            }
            await refreshSourceApps()
            await search()
        }
    }

    /// UI-test hook: seed one synthetic clip at two uses so the next Copy drives
    /// the real atomic threshold and banner. Both arguments are mandatory; a
    /// normal launch can never touch durable user history.
    private func seedReuseSuggestionIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-reuse-suggestion"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000204")
        else { return }
        Task {
            let item = ClipItem(
                id: id, preview: "Reusable standup update",
                contentHash: "ios-ui-reuse-suggestion", uses: 2)
            _ = try? await full.insert(item, content: .text("Reusable standup update"))
            await search()
        }
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

    func setTelemetryConsent(_ consent: TelemetryConsent) {
        guard consent != .notAsked else { return }
        telemetryConsent = consent
    }

    func requestTelemetryConsentAfterFirstValue() {
        guard telemetryConsent == .notAsked else { return }
        isTelemetryConsentPromptPresented = true
    }

    func forceSync() async {
        // Start = "run a sync cycle now" on the boundary; the CloudKit
        // adapter gives it real semantics during on-device verification.
        await syncController.forceSync()
        await refreshHints()
    }

    /// Pull the latest from iCloud (and push pending) when the app comes
    /// forward, so another device's recent clips appear without a pull-to-
    /// refresh. The engine is push-driven on its own; this is the latency
    /// belt-and-braces for foregrounding (and pushes iOS coalesced while the
    /// app was suspended). The status observer refreshes the list on settle.
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

    private func recordBoardFailure(_ message: String.LocalizationValue) {
        diagnostics.record(String(localized: "Boards"), String(localized: message))
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
    /// Honors the shared free-tier gate and only confirms a durable write.
    func saveAsSnippet(_ item: ClipItem) async {
        guard let full else { return }
        switch await curationController.promoteToSnippet(item, tier: tier, store: full) {
        case .promoted:
            await search()
            // Refresh first so the two-second confirmation remains visible
            // after the durable mutation has settled and the UI is idle.
            flashNote(String(localized: "Saved as snippet"))
        case .freeLimitReached:
            proGateTick += 1
        case .clipUnavailable:
            await search()
        case .failed:
            diagnostics.record("Snippets", "Couldn’t save the snippet.")
        }
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
            if outcome == .failed {
                recordBoardFailure("Couldn’t create the board.")
            }
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
        if outcome == .failed {
            recordBoardFailure("Couldn’t create the board.")
        } else if case .created(_, filedClip: false) = outcome {
            recordBoardFailure("The board was created, but the clip couldn’t be added.")
        }
        await refreshBoards()
        await search()
        guard case .created(let boardID, filedClip: true) = outcome else { return nil }
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
    /// record, so enqueue the changed clip immediately after the local write.
    @discardableResult
    func setBoardMembership(_ item: ClipItem, board: Pinboard, member: Bool) async -> Bool {
        guard let full else { return false }
        let succeeded = await BoardsController().setBoardMembership(
            item, board: board, member: member, store: full, engine: syncController.engine)
        guard succeeded else {
            recordBoardFailure(
                member
                    ? "Couldn’t add the clip to the board."
                    : "Couldn’t remove the clip from the board.")
            return false
        }
        await search()
        return true
    }

    /// Rename a user board and propagate the new name (no-op on Favorites — the
    /// shared controller guards `isSystem`).
    func renameBoard(_ board: Pinboard, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let full else { return }
        Task {
            let outcome = await BoardsController().renameBoard(
                board, name: trimmed, store: full, engine: syncController.engine)
            if outcome == .failed {
                recordBoardFailure("Couldn’t rename the board.")
            }
            await refreshBoards()
        }
    }

    @discardableResult
    func updateBoardIdentity(_ board: Pinboard, colorHex: String?, emoji: String?) async -> Bool {
        guard let full else { return false }
        let outcome = await BoardsController().updateBoardIdentity(
            board, colorHex: colorHex, emoji: emoji, store: full,
            engine: syncController.engine)
        if outcome == .failed {
            recordBoardFailure("Couldn’t update the board appearance.")
        }
        await refreshBoards()
        return outcome != .failed
    }

    /// Delete a user board. When sync is on, tombstone it so the removal reaches
    /// the other devices; otherwise a plain local delete. Favorites is protected.
    func deleteBoard(_ board: Pinboard) {
        guard !board.isSystem, let full else { return }
        Task {
            let outcome = await BoardsController().deleteBoard(
                board, store: full, engine: syncController.engine,
                syncEnabled: syncController.isEnabled)
            if outcome == .failed {
                recordBoardFailure("Couldn’t delete the board.")
            }
            if outcome == .changed, selectedBoardID == board.id { selectedBoardID = nil }
            await refreshBoards()
            await search()
        }
    }

    /// The recent list (no query, no board) is the only date-grouped, paginated
    /// view — see `HistoryListViewModel.isGroupedView`.
    var isGroupedView: Bool { history.isGroupedView }

    /// `captures` narrowed by the kind filter — see `HistoryListViewModel`.
    var visibleClips: [ClipItem] { history.visibleClips }

    func search() async { await history.search() }

    func refreshSourceApps() async { await history.refreshSourceApps() }

    /// Append the next page as the list nears its end (infinite scroll).
    func loadMoreIfNeeded(_ item: ClipItem) async { await history.loadMoreIfNeeded(item) }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    func rebuildSections() { history.rebuildSections() }

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
        // Frecency signal: iOS's "use" is the Copy tap (there's no paste-back).
        // The atomic return contains metadata only and never flags a re-upload.
        let suggestion = try? await full?.recordUseAndSnippetSuggestion(
            id: item.id, now: .now,
            requiredUses: SnippetLimits.promotionSuggestionUseThreshold)
        // Copying a clip is the truest "ready to paste" moment — it's on the
        // pasteboard now — so surface it on the Live Activity too.
        clipActivity.show(item, sync: ClipSyncBadge(syncStatus))
        requestTelemetryConsentAfterFirstValue()
        if let suggestion { await presentReuseSuggestion(suggestion) }
    }

    /// Resolves the one curation prompt for this use. Auto-board keeps priority
    /// so the copy moment never stacks a board prompt and a snippet prompt.
    private func presentReuseSuggestion(_ item: ClipItem) async {
        let destination: ReuseSuggestion.Destination
        if let board = await suggestedBoard(for: item) {
            destination = .board(board)
        } else {
            destination = .snippet
        }
        reuseSuggestion = ReuseSuggestion(item: item, destination: destination)
    }

    func dismissReuseSuggestion() {
        reuseSuggestion = nil
    }

    func acceptReuseSuggestion() async {
        guard let suggestion = reuseSuggestion else { return }
        reuseSuggestion = nil
        switch suggestion.destination {
        case .board(let board):
            _ = await setBoardMembership(suggestion.item, board: board, member: true)
        case .snippet:
            await saveAsSnippet(suggestion.item)
        }
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
        switch await curationController.togglePin(
            item, tier: tier, store: full, engine: syncController.engine)
        {
        case .pinned, .unpinned, .alreadyPinned, .alreadyUnpinned, .clipUnavailable:
            await search()
        case .freeLimitReached:
            proGateTick += 1
        case .failed:
            diagnostics.record("Pins", "Couldn’t update the pin.")
        }
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
    private let curationController = ClipCurationController()
    private let ingestionCoordinator = ClipIngestionCoordinator()
    /// Durable store in the App Group container (shared family location);
    /// in-memory fallback keeps the app usable if the container is missing.
    let store: any ClipboardStore = {
        // Test hook: force the in-memory fallback so the "history isn't being
        // saved" path (and its diagnostics entry) is drivable by a UI test.
        if ProcessInfo.processInfo.arguments.contains("-force-ephemeral-store") {
            return InMemoryClipboardStore()
        }
        // A unique SQLite store gives UI tests durable GRDB semantics without
        // opening the simulator user's App Group database or Keychain.
        if ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "gancho-ios-uitest-store-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            return
                (try? GRDBClipboardStore(directory: directory))
                ?? InMemoryClipboardStore()
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
        saveNoteTask?.cancel()
        saveNote = text
        // The note is a transient overlay VoiceOver won't focus on its own; speak
        // it so a blind user gets the same confirmation a sighted one sees.
        UIAccessibility.post(notification: .announcement, argument: text)
        saveNoteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            saveNote = nil
            saveNoteTask = nil
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
        let configuration = ClipIngestionCoordinator.Configuration(
            sensitiveLifetime: RetentionPolicy.load(from: defaults).sensitiveLifetime,
            detectSecrets: intelligence.detectSecrets,
            precomputedKind: precomputedKind,
            tier: tier,
            intelligence: intelligence)
        guard
            let outcome = try? await ingestionCoordinator.ingest(
                capture,
                configuration: configuration,
                store: store,
                syncEngine: syncController.engine)
        else { return }
        flashNote(
            outcome.isNew
                ? String(localized: "Saved") : String(localized: "Already in your history"))
        // Bounded like every other load — search() pulls the first page only.
        await search()
        reloadWidgets()
        // Surface the just-captured clip as "ready to paste" (masked if
        // sensitive) on the Dynamic Island / lock screen.
        clipActivity.show(outcome.item, sync: ClipSyncBadge(syncStatus))
        enrich(outcome)
    }

    /// On-device enrichment of a clip captured ON this iPhone — Apple
    /// Intelligence titles, OCR, and semantic embeddings — so an iOS capture is
    /// as rich as one synced from the Mac. Never blocks capture (utility
    /// priority); the shared `EnrichmentPlan` gates it (Pro + non-sensitive +
    /// per-stage toggles). Enriched fields that ride the clip record sync; the
    /// embedding stays device-local.
    private func enrich(_ outcome: ClipIngestionCoordinator.Outcome) {
        guard !outcome.enrichment.isEmpty, let full else { return }
        let syncEngine: (any SyncEngine)? =
            syncController.isEnabled ? syncController.engine : nil
        Task(priority: .utility) {
            await ingestionCoordinator.enrich(
                outcome,
                store: full,
                syncEngine: syncEngine
            ) {
                await self.search()  // surface the new title without a manual refresh
            }
        }
    }
}
