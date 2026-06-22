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

    var body: some Scene {
        WindowGroup {
            Group {
                // iPad gets the sidebar layout; iPhone keeps the stack.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    IPadSplitView()
                } else {
                    CaptureView()
                }
            }
            .environment(model)
            // Widget deep links (`gancho://clip/<id>`) open the right clip.
            .onOpenURL { model.handleDeepLink($0) }
            // Brand-green accent (iOS has no per-app OS accent picker, so green
            // is the default); the Synced check and success states use it too.
            .ganchoTinted()
        }
    }
}

@Observable
@MainActor
final class IOSAppModel {
    var captures: [ClipItem] = []
    var hints = IntentionalPasteboardSource.ContentHints()
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

    /// Sync boundary: pull-to-refresh forces a cycle. A `NoopSyncEngine`
    /// until the user is Pro on an iCloud-signed-in device; the adapter swaps
    /// in transparently — the pull-to-refresh UI contract is identical.
    private var syncEngine: any SyncEngine = NoopSyncEngine()
    private var syncEnabled = false
    private(set) var syncStatus: SyncStatus = .idle
    private var tier: UserTier = .free
    private let purchases = StoreKitPurchaseHandler()

    init() {
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
        // adapter gives it real semantics on the device-day.
        try? await syncEngine.start()
        await refreshHints()
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

    /// Creates a board and queues its metadata for sync, so it shows up on the
    /// user's other devices. The built-in Favorites board never counts against
    /// the free limit.
    func createBoard(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let grdb = store as? GRDBClipboardStore else { return }
        Task {
            let count = (try? await grdb.pinboards().filter { !$0.isSystem }.count) ?? 0
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro) else {
                flashNote(String(localized: "Upgrade to Pro for more boards"))
                return
            }
            if let board = try? await grdb.createPinboard(name: trimmed) {
                await syncEngine.enqueue(boards: [board])
            }
            await refreshBoards()
        }
    }

    /// The boards a clip belongs to — drives the detail screen's checkmarks.
    func boardMembership(for item: ClipItem) async -> Set<UUID> {
        guard let grdb = store as? GRDBClipboardStore else { return [] }
        return (try? await grdb.boardIDs(forClip: item.id)) ?? []
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

    func search() async {
        let grdb = store as? GRDBClipboardStore
        guard let grdb, !query.isEmpty else {
            if let board = selectedBoardID, let grdb {
                captures = (try? await grdb.items(inBoard: board)) ?? []
            } else {
                captures = (try? await store.items(offset: 0, limit: 50)) ?? []
            }
            if let kindFilter {
                captures = captures.filter { $0.kind == kindFilter }
            }
            return
        }
        let kinds: Set<ClipContentKind>? = kindFilter.map { [$0] }
        captures =
            (try? await grdb.search(
                ClipSearchQuery(text: query, kinds: kinds, boardID: selectedBoardID), limit: 50))
            ?? []
    }

    /// 1-tap copy with haptic confirmation.
    func copyToPasteboard(_ item: ClipItem) async {
        guard let content = try? await store.content(for: item.id) else { return }
        switch content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .binary(let data, _):
            UIPasteboard.general.image = UIImage(data: data)
        case .fileReferences(let paths):
            UIPasteboard.general.string = paths.joined(separator: "\n")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        let directory = SharedStorageLocation.storeDirectory(
            appGroupID: SharedInbox.appGroupID)
        return (try? GRDBClipboardStore(directory: directory)) ?? InMemoryClipboardStore()
    }()

    /// Metadata-only refresh — safe on every activation, never alerts.
    func refreshHints() async {
        hints = await source.hints()
        captures = (try? await store.items(offset: 0, limit: 50)) ?? []
    }

    /// The user-initiated read (system paste transparency applies).
    func saveClipboard() async {
        guard let capture = source.captureNow() else { return }
        await ingest(capture)
    }

    private func flashNote(_ text: String) {
        saveNote = text
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
        flashNote(
            stored?.id == item.id
                ? String(localized: "Saved") : String(localized: "Already in your history"))
        captures = (try? await store.items()) ?? []
        reloadWidgets()
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
            return SensitiveIngestionPolicy.decorate(
                item, finding: SensitiveDataDetector().detect(text), originalText: text)
        }
    }
}

struct CaptureView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showNewBoard = false
    @State private var newBoardName = ""
    @State private var path: [UUID] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            List {
                syncStatusSection
                Section("Pasteboard") {
                    hintsRow
                    Button("Save clipboard", systemImage: "square.and.arrow.down") {
                        Task { await model.saveClipboard() }
                    }
                    .accessibilityIdentifier("capture-button")
                    PasteControlView { providers in
                        model.ingest(providers: providers)
                    }
                    .frame(height: 36)
                    .accessibilityIdentifier("paste-control")
                }

                Section("History") {
                    if model.captures.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.captures) { item in
                            NavigationLink(value: item.id) {
                                ClipCard(item: item)
                            }
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
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.query, prompt: Text("Search your clipboard"))
            .onChange(of: model.query) { _, _ in Task { await model.search() } }
            .navigationTitle("Gancho")
            .navigationDestination(for: UUID.self) { id in
                if let item = model.captures.first(where: { $0.id == id }) {
                    ClipDetailView(item: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    boardFilterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    kindFilterMenu
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .sheet(isPresented: $showSettings) { IOSSettingsView() }
            .alert("New board", isPresented: $showNewBoard) {
                TextField("Board name", text: $newBoardName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { model.createBoard(named: newBoardName) }
            }
            .refreshable { await model.forceSync() }
            .accessibilityIdentifier("capture-screen")
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await activate() }
        }
        .onChange(of: model.deepLinkClipID) { _, id in
            guard let id else { return }
            path = [id]
            model.deepLinkClipID = nil
        }
    }

    /// Board picker (a higher axis than the type filter): All clips · Favorites
    /// · user boards. Pinned clips still float to the top within each.
    private var boardFilterMenu: some View {
        @Bindable var model = self.model
        return Menu {
            Picker("Board", selection: $model.selectedBoardID) {
                Label("All clips", systemImage: "tray.full").tag(UUID?.none)
                ForEach(model.boards) { board in
                    Label {
                        board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
                    } icon: {
                        Image(systemName: board.sfSymbol)
                    }
                    .tag(UUID?.some(board.id))
                }
            }
            Divider()
            Button {
                newBoardName = ""
                showNewBoard = true
            } label: {
                Label("New board…", systemImage: "plus")
            }
            .accessibilityIdentifier("board-new")
        } label: {
            Image(systemName: model.selectedBoardID == nil ? "square.stack" : "square.stack.fill")
        }
        .onChange(of: model.selectedBoardID) { _, _ in Task { await model.search() } }
        .accessibilityLabel(Text("Board"))
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

    /// Honest about the platform: no background capture exists on iOS.
    private var emptyState: some View {
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

    /// Foreground activation: metadata hints + extension inbox, no reads.
    private func activate() async {
        await model.refreshHints()
        await model.drainSharedInbox()
        await model.refreshBoards()
        await model.search()
    }

    @ViewBuilder
    private var hintsRow: some View {
        if let note = model.saveNote {
            Label(note, systemImage: "checkmark.circle")
                .foregroundStyle(GanchoTokens.Palette.success)
                .accessibilityIdentifier("save-note")
        }
        if model.hints.hasContent {
            // The capture banner: detection happened WITHOUT reading; the
            // button is the explicit consent that triggers the read.
            HStack {
                Label(hintText, systemImage: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save it") {
                    Task { await model.saveClipboard() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .accessibilityIdentifier("pasteboard-hints")
        } else {
            Label("Pasteboard is empty", systemImage: "doc.on.clipboard")
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("pasteboard-hints")
        }
    }

    /// Compact iCloud sync indicator (no suggestion line — kept minimal on
    /// iOS; pull-to-refresh forces a sync). Renders nothing when sync is off.
    @ViewBuilder
    private var syncStatusSection: some View {
        switch model.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            syncRow(Text("Syncing…"), "arrow.triangle.2.circlepath")
        case .upToDate:
            syncRow(Text("Synced"), "checkmark.icloud", tint: GanchoTokens.Palette.success)
        case .pending(let count):
            syncRow(
                Text("\(Text("Waiting to sync")) · \(String(count))"), "arrow.up.circle")
        case .paused(let cause):
            syncRow(Text(causeText(cause)), "pause.circle", tint: GanchoTokens.Palette.warning)
        case .failed(let cause):
            syncRow(
                Text(causeText(cause)), "exclamationmark.icloud", tint: GanchoTokens.Palette.danger)
        }
    }

    private func syncRow(_ text: Text, _ symbol: String, tint: Color = .secondary) -> some View {
        Section {
            Label {
                text
            } icon: {
                // "Synced" reads green (a state); paused/failed warn — like macOS.
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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

    private var hintText: String {
        var parts: [String] = []
        if model.hints.probableWebURL { parts.append(String(localized: "link")) }
        if model.hints.probableWebSearch { parts.append(String(localized: "search text")) }
        if model.hints.number { parts.append(String(localized: "number")) }
        let detail = parts.isEmpty ? String(localized: "content") : parts.joined(separator: ", ")
        return String(localized: "Has \(detail) — not read yet")
    }
}

/// Per-kind detail: full content, dev actions, one-tap copy with haptics.
struct ClipDetailView: View {
    @Environment(IOSAppModel.self) private var model
    let item: ClipItem
    @State private var fullText = ""
    @State private var actionResult: String?
    @State private var boardIDs: Set<UUID> = []

    var body: some View {
        List {
            Section {
                TypeBadge(kind: item.kind)
                Text(fullText.isEmpty ? item.preview : fullText)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
            }

            let actions = DevActions.actions(for: item.kind)
            if !actions.isEmpty {
                Section("Actions") {
                    ForEach(actions) { action in
                        Button(LocalizedStringKey(action.title)) {
                            actionResult = (try? action.transform(fullText)) ?? ""
                        }
                    }
                    if let actionResult, !actionResult.isEmpty {
                        Text(actionResult)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button("Copy result", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = actionResult
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }

            if !model.boards.isEmpty {
                Section("Boards") {
                    ForEach(model.boards) { board in
                        Button {
                            Task {
                                await model.setBoardMembership(
                                    item, board: board, member: !boardIDs.contains(board.id))
                                boardIDs = await model.boardMembership(for: item)
                            }
                        } label: {
                            HStack {
                                Label {
                                    board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
                                } icon: {
                                    Image(systemName: board.sfSymbol)
                                }
                                Spacer()
                                if boardIDs.contains(board.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(GanchoTokens.Palette.accent)
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("detail-board-\(board.id.uuidString)")
                    }
                }
            }

            Section {
                Button("Copy", systemImage: "doc.on.doc") {
                    Task { await model.copyToPasteboard(item) }
                }
                .accessibilityIdentifier("detail-copy")
            }
        }
        .navigationTitle(Text(LocalizedStringKey(item.kind.rawValue)))
        .task {
            if case .text(let text)? = try? await model.store.content(for: item.id) {
                fullText = text
            }
        }
        .task {
            await model.refreshBoards()
            boardIDs = await model.boardMembership(for: item)
        }
    }
}

/// iOS settings: honest capture explainer + the Shortcuts gallery link.
struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
        @Environment(IOSAppModel.self) private var model
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
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
        }
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
        let control = UIPasteControl()
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
