import AppIntents
import AppKit
import ApplicationServices
import ClipboardCore
import GanchoAI
import GanchoAppCore
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
    /// Clips hidden from the list while their delete is in the undo window — kept
    /// out of `recentItems` even across a refresh until the deletion commits.
    private var pendingDeletionIDs: Set<UUID> = []
    private var deletionTasks: [UUID: Task<Void, Never>] = [:]
    var monitorStatus: MonitorStatus { monitor.status }

    /// True when the durable store failed to open and the app is running on the
    /// in-memory fallback — history won't survive a relaunch, so the panel warns.
    var storageIsEphemeral: Bool { !store.isDurable }

    /// Durable store under Application Support; falls back to in-memory if
    /// the disk store cannot open (never block launch on a storage error).
    let store: any ClipboardStore
    /// Full first-party store surface, downcast once from `store`; nil on the
    /// in-memory fallback. Feature code (this model and the views) reaches every
    /// capability through it instead of downcasting to the concrete class.
    let grdbStore: (any FullClipStore)?
    /// Narrow concrete handle kept ONLY to construct in-module engines
    /// (`RetentionEngine`, `TierEnforcement`, `GanchoArchive`), to feed
    /// `SyncEngineFactory`, and to reach the MCP access log / sync-internal
    /// tombstone list — none of which belong in a client facet.
    let grdbForEngines: GRDBClipboardStore?
    /// Cached image thumbnails for the history rows and the peek.
    let thumbnails: ClipThumbnailStore

    let monitor: MacPasteboardMonitor
    let pasteBack = PasteBackService()
    let privacyEvents = InMemoryPrivacyEventRecorder()
    /// Content-free log of recent operational issues (storage that wouldn't
    /// open, a sync that failed) for the Privacy Center and support — never any
    /// clip text, never persisted or uploaded.
    let diagnostics = DiagnosticLog()
    let panel = PanelController()
    /// Transient HUD for action feedback (copy-only paste, pin/unpin).
    let toasts = ToastPresenter()
    let welcomeWindow = WelcomeWindowController()
    let privacyCenterWindow = PrivacyCenterWindowController()
    let paywallWindow = PaywallWindowController()
    let permissionWindow = PasteboardPermissionWindowController()
    let libraryWindow = LibraryWindowController()
    let settingsWindow = SettingsWindowController()
    let mcpAccessWindow = MCPAccessWindowController()
    let intelligenceWindow = IntelligenceWindowController()
    let purchases: any PurchaseHandling = AppModel.makePurchaseHandler()
    #if GANCHO_DIRECT_DOWNLOAD
        // Sparkle auto-updater, started at launch (direct-download channel only).
        let updater = SparkleUpdater()
    #endif
    let telemetry: TelemetryPipeline

    /// Encrypted iCloud sync, behind the boundary. Owns the engine lifecycle
    /// (make/start/stop/reset + the enabled flag); this model keeps only the
    /// status state below and its UI mapping. A `NoopSyncEngine` until the user
    /// is Pro on an iCloud-signed-in device; `syncController.configure(tier:)`
    /// swaps in the real adapter and back as the tier or account changes.
    let syncController: SyncController

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

    /// Free AI-title "taste": how many of `FreeTierLimits.freeAITitleTaste` have
    /// been spent, and the consume step. Persisted so the budget survives relaunch.
    private var freeAITitlesUsed: Int { defaults.integer(forKey: "free-ai-titles-used") }
    private var freeAITitlesRemaining: Int {
        FreeTierLimits.freeAITitlesRemaining(used: freeAITitlesUsed)
    }
    private func consumeFreeAITitle() {
        defaults.set(freeAITitlesUsed + 1, forKey: "free-ai-titles-used")
    }

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

    /// On-device intelligence toggles (the Intelligence screen). Each gates a
    /// real enrichment stage in `enrich`/`makeItem`.
    var intelligence: IntelligencePreferences {
        didSet { intelligence.save(to: defaults) }
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
        // Test hook: force the in-memory fallback so the "history isn't being
        // saved" warning path is drivable by a UI test (mirrors a real failure
        // to open the encrypted store).
        let forceEphemeral = ProcessInfo.processInfo.arguments.contains("-force-ephemeral-store")
        let grdb = forceEphemeral ? nil : (try? GRDBClipboardStore.encrypted(directory: directory))
        self.grdbStore = grdb
        self.grdbForEngines = grdb
        self.store = grdb ?? InMemoryClipboardStore()
        self.syncController = SyncController(
            store: grdb,
            stateStoreURL: URL.applicationSupportDirectory
                .appendingPathComponent("Gancho", isDirectory: true)
                .appendingPathComponent("sync-state.plist"))
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
        intelligence = IntelligencePreferences.load(from: defaults)
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

        // Sync status/idle mapping stays here (the views observe `syncStatus`);
        // the controller only drives the engine lifecycle and calls back.
        syncController.onStatus = { [weak self] status in self?.applySyncStatus(status) }
        syncController.onIdle = { [weak self] in self?.syncStatus = .idle }
        // StoreKit drives the tier: the listener catches renewals/refunds,
        // and a launch refresh reconciles against current entitlements.
        // Only StoreKit has out-of-process tier changes (renewals, refunds);
        // the direct-download license handler changes only on activation.
        (purchases as? StoreKitPurchaseHandler)?.onTierChange = { [weak self] tier in
            self?.applyTier(tier)
        }
        Task {
            let entitled = await purchases.currentTier()
            if entitled != tier { applyTier(entitled) }
            #if DEBUG
                if DebugFlags.forcePro, tier != .pro { applyTier(.pro) }
            #endif
            syncController.configure(tier: tier)
        }
        telemetry.record(.appLaunched)
        // A data-loss-level storage failure also lands in the support log (the
        // banner already shouts; this keeps a copyable, timestamped trail).
        if storageIsEphemeral {
            diagnostics.record(
                String(localized: "Storage"),
                String(localized: "Couldn’t open secure storage — running in memory."))
        }
        Task { await refreshRecents() }
        // Post-launch maintenance: the cosmetic legacy-preview backfill moved
        // off the synchronous store open (it scanned image rows on every
        // launch); run it at utility priority once the UI is wired up.
        if let grdb {
            Task(priority: .utility) { try? await grdb.backfillLegacyPreviews() }
        }

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

        // UI-test hook: open the Privacy Center directly, without depending on the
        // status-item menu (which self-skips on headless runners). Pairs with
        // `-force-ephemeral-store` to assert the diagnostics "Recent issues" log.
        if CommandLine.arguments.contains("-open-privacy-center-on-launch") {
            NSApplication.shared.setActivationPolicy(.regular)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                privacyCenterWindow.show(model: self)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            }
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
        // Universal Clipboard delivers a copy made on another device. If that
        // device runs gancho it captures and syncs the original — already
        // enriched (title/OCR) — so re-capturing the remote copy here only
        // duplicates what sync brings, minus the enrichment. And if the origin
        // isn't gancho, the user never chose to save it. Either way, skip it;
        // this also keeps cross-device capture consistent with iOS's consensual
        // model (the origin device decides, the rest receive via sync).
        guard !capture.isFromUniversalClipboard else { return }
        let (item, content) = Self.makeItem(
            from: capture, classifier: classifier, detector: sensitiveDetector,
            sensitiveLifetime: retentionPolicy.sensitiveLifetime,
            detectSecrets: intelligence.detectSecrets)
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
            await syncController.engine.enqueue([item])
            await refreshRecents()
            enrich(item, content: content)
        }
    }

    /// Pro-tier async enrichment — never blocks capture: OCR makes image
    /// clips searchable; the tiered annotator titles text clips.
    private func enrich(_ item: ClipItem, content: ClipContent?) {
        // The Pro + non-sensitive + per-toggle gating is the shared policy both
        // platforms drive their enrichment IO from (see `EnrichmentPlan`); only
        // the store writes and the list refresh differ per platform.
        let plan = EnrichmentPlan(
            content: content, kind: item.kind, isSensitive: item.isSensitive,
            hasTitle: !item.title.isEmpty, isPro: tier == .pro, preferences: intelligence)
        // Free taste: the first `FreeTierLimits.freeAITitleTaste` text clips get a
        // real AI title even on the free tier, so a new user sees the on-device
        // intelligence on their OWN clips before deciding. Titles only — semantic
        // search and OCR stay Pro; sensitive clips are never enriched.
        let tasteTitle =
            tier != .pro && !item.isSensitive && item.title.isEmpty
            && freeAITitlesRemaining > 0
        guard !plan.isEmpty || tasteTitle, let grdbStore else { return }
        Task(priority: .utility) {
            await EnrichmentService().enrich(
                item, content: content, plan: plan,
                writeTitle: plan.runs(.title) || tasteTitle, store: grdbStore
            ) { @MainActor in
                if tasteTitle {
                    consumeFreeAITitle()
                    // The moment the taste runs out is the conversion moment: a
                    // gentle, tappable nudge — never an interrupting gateway.
                    if freeAITitlesRemaining == 0 { showAITasteEndedNudge() }
                }
                await refreshRecents()
            }
        }
    }

    func refreshRecents() async {
        let items = (try? await store.items(offset: 0, limit: 50)) ?? []
        // Keep clips in their undo window hidden even if a capture refreshes the list.
        recentItems =
            pendingDeletionIDs.isEmpty
            ? items : items.filter { !pendingDeletionIDs.contains($0.id) }
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
        sensitiveLifetime: TimeInterval,
        detectSecrets: Bool = true
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
                sensitiveLifetime: sensitiveLifetime, detectSecrets: detectSecrets)
            return (
                item,
                item.isSensitive ? .text(text) : .binary(data: rtf, typeIdentifier: "public.rtf")
            )
        default:
            let text = capture.textRepresentation ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime, detectSecrets: detectSecrets)
            return (item, .text(ContentNormalizer.canonicalText(text, kind: item.kind)))
        }
    }

    private static func decoratedTextItem(
        text: String, capture: PasteboardCapture, classifier: RuleClassifier,
        detector: SensitiveDataDetector, sensitiveLifetime: TimeInterval,
        detectSecrets: Bool = true
    ) -> ClipItem {
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = ClipItem(
            kind: kind,
            preview: String(canonical.prefix(120)),
            contentHash: ClipItem.hash(of: canonical, kind: kind),
            sourceAppBundleID: capture.sourceAppBundleID)
        // Intelligence toggle off ⇒ skip secret detection/masking. The
        // password-manager veto (ConcealedType, pre-read) is separate and stays.
        guard detectSecrets else { return item }
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

    /// One-time conversion nudge the moment the free AI-title taste runs out.
    private func showAITasteEndedNudge() {
        toasts.show(
            GanchoToast(
                message: "Loved the smart AI titles? Pro keeps them on every clip",
                action: ToastAction(title: "See Pro") { [weak self] in
                    guard let self else { return }
                    paywallWindow.show(trigger: .freeLimitReached, model: self)
                }),
            duration: .seconds(6))
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

    // MARK: - Smart paste (deterministic + on-device Apple Intelligence)

    private let smartPasteService = SmartPasteService()

    /// Smart Paste affordances appear when the user kept the feature on.
    /// Deterministic actions such as PII redaction do not need Apple
    /// Intelligence, so the UI must not hide the entire menu behind model
    /// availability.
    var smartPasteAvailable: Bool {
        intelligence.smartPaste
    }

    /// Model-backed rewrites and translations require Apple Intelligence in
    /// addition to the user's Smart Paste opt-in.
    var smartPasteModelAvailable: Bool {
        intelligence.smartPaste && SmartPasteService.isAvailable
    }

    /// Transforms a clip's text on-device; nil if unavailable or the model
    /// declined. Pure enrichment — never fails the caller.
    func smartPaste(_ text: String, action: SmartPasteAction) async -> String? {
        try? await smartPasteService.transform(text, action: action)
    }

    /// On-device translation to an English-named target language; nil on failure.
    func smartTranslate(_ text: String, to language: String) async -> String? {
        try? await smartPasteService.translate(text, to: language)
    }

    // MARK: - Ask your clipboard (grounded on-device QA)

    /// A grounded answer plus the clips it was drawn from (for citing/pasting).
    struct ClipboardAnswer: Identifiable, Sendable {
        let id = UUID()
        let answer: String
        let sources: [ClipItem]
    }

    private let qaService = ClipboardQAService()
    var askAvailable: Bool { ClipboardQAService.isAvailable }

    /// Retrieve the most relevant clips (semantic when the embeddings are ready,
    /// else full-text) and have the on-device model answer grounded ONLY in
    /// them. Sensitive clips are filtered out before anything reaches the model.
    func askClipboard(_ question: String) async -> ClipboardAnswer? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let grdbStore, ClipboardQAService.isAvailable, !trimmed.isEmpty else { return nil }

        var clips: [ClipItem] = []
        if intelligence.semanticSearch, let embedder = ContextualSentenceEmbedder(),
            embedder.hasAvailableAssets,
            let vector = try? embedder.vector(for: String(trimmed.prefix(1_000)))
        {
            clips =
                (try? await grdbStore.semanticSearch(
                    queryVector: vector, topK: 6, snippetsOnly: false)) ?? []
        }
        if clips.isEmpty {
            clips = (try? await grdbStore.search(ClipSearchQuery(text: trimmed), limit: 6)) ?? []
        }
        let safe = clips.filter { !$0.isSensitive }
        guard !safe.isEmpty else {
            return ClipboardAnswer(
                answer: String(localized: "Nothing in your clipboard matches that."), sources: [])
        }

        var sources: [String] = []
        for clip in safe {
            let body: String
            if case .text(let text)? = try? await store.content(for: clip.id) {
                body = text
            } else {
                body = clip.preview
            }
            sources.append(clip.title.isEmpty ? body : "\(clip.title): \(body)")
        }
        let answer = try? await qaService.answer(question: trimmed, sources: sources)
        return ClipboardAnswer(
            answer: answer ?? String(localized: "Couldn’t answer that — try again."),
            sources: safe)
    }

    /// Pastes arbitrary text (a Smart Paste or filled-snippet result) into the
    /// frontmost app via the same paste-back path as a normal paste.
    func pasteText(_ text: String) {
        Task {
            panel.hide()
            try? await Task.sleep(for: .milliseconds(80))
            if pasteBack.paste(.text(text), asPlainText: false) == .copiedOnly {
                showCopyOnlyToast()
            }
        }
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
    /// Deferred + reversible delete. The clip disappears from the list at once,
    /// but the destructive removal (and the sync tombstone that propagates it to
    /// every device) only commits after the undo window — so a mis-tap never
    /// loses history, and pins/boards/timestamps survive an Undo intact. If the
    /// app quits mid-window the commit never runs, so the clip is kept (safe).
    func delete(_ item: ClipItem) {
        pendingDeletionIDs.insert(item.id)
        recentItems.removeAll { $0.id == item.id }
        // The deleted clip may have been the most-recent one — re-publish so the
        // menu-bar helper's "Last copied" preview doesn't point at it until the
        // next refresh.
        publishLastCopied()
        deletionTasks[item.id]?.cancel()
        deletionTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await self?.commitDeletion(item)
        }
        toasts.show(
            GanchoToast(
                message: "Deleted",
                action: ToastAction(title: "Undo") { [weak self] in
                    self?.undoDelete(item)
                }))
    }

    private func undoDelete(_ item: ClipItem) {
        deletionTasks[item.id]?.cancel()
        deletionTasks[item.id] = nil
        pendingDeletionIDs.remove(item.id)
        Task { await refreshRecents() }  // still in the store → reappears in place
    }

    private func commitDeletion(_ item: ClipItem) async {
        // A late Undo may have reclaimed the clip right at the window boundary —
        // only commit if it's still pending.
        guard pendingDeletionIDs.contains(item.id) else { return }
        deletionTasks[item.id] = nil
        if syncController.isEnabled, let grdbStore {
            _ = try? await grdbStore.deleteForSync(id: item.id, now: .now)
            await syncController.engine.enqueueDeletion(ids: [item.id])
        } else {
            _ = try? await store.delete(id: item.id)
        }
        // Clear the hold and reconcile from the store of record only AFTER the
        // delete lands: a refresh mid-commit can't flash the clip back (it stays
        // filtered until now), and a failed delete honestly reappears — the list
        // and "Last copied" are both re-derived from what's actually stored.
        pendingDeletionIDs.remove(item.id)
        await refreshRecents()
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

    /// Generates the shareable "Wrapped" stats card and saves it (on-device).
    /// Exposed so a Settings button can reach it, not just the menu-bar command.
    func exportWrapped() {
        Task {
            let stats = await WrappedStats.gather(model: self)
            WrappedExporter.savePNG(stats: stats)
        }
    }

    // MARK: - Purchases

    /// Applies a tier from StoreKit and releases any archived clips when the
    /// user becomes Pro (free-tier archiving is reversible — no data hostage).
    private func applyTier(_ newTier: UserTier) {
        tier = newTier
        syncController.configure(tier: tier)
        guard let grdbForEngines else { return }
        Task {
            _ = try? await TierEnforcement(store: grdbForEngines).enforce(tier: newTier)
            await refreshRecents()
        }
    }

    // MARK: - Sync

    /// Pull the latest from iCloud (and push anything pending). Called when the
    /// panel opens, so a clip captured on another device shows up without an app
    /// restart — the engine only fetches on `start()`, and a menu-bar agent gets
    /// no push to fetch on. The refresh-on-settle in `applySyncStatus` updates
    /// the panel once the fetch lands. A no-op when sync is off.
    func syncNow() {
        syncController.syncNow()
    }

    /// Drop the persisted CKSyncEngine state and re-arm sync, so it re-fetches
    /// every zone from scratch. Fixes a device whose change token drifted ahead
    /// of what it actually stored — older records never re-arrive on an
    /// incremental fetch. Local rows are kept; remote records re-upsert.
    func resetSyncAndRepull() {
        syncController.reset(tier: tier)
    }

    /// Applies a status from the engine: updates the indicator and logs a
    /// metadata-only milestone (synced/paused/failed) to the Privacy Center.
    private func applySyncStatus(_ status: SyncStatus) {
        let wasSyncing = syncStatus == .syncing
        let wasFailed: Bool = { if case .failed = syncStatus { true } else { false } }()
        syncStatus = status
        if let event = Self.syncEvent(for: status) {
            privacyEvents.record(sync: event)
        }
        // Edge-triggered: log a failure to the support trail once per failure,
        // not on every re-emit while it stays failed. The detailed, localized
        // cause already shows in the iCloud-sync section, so keep this line
        // fixed and user-friendly rather than leaking the raw enum case name.
        if case .failed = status, !wasFailed {
            diagnostics.record(
                String(localized: "Sync"), String(localized: "iCloud sync failed."))
        }
        // A finished fetch may have pulled new clips/boards from iCloud — refresh
        // so the panel and Library reflect them without a manual reopen.
        if wasSyncing, status != .syncing {
            Task {
                await refreshRecents()
                await refreshBoards()
            }
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
        Task { await syncController.forceSync() }
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
        guard let grdbForEngines else { return [] }
        return (try? await grdbForEngines.recentMCPAccesses(limit: limit)) ?? []
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

    /// Activates a direct-download Lemon Squeezy license key. Reports the
    /// distinguishable outcome (activated / wrong key / no network / not
    /// licensable) so the paywall can guide the user instead of dead-ending
    /// every failure on one message. The tier is reconciled from the verified
    /// token either way.
    func activateLicense(_ licenseKey: String) async -> LicenseActivationResult {
        let result = await purchases.activateResult(licenseKey: licenseKey)
        applyTier(await purchases.currentTier())
        return result
    }

    @MainActor
    private static func makePurchaseHandler() -> any PurchaseHandling {
        #if GANCHO_DIRECT_DOWNLOAD
            return LicenseKeyPurchaseHandler(
                store: KeychainLicenseTokenStore(),
                activation: LicenseActivationService(
                    validator: LemonSqueezyValidator(
                        transport: { try await URLSession.shared.data(for: $0) }),
                    signingKey: LicenseSigningKey.embedded),
                instanceName: Host.current().localizedName ?? "Mac")
        #else
            return StoreKitPurchaseHandler()
        #endif
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
            // setPinned flagged the row for upload; enqueue pushes it now
            // instead of at the next sync start(). The engine builds the
            // record from the stored row, so only the id matters here.
            await syncController.engine.enqueue([item])
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
            _ = try? await grdbStore.promoteToSnippet(id: item.id, title: nil)
            toasts.show(GanchoToast(message: "Saved as snippet"))
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

    /// Assign + a one-tap Undo (the board-suggestion accept path). The action is
    /// reversible, so offer the reversal in the toast instead of making the user
    /// hunt through the board menu to take it back.
    func assignWithUndo(_ item: ClipItem, toBoard board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.assign(clipID: item.id, toBoard: board.id)
            await refreshRecents()
            toasts.show(
                GanchoToast(
                    message: "Added to board",
                    action: ToastAction(title: "Undo") { [weak self] in
                        self?.unassign(item, fromBoard: board)
                    }))
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

    /// Suggest the board this clip probably belongs to, by a semantic k-NN vote
    /// over how similar clips were filed (`BoardSuggester`). Only ever suggests;
    /// nil when the toggle is off, the clip is sensitive, there are no eligible
    /// user boards, or the neighborhood shows no clear home. 100% on-device.
    func suggestedBoard(for item: ClipItem) async -> Pinboard? {
        guard intelligence.autoBoard, !item.isSensitive, let grdbStore else { return nil }
        return await BoardSuggestionService().suggest(for: item, store: grdbStore)
    }

    /// Creates a board and, when `assigning` is set, files that clip into it —
    /// the per-clip "Add to board → New board…" path expects the clip to land in
    /// the board it just named.
    func createBoard(named name: String, assigning item: ClipItem? = nil) {
        guard let grdbStore else { return }
        Task {
            // The built-in Favorites board never counts against the free limit.
            let count = (try? await grdbStore.pinboards().filter { !$0.isSystem }.count) ?? 0
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro)
            else {
                paywallWindow.show(trigger: .freeLimitReached, model: self)
                return
            }
            if let board = try? await grdbStore.createPinboard(name: name, sfSymbol: "square.stack")
            {
                await syncController.engine.enqueue(boards: [board])
                if let item {
                    try? await grdbStore.assign(clipID: item.id, toBoard: board.id)
                    toasts.show(GanchoToast(message: "Added to board"))
                }
            }
            await refreshBoards()
            if item != nil { await refreshRecents() }
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
            await syncController.engine.enqueue(boards: [renamed])
            await refreshBoards()
        }
    }

    func deleteBoard(_ board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            // When sync is on, tombstone the deletion so it reaches the other
            // devices; otherwise a plain local delete is enough.
            if syncController.isEnabled {
                try? await grdbStore.deletePinboardForSync(id: board.id, now: .now)
                await syncController.engine.enqueueBoardDeletion(ids: [board.id])
            } else {
                try? await grdbStore.deletePinboard(id: board.id)
            }
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
        // Trim pasted whitespace/newlines so a manual entry actually matches the
        // frontmost app's bundle id (an untrimmed entry silently never matches).
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        monitor.denylist.add(trimmed)
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
        guard let grdbForEngines else { return }
        let policy = retentionPolicy
        let tier = tier
        Task {
            _ = try? await RetentionEngine(store: grdbForEngines).runPurge(policy: policy)
            // The purge tombstoned any synced victims; enqueue those deletions
            // now so they propagate immediately rather than at the next sync
            // start(). Re-adding an already-pending deletion is a no-op in the
            // engine, so sweeping the whole tombstone table is safe.
            if syncController.isEnabled {
                let recordIDs = (try? await grdbForEngines.pendingDeletionRecordIDs()) ?? []
                let ids = recordIDs.compactMap { UUID(uuidString: $0) }
                if !ids.isEmpty { await syncController.engine.enqueueDeletion(ids: ids) }
            }
            _ = try? await TierEnforcement(store: grdbForEngines).enforce(tier: tier)
            await refreshRecents()
        }
    }
}
