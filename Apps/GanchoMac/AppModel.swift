import AppIntents
import AppKit
import ApplicationServices
import ClipboardCore
import GanchoAI
import GanchoKit
import GanchoSync
import GanchoTelemetry
import KeyboardShortcuts
import SwiftUI

/// The app's appearance override — Auto follows the system, Light/Dark force
/// it. Mirrors the design's Auto/Light/Dark control.
enum AppearancePreference: String, CaseIterable {
    case auto
    case light
    case dark

    /// The app-wide AppKit appearance to apply (nil = follow the system).
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Central app state: wires monitor → classifier → GRDB store, owns the
/// paste-back service, preferences, retention, and the panel lifecycle.
@Observable
@MainActor
final class AppModel {
    private(set) var recentItems: [ClipItem] = []
    var monitorStatus: MonitorStatus { monitor.status }

    /// Durable store under Application Support; falls back to in-memory if
    /// the disk store cannot open (never block launch on a storage error).
    let store: any ClipboardStore
    let grdbStore: GRDBClipboardStore?
    /// Cached image thumbnails for the history rows and the peek.
    let thumbnails: ClipThumbnailStore

    let monitor: MacPasteboardMonitor
    let pasteBack = PasteBackService()
    let privacyEvents = InMemoryPrivacyEventRecorder()
    let panel = PanelController()
    /// Transient HUD for action feedback (copy-only paste, pin/unpin).
    let toasts = ToastPresenter()
    let welcomeWindow = WelcomeWindowController()
    let privacyCenterWindow = PrivacyCenterWindowController()
    let paywallWindow = PaywallWindowController()
    let permissionWindow = PasteboardPermissionWindowController()
    let libraryWindow = LibraryWindowController()
    let settingsWindow = SettingsWindowController()
    let purchases = StoreKitPurchaseHandler()
    let telemetry: TelemetryPipeline

    /// Encrypted iCloud sync, behind the boundary. A `NoopSyncEngine` until
    /// the user is Pro on an iCloud-signed-in device; `configureSync()` swaps
    /// in the real adapter and back as the tier or account changes.
    private(set) var sync: any SyncEngine = NoopSyncEngine()
    private var syncEnabled = false

    /// Current sync state for the UI (panel indicator + Privacy Center).
    private(set) var syncStatus: SyncStatus = .idle

    /// Local MCP server opt-in + scope, persisted as a file in the store
    /// directory (the `gancho` CLI reads the same file). OFF by default.
    private(set) var mcpConfig: MCPServerConfig = .init()

    /// Entitlement — StoreKit is the source of truth; the persisted value is
    /// only the cached default used until StoreKit answers on launch.
    var tier: UserTier {
        didSet { tier.save(to: defaults) }
    }

    /// Analytics opt-out. Default opted-in (anonymous buckets only, per the
    /// product plan); the sender is created at launch, so a change applies
    /// on the next launch.
    var telemetryOptedOut: Bool {
        didSet {
            defaults.set(telemetryOptedOut, forKey: "telemetry-opted-out")
            telemetry.setOptedOut(telemetryOptedOut)
        }
    }

    private let classifier = RuleClassifier()
    private let sensitiveDetector = SensitiveDataDetector()
    private let defaults = UserDefaults.standard
    private var retentionTimer: Timer?
    private let screenShareDetector = ScreenShareDetector()
    private var screenShareTimer: Timer?
    private var uiTestPanelObserver: NSObjectProtocol?

    /// Opt-out for the share auto-pause (on by default).
    var autoPauseOnScreenShare: Bool {
        didSet { defaults.set(autoPauseOnScreenShare, forKey: "auto-pause-screen-share") }
    }

    var preferences: CapturePreferences {
        didSet {
            monitor.preferences = preferences
            preferences.save(to: defaults)
        }
    }

    var retentionPolicy: RetentionPolicy {
        didSet { retentionPolicy.save(to: defaults) }
    }

    /// Menu-bar agent by default; Settings can surface the Dock icon.
    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "show-in-dock")
            applyActivationPolicy()
        }
    }

    /// App appearance: Auto follows the system, Light/Dark force it.
    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    init() {
        let directory = SharedStorageLocation.macAppStoreDirectory
        let grdb = try? GRDBClipboardStore(directory: directory)
        self.grdbStore = grdb
        self.store = grdb ?? InMemoryClipboardStore()
        let resolvedStore = self.store
        self.thumbnails = ClipThumbnailStore(imageData: { id in
            if case .binary(let data, _)? = try? await resolvedStore.content(for: id) {
                return data
            }
            return nil
        })
        self.mcpConfig = MCPServerConfig.load(fromStoreDirectory: directory)

        let loadedPreferences = CapturePreferences.load(from: defaults)
        preferences = loadedPreferences
        retentionPolicy = RetentionPolicy.load(from: defaults)
        // Default to a menu-bar agent (.accessory). This app is LSUIElement;
        // forcing .regular (what the old Debug-only "show in Dock" default did)
        // leaves the status item registered but never placed in the menu bar —
        // the icon silently vanishes. Opt into the Dock explicitly instead.
        showInDock = defaults.bool(forKey: "show-in-dock")
        appearance =
            AppearancePreference(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .auto
        autoPauseOnScreenShare =
            defaults.object(forKey: "auto-pause-screen-share") as? Bool ?? true
        tier = UserTier.load(from: defaults)

        // Telemetry: no sender is built when opted out, so the SDK never
        // initializes and nothing leaves the device. Buckets only either way.
        let optedOut = defaults.bool(forKey: "telemetry-opted-out")
        telemetryOptedOut = optedOut
        let sender: (any TelemetrySending)? =
            optedOut ? nil : TelemetryDeckSender(appID: GanchoTelemetryConfig.appID)
        telemetry = TelemetryPipeline(sender: sender, optedOut: optedOut)

        monitor = MacPasteboardMonitor(preferences: loadedPreferences)
        monitor.denylist = SourceAppDenylist.load(from: defaults)
        monitor.onCapture = { [weak self] capture in
            self?.ingest(capture)
        }
        monitor.onIgnore = { [weak self] reason in
            self?.privacyEvents.record(IgnoredCaptureEvent(reason: reason))
        }
        monitor.start()
        scheduleRetention()
        scheduleScreenShareWatch()
        panel.attach(model: self)
        applyActivationPolicy()
        // Intents resolve the SAME model instance the UI uses.
        AppDependencyManager.shared.add(dependency: self)
        KeyboardShortcuts.onKeyUp(for: .togglePrivateMode) { [weak self] in
            self?.togglePrivateMode()
        }
        KeyboardShortcuts.onKeyUp(for: .cyclicPaste) { [weak self] in
            self?.cyclicPaste()
        }
        KeyboardShortcuts.onKeyUp(for: .pasteFromStack) { [weak self] in
            self?.pasteNextFromStack()
        }

        // StoreKit drives the tier: the listener catches renewals/refunds,
        // and a launch refresh reconciles against current entitlements.
        purchases.onTierChange = { [weak self] tier in
            self?.applyTier(tier)
        }
        Task {
            let entitled = await purchases.currentTier()
            if entitled != tier { applyTier(entitled) }
            #if DEBUG
                if DebugFlags.forcePro, tier != .pro { applyTier(.pro) }
            #endif
            configureSync()
        }
        telemetry.record(.appLaunched)
        Task { await refreshRecents() }

        // UI-test hook: deterministic panel access without the global hotkey.
        if CommandLine.arguments.contains("-open-panel-on-launch") {
            NSApplication.shared.setActivationPolicy(.regular)
            uiTestPanelObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    panel.show(model: self)
                    _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                    try? await Task.sleep(for: .milliseconds(250))
                    panel.show(model: self)
                    _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if !panel.isVisible { panel.show(model: self) }
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            }
        } else if !defaults.bool(forKey: "has-seen-welcome") {
            Task { welcomeWindow.show(model: self) }
        } else if monitor.status == .deniedByPrivacySettings {
            Task { permissionWindow.show(model: self) }
        }
    }

    private func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    // MARK: - Capture pipeline

    private func ingest(_ capture: PasteboardCapture) {
        var (item, content) = Self.makeItem(
            from: capture, classifier: classifier, detector: sensitiveDetector,
            sensitiveLifetime: retentionPolicy.sensitiveLifetime)
        // Universal Clipboard interop: badge persists as a tag so sync can
        // recognize already-synced arrivals and the UI can show the badge.
        if capture.isFromUniversalClipboard {
            item.tags.append("universal-clipboard")
        }
        // Bucketized analytics: kind + a length BUCKET, never the content.
        let length: Int
        switch content {
        case .text(let text): length = text.count
        case .binary(let data, _): length = data.count
        default: length = item.preview.count
        }
        telemetry.record(
            .itemCaptured(
                type: item.kind.rawValue,
                lengthBucket: .init(characterCount: length)))
        Task {
            _ = try? await store.insert(item, content: content)
            await sync.enqueue([item])
            await refreshRecents()
            enrich(item, content: content)
        }
    }

    /// Pro-tier async enrichment — never blocks capture: OCR makes image
    /// clips searchable; the tiered annotator titles text clips.
    private func enrich(_ item: ClipItem, content: ClipContent?) {
        guard tier == .pro, let grdbStore, !item.isSensitive else { return }
        Task(priority: .utility) {
            switch content {
            case .binary(let data, _) where item.kind == .image:
                if let text = try? await ImageTextExtractor().extractText(from: data) {
                    _ = try? await grdbStore.attachExtractedText(id: item.id, text: text)
                }
            case .text(let text) where item.title.isEmpty:
                if let annotation = try? await TieredClipAnnotator().annotate(text) {
                    _ = try? await grdbStore.updateTitle(id: item.id, title: annotation.title)
                    await refreshRecents()
                }
                // Semantic vector (the embedder caches its model after the
                // first call — warm-up cost measured in the AI spike).
                if let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
                    let vector = try? embedder.vector(for: String(text.prefix(1_000)))
                {
                    _ = try? await grdbStore.saveEmbedding(clipID: item.id, vector: vector)
                }
            default:
                break
            }
        }
    }

    func refreshRecents() async {
        recentItems = (try? await store.items(offset: 0, limit: 50)) ?? []
        publishLastCopied()
    }

    /// Publish the most recent clip's preview to the menu-bar helper's recent
    /// row. Private mode clears it; sensitive clips send only a mask — full
    /// content never crosses to the helper.
    private func publishLastCopied() {
        guard !preferences.isPrivateModePaused, let top = recentItems.first else {
            GanchoMenuBarBridge.writeLastCopied(preview: nil, label: "", at: Date())
            return
        }
        GanchoMenuBarBridge.writeLastCopied(
            preview: top.isSensitive ? "•••" : top.preview,
            label: String(localized: "Last copied"), at: top.createdAt)
    }

    /// Capture payload → classified, normalized, sensitivity-decorated clip
    /// plus its full content for the store.
    static func makeItem(
        from capture: PasteboardCapture,
        classifier: RuleClassifier,
        detector: SensitiveDataDetector,
        sensitiveLifetime: TimeInterval
    ) -> (ClipItem, ClipContent?) {
        switch capture.payload {
        case .image(let data, let typeIdentifier):
            let item = ClipItem(
                kind: .image,
                preview: "Image (\(ByteSize.formatted(data.count)))",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .binary(data: data, typeIdentifier: typeIdentifier))
        case .fileReferences(let urls):
            let paths = urls.map(\.path)
            let item = ClipItem(
                kind: .fileReference,
                preview: urls.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: ClipItem.hash(of: paths.joined(separator: "\n"), kind: .fileReference),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .fileReferences(paths))
        case .richText(let rtf, let plain):
            let text = plain ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime)
            return (
                item,
                item.isSensitive ? .text(text) : .binary(data: rtf, typeIdentifier: "public.rtf")
            )
        default:
            let text = capture.textRepresentation ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime)
            return (item, .text(ContentNormalizer.canonicalText(text, kind: item.kind)))
        }
    }

    private static func decoratedTextItem(
        text: String, capture: PasteboardCapture, classifier: RuleClassifier,
        detector: SensitiveDataDetector, sensitiveLifetime: TimeInterval
    ) -> ClipItem {
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = ClipItem(
            kind: kind,
            preview: String(canonical.prefix(120)),
            contentHash: ClipItem.hash(of: canonical, kind: kind),
            sourceAppBundleID: capture.sourceAppBundleID)
        return SensitiveIngestionPolicy.decorate(
            item, finding: detector.detect(canonical), originalText: canonical,
            sensitiveLifetime: sensitiveLifetime)
    }

    // MARK: - Actions

    /// Paste a stored clip into the frontmost app (panel Enter / menu click).
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            guard let content = try? await store.content(for: item.id) else { return }
            panel.hide()
            // Give focus one beat to return to the previous app.
            try? await Task.sleep(for: .milliseconds(80))
            switch pasteBack.paste(content, asPlainText: asPlainText) {
            case .copiedOnly:
                showCopyOnlyToast()
            case .pasted:
                if asPlainText { toasts.show(GanchoToast(message: "Pasted as plain text")) }
            }
            // Activation metric (local, content-free): first paste-back ever.
            if defaults.object(forKey: "first-pasteback-at") == nil {
                defaults.set(Date().timeIntervalSince1970, forKey: "first-pasteback-at")
            }
            defaults.set(
                defaults.integer(forKey: "pasteback-count") + 1, forKey: "pasteback-count")
            telemetry.record(
                .itemPastedBack(
                    ageBucket: .init(age: Date().timeIntervalSince(item.createdAt))))
            _ = try? await store.insert(item, content: nil)  // move-to-top
            await refreshRecents()
        }
    }

    /// Paste with a pure transform applied at paste time.
    func paste(_ item: ClipItem, transform: PasteTransform) {
        Task {
            guard case .text(let text)? = try? await store.content(for: item.id) else {
                paste(item, asPlainText: transform == .plainText)
                return
            }
            panel.hide()
            try? await Task.sleep(for: .milliseconds(80))
            if pasteBack.paste(.text(transform.apply(to: text)), asPlainText: true) == .copiedOnly {
                showCopyOnlyToast()
            }
            _ = try? await store.insert(item, content: nil)
            await refreshRecents()
        }
    }

    /// Paste-back degraded to copy-only (Accessibility off): tell the user and
    /// offer a one-tap path to enable it.
    private func showCopyOnlyToast() {
        toasts.show(
            GanchoToast(
                message: "Copied — enable Accessibility to paste directly",
                style: .warning,
                action: ToastAction(title: "Enable") { [weak self] in
                    self?.requestAccessibilityPrompt()
                }),
            duration: .seconds(5))
    }

    /// Show the system Accessibility prompt (it pre-adds Gancho to the list) and
    /// open the Accessibility settings pane, so the user can enable paste-back
    /// without hunting for the app.
    func requestAccessibilityPrompt() {
        // `kAXTrustedCheckOptionPrompt` is imported as a global var that Swift 6
        // flags as not concurrency-safe; its value is this stable API string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Insert a snippet by keyword: fill its {fields} with the given values,
    /// paste the result, and bump the usage count. Empty values means a
    /// non-template snippet (or fields left blank → their defaults apply).
    func pasteSnippet(_ snippet: ClipItem, values: [String: String]) {
        guard let grdbStore else { return }
        Task {
            guard case .text(let body)? = try? await store.content(for: snippet.id) else { return }
            let filled = SnippetTemplate.fill(body, values: values)
            panel.hide()
            try? await Task.sleep(for: .milliseconds(80))
            if pasteBack.paste(.text(filled), asPlainText: false) == .copiedOnly {
                showCopyOnlyToast()
            }
            try? await grdbStore.incrementUses(id: snippet.id)
            await refreshRecents()
        }
    }

    /// The snippet invoked by an exact keyword, if any (the panel's expansion).
    func snippet(matchingKeyword keyword: String) async -> ClipItem? {
        (try? await grdbStore?.snippet(matchingKeyword: keyword)) ?? nil
    }

    /// Cyclic quick-paste: each invocation pastes the NEXT history item
    /// (wraps around). Resets to the top after 8s of silence.
    private var cycleIndex = 0
    private var lastCycleAt = Date.distantPast

    func cyclicPaste() {
        if Date().timeIntervalSince(lastCycleAt) > 8 { cycleIndex = 0 }
        lastCycleAt = Date()
        guard !recentItems.isEmpty else { return }
        let item = recentItems[cycleIndex % recentItems.count]
        cycleIndex += 1
        paste(item)
    }

    // MARK: - Paste stack (local; cross-device rides sync)

    /// FIFO queue: load several clips, then paste them in order — each
    /// stack-paste pops the front. Survives only the session (by design:
    /// a stack is a working set, not history).
    private(set) var pasteStack: [ClipItem] = []

    func pushToStack(_ item: ClipItem) {
        pasteStack.append(item)
        toasts.show(GanchoToast(message: "Added to paste stack"))
    }

    func clearStack() {
        pasteStack.removeAll()
    }

    func pasteNextFromStack() {
        guard !pasteStack.isEmpty else { return }
        let item = pasteStack.removeFirst()
        paste(item)
    }

    /// Sync-aware delete: when iCloud sync is active, leave a tombstone and
    /// propagate the deletion; otherwise a plain local delete.
    func delete(_ item: ClipItem) {
        Task {
            if syncEnabled, let grdbStore {
                _ = try? await grdbStore.deleteForSync(id: item.id)
                await sync.enqueueDeletion(ids: [item.id])
            } else {
                _ = try? await store.delete(id: item.id)
            }
            await refreshRecents()
        }
    }

    func togglePause() {
        if monitor.status == .running {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    func togglePrivateMode() {
        preferences.isPrivateModePaused.toggle()
    }

    func ignoreNextCopy() {
        monitor.ignoreNextCopy()
    }

    // MARK: - Purchases

    /// Applies a tier from StoreKit and releases any archived clips when the
    /// user becomes Pro (free-tier archiving is reversible — no data hostage).
    private func applyTier(_ newTier: UserTier) {
        tier = newTier
        configureSync()
        guard let grdbStore else { return }
        Task {
            _ = try? await TierEnforcement(store: grdbStore).enforce(tier: newTier)
            await refreshRecents()
        }
    }

    // MARK: - Sync

    /// Arms or disarms iCloud sync to match the current tier + account. Only
    /// rebuilds when the enablement decision flips, so it is safe to call on
    /// launch and on every tier change.
    private func configureSync() {
        guard let grdbStore else { return }
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let cloudKitEntitled = CloudKitEntitlements.currentTaskAllowsSync()
        let enable = SyncEnablement.shouldEnable(
            tier: tier,
            iCloudAvailable: iCloudAvailable,
            hasCloudKitEntitlement: cloudKitEntitled)
        guard enable != syncEnabled else { return }
        syncEnabled = enable

        let previous = sync
        Task { await previous.stop() }
        let stateURL = URL.applicationSupportDirectory
            .appendingPathComponent("Gancho", isDirectory: true)
            .appendingPathComponent("sync-state.plist")
        sync = SyncEngineFactory.make(
            store: grdbStore, tier: tier, iCloudAvailable: iCloudAvailable,
            hasCloudKitEntitlement: cloudKitEntitled,
            stateStore: .file(at: stateURL),
            onStatus: { [weak self] status in
                Task { @MainActor in self?.applySyncStatus(status) }
            })
        if enable {
            let engine = sync
            Task { try? await engine.start() }
        } else {
            syncStatus = .idle
        }
    }

    /// Applies a status from the engine: updates the indicator and logs a
    /// metadata-only milestone (synced/paused/failed) to the Privacy Center.
    private func applySyncStatus(_ status: SyncStatus) {
        syncStatus = status
        if let event = Self.syncEvent(for: status) {
            privacyEvents.record(sync: event)
        }
    }

    private static func syncEvent(for status: SyncStatus) -> SyncActivityEvent? {
        switch status {
        case .idle, .syncing, .pending: nil
        case .upToDate: SyncActivityEvent(kind: .synced)
        case .paused(let cause): SyncActivityEvent(kind: .paused, cause: cause)
        case .failed(let cause): SyncActivityEvent(kind: .failed, cause: cause)
        }
    }

    /// User-triggered sync (the Privacy Center "Force sync" button).
    func forceSync() {
        let engine = sync
        Task { try? await engine.start() }
    }

    // MARK: - Local MCP server

    /// Turns local agent access on/off. Persisting OFF leaves the `gancho mcp`
    /// server running for connected clients but serving zero tools.
    func setMCPEnabled(_ enabled: Bool) {
        updateMCPConfig { $0.isEnabled = enabled }
    }

    func setMCPScope(_ scope: MCPAccessScope) {
        updateMCPConfig { $0.scope = scope }
    }

    private func updateMCPConfig(_ mutate: (inout MCPServerConfig) -> Void) {
        var config = mcpConfig
        mutate(&config)
        mcpConfig = config
        try? config.save(toStoreDirectory: SharedStorageLocation.macAppStoreDirectory)
    }

    /// Recent MCP/CLI accesses for the Privacy Center (metadata only).
    func recentMCPAccesses(limit: Int = 20) async -> [MCPAccessEvent] {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.recentMCPAccesses(limit: limit)) ?? []
    }

    func buyPlan(_ plan: ProProduct.Plan) {
        defaults.set(defaults.integer(forKey: "upgrade-started") + 1, forKey: "upgrade-started")
        Task {
            if (try? await purchases.purchase(plan)) == true {
                defaults.set(
                    defaults.integer(forKey: "upgrade-completed") + 1,
                    forKey: "upgrade-completed")
            }
        }
    }

    func restorePurchases() {
        Task { _ = try? await purchases.restorePurchases() }
    }

    // MARK: - Pins & boards

    private(set) var boards: [Pinboard] = []

    func togglePin(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            // Free-tier ceiling; the paywall UX lands with monetization.
            if !item.isPinned {
                let count = (try? await grdbStore.pinnedCount()) ?? 0
                guard PinLimits.canPin(currentPinCount: count, isPro: tier == .pro) else {
                    paywallWindow.show(trigger: .freeLimitReached, model: self)
                    return
                }
            }
            _ = try? await grdbStore.setPinned(id: item.id, !item.isPinned)
            toasts.show(GanchoToast(message: item.isPinned ? "Unpinned" : "Pinned"))
            await refreshRecents()
        }
    }

    /// The signature gesture: clip → permanent snippet (⌘S in the panel).
    func promoteToSnippet(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            let count = (try? await grdbStore.snippetCount()) ?? 0
            guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: tier == .pro)
            else {
                paywallWindow.show(trigger: .freeLimitReached, model: self)
                return
            }
            _ = try? await grdbStore.promoteToSnippet(id: item.id)
            toasts.show(GanchoToast(message: "Promoted to Library"))
            await refreshRecents()
        }
    }

    func refreshBoards() async {
        guard let grdbStore else { return }
        boards = (try? await grdbStore.pinboards()) ?? []
    }

    func assign(_ item: ClipItem, toBoard board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.assign(clipID: item.id, toBoard: board.id)
            toasts.show(GanchoToast(message: "Added to board"))
            await refreshRecents()
        }
    }

    func unassign(_ item: ClipItem, fromBoard board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.unassign(clipID: item.id, fromBoard: board.id)
            await refreshRecents()
        }
    }

    func removeFromAllBoards(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.removeFromAllBoards(clipID: item.id)
            await refreshRecents()
        }
    }

    func createBoard(named name: String) {
        guard let grdbStore else { return }
        Task {
            // The built-in Favorites board never counts against the free limit.
            let count = (try? await grdbStore.pinboards().filter { !$0.isSystem }.count) ?? 0
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro)
            else {
                paywallWindow.show(trigger: .freeLimitReached, model: self)
                return
            }
            if let board = try? await grdbStore.createPinboard(name: name) {
                await sync.enqueue(boards: [board])
            }
            await refreshBoards()
        }
    }

    /// Rename / delete are no-ops on the built-in Favorites board (the store
    /// guards on isSystem), so the UI only needs to hide the affordances.
    func renameBoard(_ board: Pinboard, name: String) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.renameBoard(id: board.id, name: name)
            var renamed = board
            renamed.name = name
            await sync.enqueue(boards: [renamed])
            await refreshBoards()
        }
    }

    func deleteBoard(_ board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.deletePinboard(id: board.id)
            await refreshBoards()
            await refreshRecents()
        }
    }

    /// The boards a clip belongs to — drives the peek's board menu checkmarks.
    func boardMembership(for item: ClipItem) async -> Set<UUID> {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.boardIDs(forClip: item.id)) ?? []
    }

    /// Add or remove a clip from one board (the peek's per-board toggle).
    func setBoardMembership(_ item: ClipItem, board: Pinboard, member: Bool) async {
        guard let grdbStore else { return }
        if member {
            try? await grdbStore.assign(clipID: item.id, toBoard: board.id)
        } else {
            try? await grdbStore.unassign(clipID: item.id, fromBoard: board.id)
        }
        await refreshRecents()
    }

    // MARK: - Denylist & settings portability

    var denylistEntries: [String] {
        let effective = SourceAppDenylist.suggestedBundleIDs
            .subtracting(monitor.denylist.disabledSuggestions)
            .union(monitor.denylist.userBundleIDs)
        return effective.sorted()
    }

    func addToDenylist(_ bundleID: String) {
        monitor.denylist.add(bundleID)
        monitor.denylist.save(to: defaults)
    }

    func removeFromDenylist(_ bundleID: String) {
        monitor.denylist.remove(bundleID)
        monitor.denylist.save(to: defaults)
    }

    /// Preferences only — never clips (reinstall portability).
    func settingsSnapshot() throws -> SettingsSnapshot {
        SettingsSnapshot(
            retention: retentionPolicy,
            capturePreferencesJSON: (try? JSONEncoder().encode(preferences)) ?? Data(),
            appSettings: [
                "panel-position": panel.position.rawValue,
                "show-in-dock": showInDock ? "true" : "false",
                "appearance": appearance.rawValue,
            ])
    }

    func apply(_ snapshot: SettingsSnapshot) {
        retentionPolicy = snapshot.retention
        if let prefs = try? JSONDecoder().decode(
            CapturePreferences.self, from: snapshot.capturePreferencesJSON)
        {
            preferences = prefs
        }
        if let raw = snapshot.appSettings["panel-position"],
            let position = PanelPosition(rawValue: raw)
        {
            panel.position = position
        }
        if let dock = snapshot.appSettings["show-in-dock"] {
            showInDock = dock == "true"
        }
        if let raw = snapshot.appSettings["appearance"],
            let value = AppearancePreference(rawValue: raw)
        {
            appearance = value
        }
    }

    private func scheduleScreenShareWatch() {
        screenShareTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let sharing =
                    self.autoPauseOnScreenShare
                    && self.screenShareDetector.isScreenSharePresumed()
                if self.monitor.pausedForScreenShare != sharing {
                    self.monitor.pausedForScreenShare = sharing
                }
            }
        }
    }

    // MARK: - Retention

    private func scheduleRetention() {
        runRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
    }

    private func runRetention() {
        guard let grdbStore else { return }
        let policy = retentionPolicy
        let tier = tier
        Task {
            _ = try? await RetentionEngine(store: grdbStore).runPurge(policy: policy)
            _ = try? await TierEnforcement(store: grdbStore).enforce(tier: tier)
            await refreshRecents()
        }
    }
}
