import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// iOS companion shell (pre-alpha). Proves the honest capture story end to
/// end: intent-based reads only (capture button, UIPasteControl, share
/// extension inbox), detect-before-read hints, and NO background polling —
/// the App Review notes promise exactly this behavior.
@main
struct GanchoiOSApp: App {
    @State private var model = IOSAppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// One-time welcome: iOS's intent-based capture is novel, so first launch
    /// explains the save paths before dropping the user on an empty list.
    @AppStorage("ios-has-seen-welcome") private var hasSeenWelcome = false

    /// UI-test hook: route straight to the Privacy Center on launch (no
    /// welcome, no navigation) so XCUITest can assert the diagnostics log.
    private var routeToPrivacyCenter: Bool {
        ProcessInfo.processInfo.arguments.contains("-open-privacy-center-on-launch")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if routeToPrivacyCenter {
                    NavigationStack { IOSPrivacyCenterView() }
                } else if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad gets the sidebar layout; iPhone keeps the stack.
                    IPadSplitView()
                } else {
                    CaptureView()
                }
            }
            .environment(model)
            // Post-launch maintenance: the cosmetic legacy-preview backfill
            // moved off the synchronous store open (it scanned image rows on
            // every cold launch); run it once the first frame is up.
            .task {
                guard let grdb = model.store as? GRDBClipboardStore else { return }
                try? await grdb.backfillLegacyPreviews()
            }
            // Widget deep links (`gancho://clip/<id>`) open the right clip.
            .onOpenURL { model.handleDeepLink($0) }
            // Brand-green accent (iOS has no per-app OS accent picker, so green
            // is the default); the Synced check and success states use it too.
            .ganchoTinted()
            .sheet(
                isPresented: Binding(
                    get: { !hasSeenWelcome && !routeToPrivacyCenter },
                    set: { showing in if !showing { hasSeenWelcome = true } })
            ) {
                IOSOnboardingView { hasSeenWelcome = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Release the encrypted store's SQLite locks before iOS suspends the
            // process (avoids 0xDEAD10CC), and resume on return to foreground.
            switch phase {
            case .background: DatabaseSuspension.suspend()
            case .active: DatabaseSuspension.resume()
            default: break
            }
        }
    }
}

/// First-run welcome (shown once via `ios-has-seen-welcome`). One scroll
/// screen: what Gancho is, then the three ways to save on iOS — because there
/// is no background clipboard watching, the save paths are the whole model.
struct IOSOnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Everything you copy, saved and searchable")
                            .font(.title2.bold())
                        Text(
                            "Gancho keeps a private history of what you copy — all on this device."
                        )
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
                        Text("Three ways to save")
                            .font(.headline)
                        onboardingRow(
                            "hand.tap", "Tap to save",
                            "iOS can't watch the clipboard in the background — no app can. Use the Paste button to save what you copied."
                        )
                        onboardingRow(
                            "square.and.arrow.up", "Share from any app",
                            "Send text, a link, or an image to Gancho from the share sheet.")
                        onboardingRow(
                            "bolt", "Shortcuts & Action Button",
                            "Save your clipboard with a Shortcut — even from the Action Button.")
                    }

                    Label(
                        "Nothing leaves this device unless you turn on iCloud sync.",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Welcome to Gancho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Get started") { onDone() }
                        .accessibilityIdentifier("onboarding-done")
                }
            }
        }
    }

    private func onboardingRow(
        _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Full-screen, pinch-zoomable view of an image clip — the in-list preview caps
/// at 340pt, too small to read a screenshot's text. Loads the full image (not
/// the thumbnail) so zooming stays sharp.
struct FullScreenImageView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if case .binary(let data, _)? = try? await model.store.content(for: item.id),
                let uiImage = UIImage(data: data)
            {
                image = Image(uiImage: uiImage)
            }
        }
    }
}

/// Pinch + double-tap zoom over a static image. Plain SwiftUI gestures keep it
/// dependency-free; double-tap toggles a 2.5× zoom for one-handed reading.
private struct ZoomableImageView: View {
    let image: Image
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, min(6, lastScale * $0.magnification)) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }
}

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

    /// Sync boundary: pull-to-refresh forces a cycle. A `NoopSyncEngine`
    /// until the user is Pro on an iCloud-signed-in device; the adapter swaps
    /// in transparently — the pull-to-refresh UI contract is identical.
    private var syncEngine: any SyncEngine = NoopSyncEngine()
    private var syncEnabled = false
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
        thumbnails = ClipThumbnailStore(store: store)
        purchases.onTierChange = { [weak self] tier in
            guard let self else { return }
            self.tier = tier
            self.configureSync()
        }
        Task {
            tier = await purchases.currentTier()
            #if DEBUG
                if DebugFlags.forcePro { tier = .pro }
            #endif
            configureSync()
        }
        // Log a data-loss-level storage failure eagerly (before any view reads
        // the diagnostics log), so the Privacy Center shows it the moment it
        // opens. The log isn't @Observable-tracked, so a later record wouldn't
        // refresh an open screen.
        recordStorageHealthIfNeeded()
    }

    /// Arms or disarms iCloud sync to match the current tier + account.
    /// Universal Purchase entitles the iPhone too, so a Pro Mac purchase
    /// turns sync on here after the next entitlement refresh.
    private func configureSync() {
        guard let grdb = store as? GRDBClipboardStore else { return }
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let cloudKitEntitled = CloudKitEntitlements.currentTaskAllowsSync()
        let enable = SyncEnablement.shouldEnable(
            tier: tier,
            iCloudAvailable: iCloudAvailable,
            hasCloudKitEntitlement: cloudKitEntitled)
        guard enable != syncEnabled else { return }
        syncEnabled = enable

        let previous = syncEngine
        Task { await previous.stop() }
        let stateURL = SharedStorageLocation.storeDirectory(appGroupID: SharedInbox.appGroupID)
            .appendingPathComponent("sync-state.plist")
        syncEngine = SyncEngineFactory.make(
            store: grdb, tier: tier, iCloudAvailable: iCloudAvailable,
            hasCloudKitEntitlement: cloudKitEntitled,
            stateStore: .file(at: stateURL),
            onStatus: { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    let wasSyncing = self.syncStatus == .syncing
                    self.syncStatus = status
                    // A finished cycle may have pulled new boards/clips from
                    // iCloud. Refresh the lists so they appear without having to
                    // background and reopen the app.
                    if wasSyncing, status != .syncing {
                        await self.refreshBoards()
                        await self.search()
                    }
                }
            })
        if enable {
            let engine = syncEngine
            Task { try? await engine.start() }
        } else {
            syncStatus = .idle
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
        configureSync()
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
                configureSync()
            }
        }

        /// QA-only: drop the saved CKSyncEngine state so the next cycle re-fetches
        /// every zone from scratch. Fixes a device whose token drifted ahead of
        /// what it actually stored (older records never re-arrive on an
        /// incremental fetch). Local rows are kept; remote records re-upsert.
        func resetSyncAndRepull() {
            let stateURL = SharedStorageLocation.storeDirectory(
                appGroupID: SharedInbox.appGroupID
            ).appendingPathComponent("sync-state.plist")
            try? FileManager.default.removeItem(at: stateURL)
            syncEnabled = false
            configureSync()
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
        try? await syncEngine.start()
        await refreshHints()
    }

    /// Pull the latest from iCloud (and push pending) when the app comes
    /// forward, so another device's recent clips appear without a pull-to-
    /// refresh — the engine only fetches on `start()` and gets no push to fetch
    /// on. The sync-status observer refreshes the list on settle. No-op off.
    func syncNow() {
        guard syncEnabled else { return }
        let engine = syncEngine
        Task { try? await engine.start() }
    }

    /// Resolves a `gancho://clip/<id>` widget link: make sure the clip is in
    /// the list (so the detail destination finds it), then signal the view to
    /// navigate. A foreign or unknown link is ignored.
    func handleDeepLink(_ url: URL) {
        guard let id = WidgetClips.clipID(fromDeepLink: url) else { return }
        Task {
            if !captures.contains(where: { $0.id == id }),
                let item = try? await (store as? GRDBClipboardStore)?.item(id: id)
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
        guard let grdb = store as? GRDBClipboardStore else { return }
        boards = (try? await grdb.pinboards()) ?? []
    }

    /// Scope the history list to a board (or back to All clips) and refresh —
    /// the one path both the rail and the boards home go through.
    func selectBoard(_ id: UUID?) {
        selectedBoardID = id
        Task { await search() }
    }

    /// Total non-archived clips — the "All clips" count on the boards home.
    func clipCount() async -> Int {
        guard let grdb = store as? GRDBClipboardStore else { return 0 }
        return (try? await grdb.count()) ?? 0
    }

    /// How many clips a board holds — its count on the boards home.
    func clipCount(in board: Pinboard) async -> Int {
        guard let grdb = store as? GRDBClipboardStore else { return 0 }
        return (try? await grdb.count(inBoard: board.id)) ?? 0
    }

    /// Promote a clip to a reusable snippet — the peek's "Save as snippet".
    /// Honors the free-tier snippet limit and surfaces a note either way.
    func saveAsSnippet(_ item: ClipItem) async {
        guard let grdb = store as? GRDBClipboardStore else { return }
        let count = (try? await grdb.snippetCount()) ?? 0
        guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: tier == .pro) else {
            flashNote(String(localized: "Upgrade to Pro for more snippets"))
            return
        }
        try? await grdb.promoteToSnippet(id: item.id)
        flashNote(String(localized: "Saved as snippet"))
        await search()
    }

    /// Creates a board and queues its metadata for sync, so it shows up on the
    /// user's other devices. The built-in Favorites board never counts against
    /// the free limit.
    func createBoard(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let grdb = store as? GRDBClipboardStore else { return }
        Task {
            let count = (try? await grdb.pinboards().filter { !$0.isSystem }.count) ?? 0
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro) else {
                // Don't dead-end on a vanishing note: surface the Pro screen.
                proGateTick += 1
                return
            }
            if let board = try? await grdb.createPinboard(name: trimmed) {
                await syncEngine.enqueue(boards: [board])
            }
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
        guard !trimmed.isEmpty, let grdb = store as? GRDBClipboardStore else { return nil }
        let count = (try? await grdb.pinboards().filter { !$0.isSystem }.count) ?? 0
        guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro) else {
            flashNote(String(localized: "Upgrade to Pro for more boards"))
            return nil
        }
        guard let board = try? await grdb.createPinboard(name: trimmed) else { return nil }
        await syncEngine.enqueue(boards: [board])
        try? await grdb.assign(clipID: item.id, toBoard: board.id)
        await refreshBoards()
        await search()
        return board.id
    }

    /// The boards a clip belongs to — drives the detail screen's checkmarks.
    func boardMembership(for item: ClipItem) async -> Set<UUID> {
        guard let grdb = store as? GRDBClipboardStore else { return [] }
        return (try? await grdb.boardIDs(forClip: item.id)) ?? []
    }

    /// Suggest the board this clip probably belongs to, by a semantic k-NN vote
    /// over how similar clips were filed (`BoardSuggester`). Only ever suggests;
    /// nil when the toggle is off, the clip is sensitive, there are no eligible
    /// user boards, or the neighborhood shows no clear home. 100% on-device.
    func suggestedBoard(for item: ClipItem) async -> Pinboard? {
        guard intelligence.autoBoard, !item.isSensitive,
            let grdb = store as? GRDBClipboardStore
        else { return nil }
        let userBoards = ((try? await grdb.pinboards()) ?? []).filter { !$0.isSystem }
        guard !userBoards.isEmpty else { return nil }
        let current = (try? await grdb.boardIDs(forClip: item.id)) ?? []
        let candidates = Set(userBoards.map(\.id)).subtracting(current)
        guard !candidates.isEmpty else { return nil }

        guard case .text(let text)? = try? await grdb.content(for: item.id),
            let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
            let vector = try? embedder.vector(for: String(text.prefix(1_000)))
        else { return nil }
        let neighbors = ((try? await grdb.semanticSearch(queryVector: vector, topK: 8)) ?? [])
            .filter { $0.id != item.id }
        guard !neighbors.isEmpty else { return nil }

        var neighborBoards: [Set<UUID>] = []
        for neighbor in neighbors {
            neighborBoards.append((try? await grdb.boardIDs(forClip: neighbor.id)) ?? [])
        }
        guard
            let vote = BoardSuggester.suggest(
                neighborBoardIDs: neighborBoards, candidates: candidates)
        else { return nil }
        return userBoards.first { $0.id == vote.boardID }
    }

    /// Add or remove a clip from one board. Membership rides the clip's sync
    /// record, so the change propagates to other devices on the next cycle.
    func setBoardMembership(_ item: ClipItem, board: Pinboard, member: Bool) async {
        guard let grdb = store as? GRDBClipboardStore else { return }
        if member {
            try? await grdb.assign(clipID: item.id, toBoard: board.id)
        } else {
            try? await grdb.unassign(clipID: item.id, fromBoard: board.id)
        }
        await search()
    }

    /// Rename a user board and propagate the new name (no-op on Favorites — the
    /// store guards `isSystem`).
    func renameBoard(_ board: Pinboard, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let grdb = store as? GRDBClipboardStore else { return }
        Task {
            try? await grdb.renameBoard(id: board.id, name: trimmed)
            var renamed = board
            renamed.name = trimmed
            await syncEngine.enqueue(boards: [renamed])
            await refreshBoards()
        }
    }

    /// Delete a user board. When sync is on, tombstone it so the removal reaches
    /// the other devices; otherwise a plain local delete. Favorites is protected.
    func deleteBoard(_ board: Pinboard) {
        guard !board.isSystem, let grdb = store as? GRDBClipboardStore else { return }
        Task {
            if syncEnabled {
                try? await grdb.deletePinboardForSync(id: board.id)
                await syncEngine.enqueueBoardDeletion(ids: [board.id])
            } else {
                try? await grdb.deletePinboard(id: board.id)
            }
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
        let grdb = store as? GRDBClipboardStore
        if query.isEmpty {
            if let board = selectedBoardID, let grdb {
                captures = (try? await grdb.items(inBoard: board)) ?? []
                reachedEnd = true
            } else {
                captures = await loadRecentPage(offset: 0)
                reachedEnd = captures.count < Self.pageSize
            }
        } else {
            let kinds: Set<ClipContentKind>? = kindFilter.map { [$0] }
            captures =
                (try? await grdb?.search(
                    ClipSearchQuery(text: query, kinds: kinds, boardID: selectedBoardID),
                    limit: 50)) ?? []
            reachedEnd = true
        }
        rebuildSections()
    }

    /// Pinned-first then capture-time order, so the date buckets stay contiguous.
    private func loadRecentPage(offset: Int) async -> [ClipItem] {
        if let grdb = store as? GRDBClipboardStore {
            return (try? await grdb.recentForBrowse(offset: offset, limit: Self.pageSize)) ?? []
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
        guard let grdb = store as? GRDBClipboardStore else { return nil }
        switch await ClipboardQA().answer(
            question: question, store: grdb, useSemantic: intelligence.semanticSearch)
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
        guard let grdb = store as? GRDBClipboardStore else { return }
        try? await grdb.setPinned(id: item.id, !item.isPinned)
        await search()
    }

    func delete(_ item: ClipItem) async {
        if syncEnabled, let grdb = store as? GRDBClipboardStore {
            try? await grdb.deleteForSync(id: item.id)
            await syncEngine.enqueueDeletion(ids: [item.id])
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
        guard let grdb = store as? GRDBClipboardStore else { return nil }
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
        guard let grdb = store as? GRDBClipboardStore else { return nil }
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
        if let stored { await syncEngine.enqueue([stored]) }
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
        guard !plan.isEmpty, let grdb = store as? GRDBClipboardStore else { return }
        Task(priority: .utility) {
            if plan.runs(.ocr), case .binary(let data, _)? = content,
                let text = try? await ImageTextExtractor().extractText(from: data)
            {
                _ = try? await grdb.attachExtractedText(id: item.id, text: text)
            }
            if plan.runs(.title), case .text(let text)? = content,
                let annotation = try? await TieredClipAnnotator().annotate(text)
            {
                _ = try? await grdb.updateTitle(id: item.id, title: annotation.title)
                await search()  // surface the new title without a manual refresh
            }
            if plan.runs(.embedding), case .text(let text)? = content,
                let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
                let vector = try? embedder.vector(for: String(text.prefix(1_000)))
            {
                _ = try? await grdb.saveEmbedding(clipID: item.id, vector: vector)
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

/// The one sheet the capture screen can present at a time.
enum CaptureSheet: Identifiable {
    case settings
    case boards
    case peek(ClipItem)
    case move(ClipItem)
    case pro

    var id: String {
        switch self {
        case .settings: "settings"
        case .boards: "boards"
        case .peek(let clip): "peek-\(clip.id)"
        case .move(let clip): "move-\(clip.id)"
        case .pro: "pro"
        }
    }
}

struct CaptureView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// One sheet at a time — Settings, the boards home, a clip peek, or the
    /// move-to-board sheet. A single `.sheet(item:)` because stacking several
    /// `.sheet` modifiers on one view is unreliable (two `isPresented` sheets
    /// silently drop one — that's why the boards home wouldn't open).
    @State private var activeSheet: CaptureSheet?
    @State private var showNewBoard = false
    @State private var newBoardName = ""
    @State private var renameTarget: Pinboard?
    @State private var renameField = ""
    @State private var path: [UUID] = []
    @State private var answer: IOSAppModel.ClipboardAnswer?
    @State private var isAsking = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                boardRail
                List {
                    if model.storageIsEphemeral { storageWarningSection }
                    syncStatusSection
                    pasteboardSection

                    if !model.query.isEmpty, model.askAvailable {
                        Section {
                            askRow
                        }
                    }

                    if model.visibleClips.isEmpty {
                        Section("History") { emptyState }
                    } else if model.isGroupedView {
                        // Pinned first, then Today / Yesterday / … date sections.
                        ForEach(model.sections) { group in
                            Section(sectionTitle(group.section)) {
                                ForEach(group.clips) { clipRow($0) }
                            }
                        }
                    } else {
                        Section("History") {
                            ForEach(model.visibleClips) { clipRow($0) }
                        }
                    }
                }
                .searchable(text: $model.query, prompt: Text("Search your clipboard"))
                .onChange(of: model.query) { _, _ in
                    answer = nil
                    Task { await model.search() }
                }
                .onChange(of: model.kindFilter) { _, _ in
                    Task { await model.search() }
                }
                .navigationTitle("Gancho")
                .navigationDestination(for: UUID.self) { id in
                    if let item = model.captures.first(where: { $0.id == id }) {
                        ClipDetailView(item: item)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        kindFilterMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            activeSheet = .boards
                        } label: {
                            Image(systemName: "rectangle.stack")
                        }
                        .accessibilityLabel(Text("Boards"))
                        .accessibilityIdentifier("boards-home-open")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            activeSheet = .settings
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))
                    }
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .settings: IOSSettingsView()
                    case .boards: BoardsHomeView()
                    case .peek(let clip):
                        // Wrap the peek in its own NavigationStack so it gets a
                        // titled bar + an explicit Done button (the codebase
                        // sheet convention) — drag-to-dismiss isn't discoverable.
                        // The pushed (deep-link) path keeps the parent's back
                        // button, so ClipDetailView itself stays unwrapped.
                        NavigationStack {
                            ClipDetailView(item: clip)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { activeSheet = nil }
                                    }
                                }
                        }
                    case .move(let clip): MoveToBoardSheet(item: clip)
                    case .pro:
                        // Wrapped like the peek: a titled bar + explicit Done,
                        // since drag-to-dismiss isn't discoverable.
                        NavigationStack {
                            ProInfoView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { activeSheet = nil }
                                    }
                                }
                        }
                    }
                }
                .onChange(of: model.proGateTick) { _, _ in
                    // A free-tier limit was hit somewhere — show the Pro screen
                    // rather than letting a vanishing note dead-end the user.
                    activeSheet = .pro
                }
                .alert("New board", isPresented: $showNewBoard) {
                    TextField("Board name", text: $newBoardName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { model.createBoard(named: newBoardName) }
                }
                .alert("Rename board", isPresented: renamePresented) {
                    TextField("Board name", text: $renameField)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") {
                        if let renameTarget { model.renameBoard(renameTarget, name: renameField) }
                    }
                }
                .refreshable { await model.forceSync() }
                .accessibilityIdentifier("capture-screen")
            }
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await activate() }
        }
        // Re-sense the pasteboard every time the app comes forward — the most
        // reliable signal (scenePhase can miss). This is how the capture card
        // tracks what you just copied in another app.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await model.refreshHints() }
        }
        // …and when the pasteboard changes while we're foreground (e.g. you tap
        // Copy on a clip), so the card reflects it without a round-trip away.
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) {
            _ in
            Task { await model.refreshHints() }
        }
        .onChange(of: model.deepLinkClipID) { _, id in
            guard let id else { return }
            path = [id]
            model.deepLinkClipID = nil
        }
    }

    /// "Ask your clipboard": a one-tap button to answer the typed query from
    /// history, the spinner while it runs, and the grounded answer card. The
    /// section only appears while searching and when the model is available.
    @ViewBuilder private var askRow: some View {
        if isAsking {
            Label("Thinking…", systemImage: "sparkles")
                .font(.callout).foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
        } else if let answer {
            answerCard(answer)
        } else {
            Button {
                runAsk()
            } label: {
                Label("Ask gancho", systemImage: "sparkles")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(GanchoTokens.Palette.accent)
            }
            .accessibilityIdentifier("ask-clipboard")
        }
    }

    private func answerCard(_ answer: IOSAppModel.ClipboardAnswer) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Label("Answer", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    self.answer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .accessibilityLabel(Text("Dismiss"))
            }
            Text(answer.answer)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if !answer.sources.isEmpty {
                Text("Sources").font(.caption).foregroundStyle(.secondary)
                ForEach(answer.sources.prefix(4)) { clip in
                    Button {
                        Task { await model.copyToPasteboard(clip) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: clip.kind.symbolName)
                                .font(.caption)
                                .foregroundStyle(GanchoTokens.Palette.kindTint(for: clip.kind))
                            Text(clip.preview).font(.callout).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "doc.on.doc")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("ask-answer")
    }

    private func runAsk() {
        let question = model.query
        answer = nil
        isAsking = true
        Task {
            let result = await model.askClipboard(question)
            isAsking = false
            answer = result
        }
    }

    /// Boards axis (above the type filter), as a horizontal rail of chips: All
    /// clips · Favorites · user boards · New board. The active chip takes the
    /// system accent; long-press a user board to rename or delete it.
    /// One history row: tap pushes the detail (the peek lands in a later phase),
    /// swipe gives Copy / Pin / Delete, and reaching the last rows pulls the next
    /// page (infinite scroll).
    @ViewBuilder
    private func clipRow(_ item: ClipItem) -> some View {
        Button {
            activeSheet = .peek(item)
        } label: {
            ClipCard(item: item, thumbnail: model.thumbnails.cached(for: item.id))
        }
        .buttonStyle(.plain)
        .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
        .onAppear { Task { await model.loadMoreIfNeeded(item) } }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await model.togglePin(item) }
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin",
                    systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await model.copyToPasteboard(item) }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
            Button {
                activeSheet = .move(item)
            } label: {
                Label("Board", systemImage: "tray.and.arrow.down")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button {
                Task { await model.copyToPasteboard(item) }
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            if !item.isSensitive {
                ShareLink(item: item.preview) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                Task { await model.togglePin(item) }
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin",
                    systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            clipPreview(item)
        }
    }

    /// The rich preview iOS lifts under a long-press: the image renders for
    /// image clips, otherwise the (masked-if-sensitive) text preview.
    @ViewBuilder
    private func clipPreview(_ item: ClipItem) -> some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 220)
        } else {
            Text(item.preview)
                .font(item.kind == .code ? .body.monospaced() : .body)
                .padding()
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    private func sectionTitle(_ section: ClipSection) -> LocalizedStringKey {
        switch section {
        case .pinned: "Pinned"
        case .date(let bucket): bucketTitle(bucket)
        }
    }

    private func bucketTitle(_ bucket: DateBucket) -> LocalizedStringKey {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .older: "Older"
        }
    }

    private var boardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                railChip(
                    Text("All clips"), systemImage: "tray.full",
                    isActive: model.selectedBoardID == nil
                ) {
                    select(board: nil)
                }
                ForEach(model.boards) { board in
                    railChip(
                        board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                        systemImage: board.sfSymbol,
                        isActive: model.selectedBoardID == board.id,
                        dotColor: board.isSystem ? nil : BoardColors.color(for: board)
                    ) {
                        select(board: board.id)
                    }
                    .contextMenu {
                        if !board.isSystem {
                            Button("Rename board…") {
                                renameField = board.name
                                renameTarget = board
                            }
                            Button("Delete board", role: .destructive) {
                                model.deleteBoard(board)
                            }
                        }
                    }
                }
                Button {
                    newBoardName = ""
                    showNewBoard = true
                } label: {
                    Label("New board…", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, GanchoTokens.Spacing.sm)
                        .padding(.vertical, GanchoTokens.Spacing.xs)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("board-new")
            }
            .padding(.horizontal, GanchoTokens.Spacing.md)
            .padding(.vertical, GanchoTokens.Spacing.xs)
        }
        .accessibilityIdentifier("board-rail")
    }

    private func railChip(
        _ label: Text, systemImage: String, isActive: Bool, dotColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dotColor, !isActive {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                } else {
                    Image(systemName: systemImage).font(.caption)
                }
                label.font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func select(board id: UUID?) {
        model.selectBoard(id)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var kindFilterMenu: some View {
        @Bindable var model = self.model
        return Menu {
            Picker("Filter by type", selection: $model.kindFilter) {
                Text("All types").tag(ClipContentKind?.none)
                ForEach(ClipContentKind.allCases, id: \.self) { kind in
                    Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
                        .tag(ClipContentKind?.some(kind))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .onChange(of: model.kindFilter) { _, _ in Task { await model.search() } }
        .accessibilityLabel(Text("Filter by type"))
    }

    private var hasActiveFilter: Bool {
        model.kindFilter != nil || model.selectedBoardID != nil
    }

    private func clearFilters() {
        model.kindFilter = nil
        model.selectBoard(nil)
    }

    /// Branches on context so it never lies: a search with no hits, a filter
    /// that excluded everything, or a genuinely empty history (the honest
    /// no-background-capture explanation). Before the split, "Nothing captured
    /// yet" showed up mid-search even when there were clips.
    @ViewBuilder private var emptyState: some View {
        if !model.query.isEmpty {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("No clips match “\(model.query)”.")
                    .foregroundStyle(.secondary)
                if hasActiveFilter {
                    Button("Clear filters") { clearFilters() }
                        .font(.footnote)
                }
            }
        } else if hasActiveFilter {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("No clips in this filter.")
                    .foregroundStyle(.secondary)
                Button("Clear filters") { clearFilters() }
                    .font(.footnote)
            }
        } else {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("Nothing captured yet.")
                    .foregroundStyle(.secondary)
                Text(
                    "iOS apps can't watch the clipboard in the background — no app can. Capture with the button above, the share sheet from any app, or a Shortcut on your Action Button."
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
        }
    }

    /// Foreground activation: metadata hints + extension inbox, no reads.
    private func activate() async {
        model.syncNow()
        await model.refreshHints()
        await model.drainSharedInbox()
        await model.refreshBoards()
        await model.search()
    }

    /// The consensual capture card (the design's Pasteboard section). gancho
    /// senses the clipboard's TYPE via `detectPatterns` — no read, no "pasted
    /// from" banner — and the green `UIPasteControl` is the user's one-tap "yes,
    /// save this". Privacy is the function, not an apology.
    @ViewBuilder private var pasteboardSection: some View {
        Section {
            if let note = model.saveNote {
                Label(note, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(GanchoTokens.Palette.success)
                    .accessibilityIdentifier("save-note")
            }
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    captureTile
                    VStack(alignment: .leading, spacing: 4) {
                        Text(senseTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.hints.hasContent {
                            if alreadyCaptured {
                                captureTag(Text("Saved"), tint: GanchoTokens.Palette.success)
                            } else {
                                captureTag(
                                    Text("not read yet"), tint: GanchoTokens.Palette.warning)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    PasteControlView { providers in model.ingest(providers: providers) }
                        .frame(width: 108, height: 34)
                        .accessibilityIdentifier("paste-control")
                }
                .padding(.vertical, 10)
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(GanchoTokens.Palette.accent)
                    Text(
                        "Gancho never reads your clipboard on its own. It only sees the type until you tap Save."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
            }
            .accessibilityIdentifier("pasteboard-capture")
        } header: {
            HStack {
                Text("Pasteboard")
                Spacer()
                Label("sensed, not read", systemImage: "shield.lefthalf.filled")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }
        }
    }

    private var captureTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(GanchoTokens.Palette.accent.opacity(0.15))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: senseSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GanchoTokens.Palette.accent)
            }
    }

    /// Amber "not read yet" pill.
    private func captureTag(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }

    /// True when the copy currently on the clipboard is the one we just saved
    /// (matched by the pasteboard's change counter — metadata, no read).
    private var alreadyCaptured: Bool {
        model.lastCapturedChangeCount != nil
            && model.hints.changeCount == model.lastCapturedChangeCount
    }

    /// What `detectPatterns` sensed, as a title — derived without reading.
    private var senseTitle: LocalizedStringKey {
        guard model.hints.hasContent else { return "Pasteboard is empty" }
        if model.hints.probableWebURL { return "A link is on your clipboard" }
        if model.hints.probableWebSearch { return "Search text is on your clipboard" }
        if model.hints.number { return "A number is on your clipboard" }
        return "Something is on your clipboard"
    }

    private var senseSymbol: String {
        if model.hints.probableWebURL { return "link" }
        if model.hints.probableWebSearch { return "magnifyingglass" }
        if model.hints.number { return "number" }
        return "doc.on.clipboard"
    }

    /// Shown only when the durable store failed to open — captures are running
    /// in memory and will be lost on relaunch. Honest beats silent.
    private var storageWarningSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History isn't being saved").font(.subheadline.weight(.semibold))
                    Text(
                        "Gancho couldn't open its secure storage. Captures will vanish when you quit the app."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
            .accessibilityIdentifier("storage-warning")
        }
    }

    /// iCloud sync indicator. The steady states (off, synced) show nothing —
    /// the "ready to paste" Live Activity carries sync status now, so the
    /// history doesn't spend a card on a green "Synced" that's almost always
    /// true. Only the transient and the actionable states surface here.
    @ViewBuilder
    private var syncStatusSection: some View {
        switch model.syncStatus {
        case .idle, .upToDate:
            EmptyView()
        case .syncing:
            syncRow(Text("Syncing…"), "arrow.triangle.2.circlepath")
        case .pending(let count):
            syncRow(
                Text("\(Text("Waiting to sync")) · \(String(count))"), "arrow.up.circle")
        case .paused(let cause):
            syncRow(
                Text(causeText(cause)), "pause.circle", tint: GanchoTokens.Palette.warning,
                retry: true)
        case .failed(let cause):
            syncRow(
                Text(causeText(cause)), "exclamationmark.icloud",
                tint: GanchoTokens.Palette.danger, retry: true)
        }
    }

    private func syncRow(
        _ text: Text, _ symbol: String, tint: Color = .secondary, retry: Bool = false
    ) -> some View {
        Section {
            HStack {
                Label {
                    text
                } icon: {
                    // "Synced" reads green (a state); paused/failed warn — like macOS.
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                // A paused/failed sync was informational only; give it a way out.
                if retry {
                    Spacer(minLength: GanchoTokens.Spacing.sm)
                    Button("Retry") { model.syncNow() }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("sync-retry")
                }
            }
            .accessibilityIdentifier("sync-status")
        }
    }

    private func causeText(_ cause: SyncInterruption) -> LocalizedStringKey {
        switch cause {
        case .iCloudFull: "iCloud storage is full"
        case .notSignedIn: "Not signed in to iCloud"
        case .offline: "No internet connection"
        case .unknown: "Sync error"
        }
    }

}

/// A board's identity color as a small filled dot — the quiet per-board accent
/// the design asks for (green stays the app accent; Favorites wears the warm
/// favorite hue). Shared by every board row.
struct BoardDot: View {
    let board: Pinboard
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(board.isSystem ? GanchoTokens.Palette.warning : BoardColors.color(for: board))
            .frame(width: size, height: size)
    }
}

/// The move-to-board primitive: a quick "file this clip" sheet reached by
/// swiping a row. A clip can live in several boards at once, so this is a
/// multi-select — each tap toggles membership and saves immediately (the
/// change rides the clip's sync record). A board can be created inline, which
/// files the clip into it in one step.
struct MoveToBoardSheet: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var memberIDs: Set<UUID> = []
    @State private var newBoardName = ""
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.boards) { board in
                        Button {
                            toggle(board)
                        } label: {
                            HStack(spacing: GanchoTokens.Spacing.sm) {
                                BoardDot(board: board)
                                board.isSystem
                                    ? Text("Favorites") : Text(verbatim: board.name)
                                Spacer()
                                if memberIDs.contains(board.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(GanchoTokens.Palette.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("move-board-\(board.id.uuidString)")
                    }
                }
                Section {
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("New board", text: $newBoardName)
                            .focused($newFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(createAndFile)
                        if !newBoardName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: createAndFile).buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Add to board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await model.refreshBoards()
            memberIDs = await model.boardMembership(for: item)
        }
    }

    private func toggle(_ board: Pinboard) {
        let isMember = memberIDs.contains(board.id)
        Task {
            await model.setBoardMembership(item, board: board, member: !isMember)
            memberIDs = await model.boardMembership(for: item)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func createAndFile() {
        let name = newBoardName
        newBoardName = ""
        newFieldFocused = false
        Task {
            if await model.createBoard(named: name, filing: item) != nil {
                memberIDs = await model.boardMembership(for: item)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// The boards home — the managed list the rail's quick switcher can't be.
/// Smart boards (All clips, Favorites) sit above the user's boards, each with
/// its identity color and live clip count. Tapping a board scopes the history
/// to it; a board can be created, renamed, or deleted here. Reorder, recolor,
/// and per-board sharing are deferred (each needs store or sync plumbing).
struct BoardsHomeView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var totalCount = 0
    @State private var counts: [UUID: Int] = [:]
    @State private var showNewBoard = false
    @State private var newBoardName = ""
    @State private var renameTarget: Pinboard?
    @State private var renameField = ""

    private var systemBoards: [Pinboard] { model.boards.filter(\.isSystem) }
    private var userBoards: [Pinboard] { model.boards.filter { !$0.isSystem } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        open(nil)
                    } label: {
                        boardLabel(
                            Text("All clips"), icon: Image(systemName: "tray.full"),
                            tint: .secondary, count: totalCount)
                    }
                    .tint(.primary)
                    ForEach(systemBoards) { boardRow($0) }
                }
                Section("Boards") {
                    ForEach(userBoards) { boardRow($0) }
                    Button {
                        newBoardName = ""
                        showNewBoard = true
                    } label: {
                        Label("New board", systemImage: "plus")
                    }
                    .accessibilityIdentifier("boards-home-new")
                }
            }
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New board", isPresented: $showNewBoard) {
                TextField("Board name", text: $newBoardName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    model.createBoard(named: newBoardName)
                    Task { await reload() }
                }
            }
            .alert("Rename board", isPresented: renamePresented) {
                TextField("Board name", text: $renameField)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let renameTarget { model.renameBoard(renameTarget, name: renameField) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await reload() }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    @ViewBuilder
    private func boardRow(_ board: Pinboard) -> some View {
        Button {
            open(board.id)
        } label: {
            boardLabel(
                board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                icon: BoardDot(board: board, size: 14), tint: .primary,
                count: counts[board.id] ?? 0)
        }
        .tint(.primary)
        .accessibilityIdentifier("boards-home-\(board.id.uuidString)")
        .contextMenu {
            if !board.isSystem { boardActions(board) }
        }
        .swipeActions(edge: .trailing) {
            if !board.isSystem {
                Button(role: .destructive) {
                    delete(board)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    renameField = board.name
                    renameTarget = board
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func boardActions(_ board: Pinboard) -> some View {
        Button {
            renameField = board.name
            renameTarget = board
        } label: {
            Label("Rename board", systemImage: "pencil")
        }
        Button(role: .destructive) {
            delete(board)
        } label: {
            Label("Delete board", systemImage: "trash")
        }
    }

    private func boardLabel(
        _ title: Text, icon: some View, tint: Color, count: Int
    ) -> some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            icon.frame(width: 22)
            title.foregroundStyle(tint)
            Spacer(minLength: GanchoTokens.Spacing.sm)
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func open(_ id: UUID?) {
        model.selectBoard(id)
        dismiss()
    }

    private func delete(_ board: Pinboard) {
        model.deleteBoard(board)
        Task { await reload() }
    }

    private func reload() async {
        await model.refreshBoards()
        totalCount = await model.clipCount()
        var fresh: [UUID: Int] = [:]
        for board in model.boards { fresh[board.id] = await model.clipCount(in: board) }
        counts = fresh
    }
}

/// Per-kind detail: full content, dev actions, one-tap copy with haptics.
struct ClipDetailView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var fullText = ""
    @State private var actionResult: String?
    @State private var boardIDs: Set<UUID> = []
    @State private var smartResult: String?
    @State private var isThinking = false
    /// Sensitive clips stay masked until the user taps Reveal (the design's
    /// secret peek); never auto-revealed.
    @State private var revealed = false
    /// Whether the move-to-board sheet (the compact "Add to board") is open.
    @State private var showMoveSheet = false
    /// Whether the tapped image is open full-screen for pinch-zoom (screenshots
    /// are often small text the 340pt preview can't make legible).
    @State private var showFullImage = false
    /// The board auto-board thinks this clip belongs to (a suggestion, never
    /// auto-filed); nil until computed or once accepted/dismissed.
    @State private var suggestedBoard: Pinboard?

    /// Text-like clips (not image / file / colour) — what snippets, Smart Paste
    /// and most dev actions apply to.
    private var isTextLike: Bool {
        item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// Smart Paste fits text clips only and never a masked secret. Model-backed
    /// rewrites need Apple Intelligence, but deterministic PII redaction remains
    /// available whenever the user kept the Smart Paste toggle on.
    private var canSmartPaste: Bool {
        model.smartPasteAvailable && !item.isSensitive && isTextLike
    }

    /// The boards this clip currently belongs to — shown as chips in the peek.
    private var currentBoards: [Pinboard] {
        model.boards.filter { boardIDs.contains($0.id) }
    }

    /// Text handed to the iOS share sheet — the full text once loaded, else the
    /// stored preview (sensitive clips share only their masked preview).
    private var shareText: String {
        item.isSensitive ? item.preview : (fullText.isEmpty ? item.preview : fullText)
    }

    /// The medium-detent quick actions (the peek's action row). Copy is primary
    /// — iOS can't paste into another app, so copy-then-the-user-pastes is the
    /// realizable path. Smart Paste and board membership live in the sections
    /// below, revealed when the sheet is dragged to its large detent.
    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            peekAction("Copy", systemImage: "doc.on.clipboard", primary: true) {
                Task { await model.copyToPasteboard(item) }
                dismiss()
            }
            ShareLink(item: shareText) {
                peekActionLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            peekAction(
                item.isPinned ? "Pinned" : "Pin",
                systemImage: item.isPinned ? "pin.fill" : "pin"
            ) {
                Task { await model.togglePin(item) }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func peekAction(
        _ title: LocalizedStringKey, systemImage: String, primary: Bool = false,
        _ run: @escaping () -> Void
    ) -> some View {
        Button(action: run) { peekActionLabel(title, systemImage: systemImage, primary: primary) }
            .buttonStyle(.plain)
    }

    private func peekActionLabel(
        _ title: LocalizedStringKey, systemImage: String, primary: Bool = false
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    primary
                        ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .foregroundStyle(primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        List {
            actionRow
            contentSection
            metaChipsSection
            boardsSection
            if isTextLike, !item.isSensitive {
                Section {
                    Button("Save as snippet", systemImage: "textformat") {
                        Task { await model.saveAsSnippet(item) }
                    }
                    .accessibilityIdentifier("detail-save-snippet")
                }
            }
            smartActionsSection
        }
        .navigationTitle(Text(LocalizedStringKey(item.kind.rawValue)))
        .sheet(isPresented: $showMoveSheet) {
            MoveToBoardSheet(item: item)
        }
        .fullScreenCover(isPresented: $showFullImage) {
            FullScreenImageView(item: item).environment(model)
        }
        .onChange(of: showMoveSheet) { _, open in
            if !open {
                Task { boardIDs = await model.boardMembership(for: item) }
            }
        }
        .task {
            if case .text(let text)? = try? await model.store.content(for: item.id) {
                fullText = text
            }
        }
        .task { await model.thumbnails.ensureLoaded(item) }
        .task {
            await model.refreshBoards()
            boardIDs = await model.boardMembership(for: item)
        }
        .task { suggestedBoard = await model.suggestedBoard(for: item) }
        // Presented as a peek: medium shows the preview + action row; drag up to
        // the large detent for chips, boards, Smart Actions, and the full text.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The clip itself — image, text, or a masked secret kept behind Reveal.
    @ViewBuilder private var contentSection: some View {
        Section {
            if item.kind == .image, !item.isSensitive,
                let thumbnail = model.thumbnails.cached(for: item.id)
            {
                thumbnail
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 340, alignment: .center)
                    .clipShape(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { showFullImage = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("Open full screen to zoom"))
            } else if item.isSensitive, !revealed {
                Text(item.preview)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .foregroundStyle(.secondary)
                Button("Reveal", systemImage: "eye") { revealed = true }
                    .accessibilityIdentifier("detail-reveal")
            } else {
                // A very long Text inside a List row fails to lay out on iOS
                // (the detail came up blank). Cap what we render; the whole clip
                // is still available via Copy.
                let body = fullText.isEmpty ? item.preview : fullText
                Text(body.count > 8000 ? String(body.prefix(8000)) + "\n…" : body)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                if item.isSensitive {
                    Button("Hide", systemImage: "eye.slash") { revealed = false }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Provenance at a glance — kind, masked badge, source app, source device.
    @ViewBuilder private var metaChipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    metaChip(
                        Text(LocalizedStringKey(item.kind.rawValue)),
                        systemImage: item.kind.symbolName)
                    if item.isSensitive {
                        metaChip(Text("Masked"), systemImage: "lock.fill")
                    }
                    if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                        metaChip(
                            Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID)),
                            systemImage: "app.dashed")
                    }
                    if let device = item.sourceDeviceName, !device.isEmpty {
                        metaChip(Text(verbatim: device), systemImage: "desktopcomputer")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func metaChip(_ text: Text, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            text.font(.caption)
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }

    /// Compact board membership: the auto-board suggestion, the boards this clip
    /// is already in as chips, and one "Add to board" that opens the move sheet.
    @ViewBuilder private var boardsSection: some View {
        if let board = suggestedBoard {
            Section {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accent)
                    Text("Add to \(board.name)?").lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Add") {
                        Task {
                            await model.setBoardMembership(item, board: board, member: true)
                            boardIDs = await model.boardMembership(for: item)
                            suggestedBoard = nil
                        }
                    }
                    .buttonStyle(.borderless)
                    Button {
                        suggestedBoard = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Dismiss"))
                }
            }
            .accessibilityIdentifier("board-suggestion")
        }
        Section("Boards") {
            if !currentBoards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        ForEach(currentBoards) { board in
                            HStack(spacing: 5) {
                                BoardDot(board: board, size: 9)
                                board.isSystem
                                    ? Text("Favorites") : Text(verbatim: board.name)
                            }
                            .font(.caption)
                            .padding(.horizontal, GanchoTokens.Spacing.sm)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Button {
                showMoveSheet = true
            } label: {
                Label("Add to board", systemImage: "plus")
            }
            .accessibilityIdentifier("detail-add-to-board")
        }
    }

    /// On-device transforms: deterministic dev actions plus, when available,
    /// Apple-Intelligence Smart Paste. One section, the design's "Smart Actions".
    @ViewBuilder private var smartActionsSection: some View {
        let actions = DevActions.actions(for: item.kind)
        if !actions.isEmpty || canSmartPaste {
            Section {
                ForEach(actions) { action in
                    Button(LocalizedStringKey(action.title)) {
                        actionResult = (try? action.transform(fullText)) ?? ""
                    }
                }
                if let actionResult, !actionResult.isEmpty {
                    Text(actionResult).font(.body.monospaced()).textSelection(.enabled)
                    Button("Copy result", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = actionResult
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                if canSmartPaste {
                    // Smart Paste actions are one tap from the section instead of
                    // buried in a nested menu; Translate stays a submenu (9
                    // languages). `accessibilityIdentifier` kept for the tests.
                    ForEach(SmartPasteAction.allCases) { action in
                        if action == .redactPII || model.smartPasteModelAvailable {
                            Button {
                                runSmartPaste(action)
                            } label: {
                                Label(
                                    LocalizedStringKey(action.titleKey),
                                    systemImage: action.symbolName)
                            }
                            .disabled(isThinking)
                        }
                    }
                    if model.smartPasteModelAvailable {
                        Menu {
                            ForEach(Self.translateLanguageCodes, id: \.self) { code in
                                Button(Self.localizedLanguageName(code)) {
                                    runTranslate(to: Self.englishLanguageName(code))
                                }
                            }
                        } label: {
                            Label("Translate to", systemImage: "globe")
                        }
                        .disabled(isThinking)
                        .accessibilityIdentifier("smart-paste-menu")
                    }
                }
                if isThinking {
                    Label("Thinking…", systemImage: "sparkles").foregroundStyle(.secondary)
                } else if let smartResult, !smartResult.isEmpty {
                    Text(smartResult).font(.body).textSelection(.enabled)
                    Button("Copy result", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = smartResult
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } header: {
                HStack {
                    Text("Smart Actions")
                    Spacer()
                    Text("on-device").foregroundStyle(.tertiary)
                }
                .textCase(nil)
            }
        }
    }

    private static let translateLanguageCodes = [
        "en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh",
    ]
    private static func localizedLanguageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
    private static func englishLanguageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    private func runSmartPaste(_ action: SmartPasteAction) {
        smartResult = nil
        isThinking = true
        Task {
            let result = await model.smartPaste(fullText, action: action)
            isThinking = false
            smartResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    private func runTranslate(to language: String) {
        smartResult = nil
        isThinking = true
        Task {
            let result = await model.smartTranslate(fullText, to: language)
            isThinking = false
            smartResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }
}

/// iOS settings: honest capture explainer + the Shortcuts gallery link.
/// The honest Pro screen for iOS — what Pro unlocks, the current free/Pro
/// state, and a real next step (restore a Universal Purchase, or learn where to
/// buy), so a free-tier limit no longer dead-ends on a note that vanishes.
/// Reachable from Settings and surfaced automatically when a limit is hit.
struct ProInfoView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var restoring = false
    @State private var restoreNote: String?
    private let copy = PaywallCopy.standard

    var body: some View {
        List {
            Section {
                HStack(spacing: GanchoTokens.Spacing.sm) {
                    Image(
                        systemName: model.tier == .pro ? "checkmark.seal.fill" : "seal"
                    )
                    .foregroundStyle(
                        model.tier == .pro ? GanchoTokens.Palette.success : Color.secondary)
                    Text(
                        model.tier == .pro
                            ? "You’re on Gancho Pro" : "You’re on the free plan"
                    )
                    .font(.headline)
                }
            }
            Section("What Pro unlocks") {
                ForEach(copy.proPoints, id: \.self) { point in
                    Label(LocalizedStringKey(point), systemImage: "checkmark")
                        .font(.callout)
                }
            }
            if model.tier != .pro {
                Section {
                    Link(destination: URL(string: "https://gancho.app/#pricing")!) {
                        Label("See Gancho Pro", systemImage: "cart")
                    }
                    .accessibilityIdentifier("see-pro")
                    Button {
                        Task { await restore() }
                    } label: {
                        if restoring {
                            ProgressView()
                        } else {
                            Label("Restore purchase", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(restoring)
                    .accessibilityIdentifier("restore-purchase")
                    if let restoreNote {
                        Text(LocalizedStringKey(restoreNote))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(
                        "Gancho Pro is a one-time purchase, available at gancho.app. Free stays free, forever."
                    )
                }
            }
        }
        .navigationTitle("Gancho Pro")
        .accessibilityIdentifier("pro-info")
    }

    private func restore() async {
        restoring = true
        restoreNote = nil
        let ok = await model.restorePro()
        restoring = false
        restoreNote =
            ok
            ? "Pro restored — enjoy."
            : "No purchase to restore on this Apple ID. Pro is sold at gancho.app."
    }
}

struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(IOSAppModel.self) private var model
    @State private var exportDocument: GanchoArchiveDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var transferNote: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProInfoView()
                    } label: {
                        Label("Gancho Pro", systemImage: "star")
                    }
                    .accessibilityIdentifier("open-pro")
                    NavigationLink {
                        IOSIntelligenceView()
                    } label: {
                        Label("Intelligence", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("open-intelligence")
                    NavigationLink {
                        IOSPrivacyCenterView()
                    } label: {
                        Label("Privacy Center", systemImage: "lock.shield")
                    }
                    .accessibilityIdentifier("open-privacy-center")
                }
                Section("Capture on iPhone") {
                    Text(
                        "Gancho never reads your pasteboard in the background. Capture happens only when you act: the save button, the share sheet, or a Shortcut."
                    )
                    .font(.footnote)
                }
                Section("Shortcuts") {
                    Link(destination: URL(string: "https://gancho.app/shortcuts")!) {
                        Label("Example Shortcuts gallery", systemImage: "square.stack.3d.up")
                    }
                }
                Section("Your history") {
                    Button {
                        startBackup()
                    } label: {
                        Label("Back up history…", systemImage: "arrow.down.doc")
                    }
                    .accessibilityIdentifier("backup-history")
                    Button {
                        showImporter = true
                    } label: {
                        Label("Restore from backup…", systemImage: "arrow.up.doc")
                    }
                    .accessibilityIdentifier("restore-history")
                    Text("Backups are .ganchoarchive files on your device — never uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let transferNote {
                        Text(verbatim: transferNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "gancho-force-pro") },
                                set: { model.setDebugForcePro($0) })
                        ) {
                            Text(verbatim: "Force Pro (QA)")
                        }
                        .accessibilityIdentifier("debug-force-pro")
                        Button {
                            model.resetSyncAndRepull()
                        } label: {
                            Text(verbatim: "Reset & re-pull sync")
                        }
                        .accessibilityIdentifier("debug-reset-sync")
                    } header: {
                        Text(verbatim: "Debug")
                    }
                #endif
            }
            .navigationTitle(Text("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showExporter, document: exportDocument, contentType: .folder,
                defaultFilename: "gancho-backup.ganchoarchive"
            ) { result in
                if case .failure = result {
                    transferNote = String(localized: "Couldn’t save the backup.")
                }
                exportDocument = nil
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    if let summary = await model.restoreBackup(from: url) {
                        transferNote = String(
                            localized:
                                "Restored \(summary.inserted) clips (\(summary.skippedDuplicates) already here)."
                        )
                    } else {
                        transferNote = String(localized: "That backup couldn’t be restored.")
                    }
                }
            }
        }
    }

    /// Build the .ganchoarchive in a temp dir, then hand it to the system
    /// exporter — the file lands wherever the user picks in Files. Off-device
    /// only if THEY choose an off-device location.
    private func startBackup() {
        Task {
            guard let url = await model.makeBackupArchive(),
                let document = try? GanchoArchiveDocument(directory: url)
            else {
                transferNote = String(localized: "Couldn’t prepare the backup.")
                return
            }
            exportDocument = document
            showExporter = true
        }
    }
}

/// Wraps a `.ganchoarchive` directory as a single document so `fileExporter`
/// can write it out (and macOS can read it back). Stores the URL (Sendable) and
/// builds the directory `FileWrapper` lazily at write time — the format is a
/// directory of clips.json, manifest.json, and the blobs. Export-only; restore
/// goes through `fileImporter`, so the read path is never exercised.
struct GanchoArchiveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    private let directory: URL

    init(directory url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        directory = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: directory)
    }
}

/// The trust dashboard on iPhone: the 0-outgoing-requests claim, local counters
/// from the on-device store, and an honest note on how capture works on iOS.
/// Every number is computed locally — this screen makes no network requests.
/// (macOS's Privacy Center has an "ignored" ledger and MCP log; iOS captures
/// only on explicit intent, so those don't apply here.)
struct IOSPrivacyCenterView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var captured = 0
    @State private var masked = 0
    @State private var expired = 0
    @State private var synced = 0

    private var weekAgo: Date { Date(timeIntervalSinceNow: -7 * 86_400) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "lock.shield.fill").font(.title2)
                        Spacer()
                        Text(verbatim: "0")
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                    }
                    Text("Outgoing content requests")
                        .font(.headline)
                    Text("Your clipboard never leaves this iPhone.")
                        .font(.footnote)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.vertical, GanchoTokens.Spacing.xs)
                .listRowBackground(Rectangle().fill(GanchoTokens.Palette.success.gradient))
            }

            Section("This week") {
                LabeledContent("Clips captured", value: "\(captured)")
                LabeledContent("Secrets masked", value: "\(masked)")
                LabeledContent("Items self-expired", value: "\(expired)")
                LabeledContent("Items synchronized", value: "\(synced)")
            }

            Section("Capture on iPhone") {
                Text(
                    "Gancho never reads your pasteboard in the background. Capture happens only when you act: the save button, the share sheet, or a Shortcut."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Recent issues") {
                let issues = Array(model.diagnostics.entries.reversed())
                if issues.isEmpty {
                    Text("No issues recorded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(issues) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.message).font(.footnote)
                            HStack(spacing: 4) {
                                Text(verbatim: entry.category)
                                Text(verbatim: "·")
                                Text(entry.at, format: .relative(presentation: .named))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button("Copy for support") {
                        UIPasteboard.general.string =
                            issues
                            .map { "\($0.at): [\($0.category)] \($0.message)" }
                            .joined(separator: "\n")
                    }
                    .accessibilityIdentifier("copy-diagnostics")
                }
                Text("Recent technical issues only — content-free, nothing about your clips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy Center")
        .accessibilityIdentifier("ios-privacy-center")
        .task { await refresh() }
    }

    /// Every counter is a local query against the on-device store. No network.
    private func refresh() async {
        captured = (try? await model.store.count()) ?? 0
        guard let grdb = model.store as? GRDBClipboardStore else { return }
        synced = (try? await grdb.syncedCount()) ?? 0
        expired = (try? await grdb.purgedItemCount(since: weekAgo)) ?? 0
        masked =
            (try? await grdb.search(
                ClipSearchQuery(text: "●●●●", mode: .exact), limit: 500
            ).count) ?? 0
    }
}

/// `UIPasteControl` wrapper: the system button that pastes WITHOUT any
/// banner or alert, because the OS itself mediates the user's tap.
struct PasteControlView: UIViewRepresentable {
    let onPaste: ([NSItemProvider]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        // Styled as the design's green "Save" — a system paste button that
        // grants one-time access on tap, no "pasted from" banner.
        let config = UIPasteControl.Configuration()
        config.cornerStyle = .capsule
        config.displayMode = .iconAndLabel
        config.baseBackgroundColor = UIColor(GanchoTokens.Palette.accent)
        config.baseForegroundColor = .white
        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator.target
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {}

    @MainActor
    final class Coordinator {
        let target: PasteTarget

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            target = PasteTarget(onPaste: onPaste)
        }
    }

    /// Hidden responder the control targets; accepts text, URLs, images.
    @MainActor
    final class PasteTarget: UIResponder {
        private let onPaste: ([NSItemProvider]) -> Void

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
                UTType.plainText.identifier,
                UTType.url.identifier,
                UTType.image.identifier,
            ])
        }

        override func paste(itemProviders: [NSItemProvider]) {
            onPaste(itemProviders)
        }
    }
}
