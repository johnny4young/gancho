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

// AppModel is the macOS composition root; extracting startup wiring is a
// behavior-sensitive refactor, so keep this file-length exception local.
// swiftlint:disable file_length

#if DEBUG
    /// Test-only policy for deterministic UI tests on machines where macOS pasteboard
    /// privacy is set to Ask or Deny. Opted in by launch argument only.
    private struct UITestAllowedPasteboardAccessPolicy: PasteboardAccessPolicy {
        func currentVerdict() -> PasteboardAccessVerdict { .allowed }
    }
#endif

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

// The composition root owns monitor, persistence, sync, and release/license
// wiring. Split responsibilities in dedicated PRs rather than hiding this with
// a baseline.
// swiftlint:disable type_body_length
/// Central app state: wires monitor → classifier → GRDB store, owns the
/// paste-back service, preferences, retention, and the panel lifecycle.
@Observable
@MainActor
final class AppModel {
    // swiftlint:enable type_body_length
    /// Shared reuse-session owner; views continue to consume this model's
    /// facade properties and commands rather than reaching through directly.
    let reuseController: ReuseController
    var recentItems: [ClipItem] { reuseController.recentItems }
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
    private let captureLifecycle: CaptureLifecycleController
    var monitorStatus: MonitorStatus { captureLifecycle.status }
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

    /// Optional anonymous diagnostics are off until the user explicitly
    /// consents. Withdrawing consent tears down the transport immediately.
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

    private let curationController = ClipCurationController()
    private let editingController = ClipEditingController()
    private let ingestionCoordinator = ClipIngestionCoordinator()
    private let defaults: UserDefaults
    private var retentionTimer: Timer?
    /// Light periodic sync pull for the menu-bar agent (see `scheduleSyncPoll`).
    private var syncPollTimer: Timer?
    private var uiTestPanelObserver: NSObjectProtocol?
    /// Wake-from-sleep sync catch-up (see the `didWakeNotification` observer).
    private var wakeObserver: NSObjectProtocol?

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
        get { captureLifecycle.autoPauseOnScreenShare }
        set { captureLifecycle.autoPauseOnScreenShare = newValue }
    }

    /// Remember successful searches for ⌘↑ recall (on by default). Queries can
    /// be as sensitive as clip content, so turning this OFF also erases the
    /// stored history immediately — a privacy toggle, not just a feature flag.
    var rememberSearches: Bool {
        get { reuseController.rememberSearches }
        set { reuseController.rememberSearches = newValue }
    }

    /// The panel's live query, mirrored by `PanelView.onChange` — so `paste`
    /// knows a search led to this paste and can remember the query. Cleared
    /// after recording: one remembered use per typed search.
    var activePanelQuery: String {
        get { reuseController.activeSearchQuery }
        set { reuseController.activeSearchQuery = newValue }
    }

    var preferences: CapturePreferences {
        get { captureLifecycle.preferences }
        set { captureLifecycle.preferences = newValue }
    }

    /// On-device intelligence toggles (the Intelligence screen). Each gates a
    /// real enrichment stage in `enrich`/`ClipItemFactory.make`.
    var intelligence: IntelligencePreferences {
        didSet { intelligence.save(to: defaults) }
    }

    /// Curated-Library Spotlight donation (snippets + pins only — never raw
    /// history). Turning it off wipes Gancho's Spotlight domain immediately.
    var spotlightIndexing: Bool {
        didSet {
            defaults.set(spotlightIndexing, forKey: "spotlightIndexing")
            refreshSpotlight()
        }
    }

    var retentionPolicy: RetentionPolicy {
        didSet { retentionPolicy.save(to: defaults) }
    }

    /// App appearance: Auto follows the system, Light/Dark force it.
    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

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

    // Startup wires storage, capture policy, sync, licensing, and UI test hooks
    // in the same order as production launch; keep the exception local until a
    // dedicated composition-root split lands.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    init() {
        let appDefaults = Self.defaultsForLaunch()
        // One-way migration from versions that allowed a Dock override. Gancho
        // is now permanently menu-bar-only, so an existing `true` must not
        // survive as latent configuration or reappear in an exported snapshot.
        appDefaults.removeObject(forKey: "show-in-dock")
        defaults = appDefaults
        let directory = SharedStorageLocation.macAppStoreDirectory
        // Test hook: force the in-memory fallback so the "history isn't being
        // saved" warning path is drivable by a UI test (mirrors a real failure
        // to open the encrypted store).
        let forceEphemeral = ProcessInfo.processInfo.arguments.contains("-force-ephemeral-store")
        // Test hook: a THROWAWAY durable store in a unique temp directory — a real
        // `GRDBClipboardStore` (so `grdbStore` is non-nil and board creation / the
        // free-tier paywall are reachable, unlike the ephemeral store) that never
        // touches the user's data. Takes precedence over `-force-ephemeral-store`.
        let grdb: GRDBClipboardStore?
        if let tempDir = Self.temporaryDurableStoreDirectory() {
            grdb = try? GRDBClipboardStore.encrypted(directory: tempDir)
        } else if forceEphemeral {
            grdb = nil
        } else {
            grdb = try? GRDBClipboardStore.encrypted(directory: directory)
        }
        self.grdbStore = grdb
        self.grdbForEngines = grdb
        self.store = grdb ?? InMemoryClipboardStore()
        let loadedRememberSearches =
            appDefaults.object(forKey: "remember-searches") as? Bool ?? true
        self.reuseController = ReuseController(
            store: self.store,
            usageStore: grdb,
            rememberSearches: loadedRememberSearches,
            onRememberSearchesChanged: {
                appDefaults.set($0, forKey: "remember-searches")
            })
        self.syncController = SyncController(
            store: grdb,
            stateStoreURL: URL.applicationSupportDirectory
                .appendingPathComponent("Gancho", isDirectory: true)
                .appendingPathComponent("sync-state.plist"),
            hasCloudKitEntitlement: { CloudKitEntitlements.currentTaskAllowsSync() },
            makeEngine: Self.syncEngineFactory)
        let resolvedStore = self.store
        self.thumbnails = ClipThumbnailStore(imageData: { id in
            if case .binary(let data, _)? = try? await resolvedStore.content(for: id) {
                return data
            }
            return nil
        })
        self.mcpConfig = MCPServerConfig.load(fromStoreDirectory: directory)

        var loadedPreferences = CapturePreferences.load(from: appDefaults)
        #if DEBUG
            // UI tests must not inherit a developer's persisted Private Mode state.
            // Keep the override in-memory so the real preference is untouched.
            if CommandLine.arguments.contains("-force-capture-active") {
                loadedPreferences.isPrivateModePaused = false
            }
        #endif
        intelligence = IntelligencePreferences.load(from: appDefaults)
        spotlightIndexing = appDefaults.object(forKey: "spotlightIndexing") as? Bool ?? true
        retentionPolicy = RetentionPolicy.load(from: appDefaults)
        appearance =
            AppearancePreference(rawValue: appDefaults.string(forKey: "appearance") ?? "")
            ?? .auto
        #if DEBUG
            let disableScreenShareAutoPause = CommandLine.arguments.contains(
                "-disable-screen-share-auto-pause")
        #else
            let disableScreenShareAutoPause = false
        #endif
        let loadedAutoPauseOnScreenShare =
            disableScreenShareAutoPause
            ? false : appDefaults.object(forKey: "auto-pause-screen-share") as? Bool ?? true
        // Test hook: pin the FREE tier so the paywall flow is deterministic even
        // when `gancho-force-pro` is set in the environment (which would otherwise
        // force Pro and make `PaywallGatekeeper` suppress every trigger).
        let forceFreeTier = CommandLine.arguments.contains("-force-free-tier")
        tier = forceFreeTier ? .free : UserTier.load(from: appDefaults)

        // Telemetry is a real opt-in. Loading `.notAsked` or `.disabled` keeps
        // the SDK uninitialized; the factory runs only after explicit consent.
        var telemetryConsent = TelemetryConsent.load(from: appDefaults)
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

        let pasteboardAccessPolicy: any PasteboardAccessPolicy
        #if DEBUG
            if CommandLine.arguments.contains("-force-pasteboard-access-allowed") {
                pasteboardAccessPolicy = UITestAllowedPasteboardAccessPolicy()
            } else {
                pasteboardAccessPolicy = SystemPasteboardAccessPolicy()
            }
        #else
            pasteboardAccessPolicy = SystemPasteboardAccessPolicy()
        #endif
        let resolvedMonitor = MacPasteboardMonitor(
            accessPolicy: pasteboardAccessPolicy,
            preferences: loadedPreferences)
        monitor = resolvedMonitor
        let screenShareDetector = ScreenShareDetector()
        captureLifecycle = CaptureLifecycleController(
            monitor: resolvedMonitor,
            preferences: loadedPreferences,
            autoPauseOnScreenShare: loadedAutoPauseOnScreenShare,
            screenShareIsActive: { screenShareDetector.isScreenSharePresumed() },
            onPreferencesChanged: { $0.save(to: appDefaults) },
            onAutoPauseChanged: {
                appDefaults.set($0, forKey: "auto-pause-screen-share")
            })
        monitor.denylist = SourceAppDenylist.load(from: appDefaults)
        monitor.onCapture = { [weak self] capture in
            self?.ingest(capture)
        }
        monitor.onIgnore = { [weak self] reason in
            self?.privacyEvents.record(IgnoredCaptureEvent(reason: reason))
        }
        reuseController.setRecentItemsObserver { [weak self] _ in
            self?.publishLastCopied()
        }
        captureLifecycle.activate()
        #if DEBUG
            if CommandLine.arguments.contains("-start-capture-paused") {
                captureLifecycle.stopCapture()
            }
        #endif
        scheduleRetention()
        scheduleSyncPoll()
        panel.attach(model: self)
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
        // Content-free sync-trouble trail → the Privacy Center's "Recent issues"
        // (fetched records that fail to decode/apply, non-transient save errors).
        syncController.diagnostics = diagnostics
        // The engine is push-driven while awake, but a sleeping Mac misses the
        // pushes for clips copied on other devices in the meantime — catch up
        // the moment the machine wakes. (Panel-open does the same for latency.)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncController.syncNow() }
        }
        // StoreKit drives the tier: the listener catches renewals/refunds,
        // and a launch refresh reconciles against current entitlements.
        // Only StoreKit has out-of-process tier changes (renewals, refunds);
        // the direct-download license handler changes only on activation.
        (purchases as? StoreKitPurchaseHandler)?.onTierChange = { [weak self] tier in
            guard !forceFreeTier else { return }
            self?.applyTier(tier)
        }
        Task {
            if forceFreeTier {
                applyTier(.free)  // deterministic free tier: skip StoreKit + forcePro
            } else {
                let entitled = await purchases.currentTier()
                if entitled != tier { applyTier(entitled) }
                #if DEBUG
                    if DebugFlags.forcePro, tier != .pro { applyTier(.pro) }
                #endif
            }
            syncController.configure(tier: tier)
        }
        telemetry.record(.appLaunched)
        #if DEBUG
            if CommandLine.arguments.contains("-show-telemetry-consent") {
                requestTelemetryConsentAfterFirstValue()
            }
        #endif
        // A data-loss-level storage failure also lands in the support log (the
        // banner already shouts; this keeps a copyable, timestamped trail).
        if storageIsEphemeral {
            diagnostics.record(
                String(localized: "Storage"),
                String(localized: "Couldn’t open secure storage — running in memory."))
        }
        Task { await refreshRecents() }
        seedSampleClipsIfRequested()
        seedDenylistEntryIfRequested()
        let uiTestBoardSeedTask = seedSampleBoardsIfRequested()
        let uiTestPanelReproTask = seedPanelReproIfRequested()
        let uiTestSourceAppSeedTask = seedSourceAppsIfRequested()
        let uiTestReuseSuggestionSeedTask = seedReuseSuggestionIfRequested()
        let uiTestClipEditingSeedTask = seedClipEditingIfRequested()
        let uiTestMultiFileDragSeedTask = seedMultiFileDragIfRequested()
        // Post-launch maintenance: the cosmetic legacy-preview backfill moved
        // off the synchronous store open (it scanned image rows on every
        // launch); run it at utility priority once the UI is wired up. The
        // Spotlight reconcile follows: it repairs any curation change the app
        // missed (crash, direct DB edit) and applies the toggle state.
        if let grdb {
            let spotlightEnabled = spotlightIndexing
            Task(priority: .utility) {
                try? await grdb.backfillLegacyPreviews()
                await LibrarySpotlightService(index: CoreSpotlightIndexer())
                    .reconcile(store: grdb, enabled: spotlightEnabled)
            }
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
                    await uiTestBoardSeedTask?.value
                    await uiTestPanelReproTask?.value
                    await uiTestSourceAppSeedTask?.value
                    await uiTestReuseSuggestionSeedTask?.value
                    await uiTestClipEditingSeedTask?.value
                    await uiTestMultiFileDragSeedTask?.value
                    panel.show(model: self)
                    _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                    try? await Task.sleep(for: .milliseconds(250))
                    panel.show(model: self)
                    _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                }
            }
            Task { @MainActor in
                await uiTestBoardSeedTask?.value
                await uiTestPanelReproTask?.value
                await uiTestSourceAppSeedTask?.value
                await uiTestReuseSuggestionSeedTask?.value
                await uiTestClipEditingSeedTask?.value
                await uiTestMultiFileDragSeedTask?.value
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
        Task {
            let configuration = ClipIngestionCoordinator.Configuration(
                sensitiveLifetime: retentionPolicy.sensitiveLifetime,
                detectSecrets: intelligence.detectSecrets,
                tier: tier,
                intelligence: intelligence,
                allowsFreeTitle: freeAITitlesRemaining > 0)
            guard
                let outcome = try? await ingestionCoordinator.ingest(
                    capture,
                    configuration: configuration,
                    store: store,
                    syncEngine: syncController.engine)
            else { return }
            // Bucketized analytics: kind + a length BUCKET, never the content.
            telemetry.record(
                .itemCaptured(
                    type: outcome.item.kind,
                    lengthBucket: .init(characterCount: outcome.contentLength)))
            await refreshRecents()
            enrich(outcome)
        }
    }

    /// UI-test hook: seed a few KNOWN synthetic clips through the normal capture
    /// pipeline so the panel/history is deterministic for the automated flows.
    /// Strictly gated on BOTH the launch arg and the ephemeral store, so a real
    /// user's durable history is never touched and a normal launch (no arg) is a
    /// byte-for-byte no-op. The seed content is synthetic and non-secret.
    private func seedSampleClipsIfRequested() {
        guard CommandLine.arguments.contains("-seed-sample-clips"), storageIsEphemeral
        else { return }
        for capture in [
            PasteboardCapture(text: "seed alpha"),
            PasteboardCapture(text: "https://seed.example/one"),
            PasteboardCapture(text: "seed beta")
        ] {
            ingest(capture)
        }
    }

    /// UI-test hook: `-seed-denylist-entry <bundle-id>` pre-adds one user
    /// denylist entry so `DenylistUITests` can verify the Settings row and
    /// the remove path with element clicks alone — synthesized typing isn't
    /// grantable on every runner. It requires an isolated test defaults suite,
    /// so a crash can never leave test data in a user's real preferences.
    private func seedDenylistEntryIfRequested() {
        #if DEBUG
            guard let index = CommandLine.arguments.firstIndex(of: "-seed-denylist-entry"),
                Self.uiTestDefaultsSuiteName() != nil,
                CommandLine.arguments.indices.contains(index + 1)
            else { return }
            addToDenylist(CommandLine.arguments[index + 1])
        #endif
    }

    /// Selects a disposable UserDefaults domain for UI tests. The prefix
    /// prevents a launch argument from ever clearing a normal preferences
    /// domain; each test supplies a unique UUID-backed suite name.
    private static func defaultsForLaunch() -> UserDefaults {
        #if DEBUG
            guard let suiteName = uiTestDefaultsSuiteName(),
                let defaults = UserDefaults(suiteName: suiteName)
            else { return .standard }
            defaults.removePersistentDomain(forName: suiteName)
            return defaults
        #else
            return .standard
        #endif
    }

    #if DEBUG
        private static func uiTestDefaultsSuiteName() -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: "-ui-test-defaults-suite"),
                CommandLine.arguments.indices.contains(index + 1)
            else { return nil }
            let suiteName = CommandLine.arguments[index + 1]
            guard suiteName.hasPrefix("com.johnny4young.gancho.uitests.") else { return nil }
            return suiteName
        }
    #endif

    /// The throwaway store directory for `-use-temp-durable-store`, or nil when
    /// the arg is absent. Lives under the OS temp directory (system-cleaned), so
    /// the UI-test paywall flow gets a REAL durable store — board creation works
    /// and the free-tier gate is reachable — without touching the user's data.
    private static func temporaryDurableStoreDirectory() -> URL? {
        guard ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store")
        else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-uitest-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UI-test hook: seed exactly `PinLimits.freeMaxPinboards` known boards into a
    /// THROWAWAY durable store so an automated flow can create ONE more and hit
    /// the free-tier paywall deterministically. Gated on BOTH `-seed-sample-boards`
    /// and `-use-temp-durable-store` (never a real store), so a normal launch is a
    /// no-op and the user's boards are never touched. Seeds sequentially so the
    /// board count is exact when the test creates the next one.
    private func seedSampleBoardsIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-sample-boards"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            for i in 1...PinLimits.freeMaxPinboards {
                _ = try? await grdbStore.createPinboard(
                    name: "Seed board \(i)", sfSymbol: "square.stack")
            }
            await refreshBoards()
        }
    }

    /// UI-test hook: seed source-app metadata into a throwaway durable store so
    /// the filter can be exercised without reading or mutating real history.
    /// Both launch arguments are required; all payloads are synthetic.
    private func seedSourceAppsIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-source-apps"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            let entries: [(text: String, app: String, kind: ClipContentKind)] = [
                ("Safari source alpha", "com.apple.Safari", .text),
                ("Safari source link", "com.apple.Safari", .url),
                ("Xcode source sample", "com.apple.dt.Xcode", .code)
            ]
            let identifiers = [
                "00000000-0000-4000-8000-000000000101",
                "00000000-0000-4000-8000-000000000102",
                "00000000-0000-4000-8000-000000000103"
            ]
            for (index, entry) in entries.enumerated() {
                guard let id = UUID(uuidString: identifiers[index]) else { return }
                let item = ClipItem(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                    kind: entry.kind, preview: entry.text,
                    contentHash: "ui-source-\(index)", sourceAppBundleID: entry.app)
                _ = try? await grdbStore.insert(item, content: .text(entry.text))
            }
            await refreshRecents()
        }
    }

    /// UI-test hook: seed one synthetic clip at two uses so a double-click
    /// drives the real paste-back → atomic third-use → suggestion path. It is
    /// available only with the throwaway durable store.
    private func seedReuseSuggestionIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-reuse-suggestion"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000104")
        else { return nil }
        return Task {
            let item = ClipItem(
                id: id, preview: "Reusable standup update",
                contentHash: "mac-ui-reuse-suggestion", uses: 2)
            _ = try? await grdbStore.insert(item, content: .text("Reusable standup update"))
            await refreshRecents()
        }
    }

    /// UI-test hook: one deterministic text clip for title/content editing and
    /// large-preview evidence. The throwaway durable-store guard prevents a
    /// normal launch from ever seeding user history.
    private func seedClipEditingIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-clip-editing"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000105")
        else { return nil }
        return Task {
            let item = ClipItem(
                id: id, preview: "Yesterday: fixed search",
                contentHash: "mac-ui-clip-editing")
            _ = try? await grdbStore.insert(
                item,
                content: .text(
                    "Yesterday: fixed search\nToday: improve editing\nBlockers: none"))
            await refreshRecents()
        }
    }

    /// UI-test hook: seed a THROWAWAY durable store with a few PINNED clips plus
    /// several same-day clips, so a UI test can assert the grouped panel render
    /// keeps exactly one row selected and hands each row a DISTINCT ⌘N shortcut —
    /// the pinned-first + date-bucket global-index math `PanelSearchModel` owns.
    /// Gated on BOTH `-seed-panel-repro` and `-use-temp-durable-store` (never a
    /// real store), so a normal launch is a no-op.
    private func seedPanelReproIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-panel-repro"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        // Fire-and-forget: AFTER the panel is on screen, capture several same-day
        // clips one at a time through the REAL ingest path, so each triggers a
        // live refresh while the grouped list is visible — the reported scenario
        // (a static seed rendered before open does NOT reproduce it).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            for text in ["repro today A", "repro today B", "repro today C", "repro today D"] {
                ingest(PasteboardCapture(text: text))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        // Awaited before the panel opens: the pinned section it sits above.
        return Task {
            var ids: [UUID] = []
            for text in ["repro pinned 1", "repro pinned 2", "repro pinned 3"] {
                let item = ClipItem(kind: .text, preview: text, contentHash: text)
                if let stored = try? await grdbStore.insert(item, content: .text(text)) {
                    ids.append(stored.id)
                }
            }
            for id in ids { _ = try? await grdbStore.setPinned(id: id, true) }
            await refreshRecents()
        }
    }

    /// UI-test hook: creates two harmless temporary files and one pinned clip
    /// that references both. The paired in-panel drop target can then verify
    /// that AppKit exposes two independent dragging items end to end.
    private func seedMultiFileDragIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-multi-file-drag"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "gancho-multi-file-drag-ui-test", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let urls = ["alpha.txt", "beta.txt"].map { directory.appending(path: $0) }
            for (index, url) in urls.enumerated() {
                try? Data("Gancho drag file \(index + 1)".utf8).write(to: url)
            }
            let item = ClipItem(
                kind: .fileReference,
                title: "Two test files",
                preview: "alpha.txt + beta.txt",
                contentHash: "mac-ui-multi-file-drag")
            if let stored = try? await grdbStore.insert(
                item, content: .fileReferences(urls.map(\.path)))
            {
                _ = try? await grdbStore.setPinned(id: stored.id, true)
            }
            await refreshRecents()
        }
    }

    /// Pro-tier async enrichment — never blocks capture: OCR makes image
    /// clips searchable; the tiered annotator titles text clips.
    private func enrich(_ outcome: ClipIngestionCoordinator.Outcome) {
        guard !outcome.enrichment.isEmpty, let grdbStore else { return }
        let syncEngine: (any SyncEngine)? =
            syncController.isEnabled ? syncController.engine : nil
        Task(priority: .utility) {
            await ingestionCoordinator.enrich(
                outcome,
                store: grdbStore,
                syncEngine: syncEngine
            ) { @MainActor [self] in
                if outcome.enrichment.usesFreeTitle {
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
        await reuseController.refreshRecents()
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

    // MARK: - Actions

    /// Paste a stored clip into the frontmost app (panel Enter / menu click).
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            guard let content = try? await store.content(for: item.id) else { return }
            panel.hide()
            // Give focus one beat to return to the previous app.
            try? await Task.sleep(for: .milliseconds(80))
            let pasteOutcome = pasteBack.paste(content, asPlainText: asPlainText)
            switch pasteOutcome {
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
            requestTelemetryConsentAfterFirstValue()
            if let suggestion = await reuseController.recordPaste(of: item),
                shouldPresentReuseSuggestion(after: pasteOutcome)
            {
                await presentReuseSuggestion(suggestion)
            }
        }
    }

    func setTelemetryConsent(_ consent: TelemetryConsent) {
        guard consent != .notAsked else { return }
        telemetryConsent = consent
    }

    func requestTelemetryConsentAfterFirstValue() {
        guard telemetryConsent == .notAsked else { return }
        isTelemetryConsentPromptPresented = true
    }

    /// The ⌘↑ recall list for the panel's search field, newest first.
    func recentSearches() async -> [String] {
        await reuseController.recentSearches()
    }

    /// A drop target accepted a dragged-out clip — the drag equivalent of a
    /// paste for ranking: bump frecency and remember the search that found the
    /// clip. Called once per drag session, however many representations the
    /// target loads. No move-to-top: the drag came FROM the visible list, and
    /// reordering it mid-interaction would yank rows out from under the user.
    func noteDragOutDelivered(_ item: ClipItem) async {
        await noteDragOutDelivered([item])
    }

    /// Records every clip represented by one successful multi-file drop while
    /// presenting at most one reuse suggestion for the session.
    func noteDragOutDelivered(_ items: [ClipItem]) async {
        var firstSuggestion: ClipItem?
        for item in items {
            if let suggestion = await reuseController.recordDragDelivery(of: item),
                firstSuggestion == nil
            {
                firstSuggestion = suggestion
            }
        }
        if let firstSuggestion { await presentReuseSuggestion(firstSuggestion) }
        requestTelemetryConsentAfterFirstValue()
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
            let pasteOutcome = pasteBack.paste(
                .text(transform.apply(to: text)), asPlainText: true)
            if pasteOutcome == .copiedOnly {
                showCopyOnlyToast()
            }
            requestTelemetryConsentAfterFirstValue()
            if let suggestion = await reuseController.recordPaste(of: item),
                shouldPresentReuseSuggestion(after: pasteOutcome)
            {
                await presentReuseSuggestion(suggestion)
            }
        }
    }

    /// Operational paste feedback outranks optional curation. The isolated UI
    /// fixture still exercises the nudge when its host cannot grant Accessibility.
    private func shouldPresentReuseSuggestion(after outcome: PasteBackOutcome) -> Bool {
        outcome == .pasted
            || (CommandLine.arguments.contains("-seed-reuse-suggestion")
                && CommandLine.arguments.contains("-use-temp-durable-store"))
    }

    /// Turns the exact third-use signal into one non-blocking curation action.
    /// A confident board has priority over snippet promotion so the user never
    /// receives two competing suggestions for the same demonstrated reuse.
    private func presentReuseSuggestion(_ item: ClipItem) async {
        if let board = await suggestedBoard(for: item) {
            toasts.show(
                GanchoToast(
                    message: "Add to \(board.name)?",
                    style: .suggestion,
                    action: ToastAction(
                        title: "Add", accessibilityIdentifier: "reuse-suggestion-action"
                    ) { [weak self] in
                        self?.assignWithUndo(item, toBoard: board)
                    }),
                duration: .seconds(8))
            return
        }
        toasts.show(
            GanchoToast(
                message: "Used 3 times — save as a snippet?",
                style: .suggestion,
                action: ToastAction(
                    title: "Save as snippet",
                    accessibilityIdentifier: "reuse-suggestion-action"
                ) { [weak self] in
                    self?.promoteToSnippet(item)
                }),
            duration: .seconds(8))
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
        guard grdbStore != nil else { return }
        Task {
            guard case .text(let body)? = try? await store.content(for: snippet.id) else { return }
            let filled = SnippetTemplate.fill(body, values: values)
            panel.hide()
            try? await Task.sleep(for: .milliseconds(80))
            if pasteBack.paste(.text(filled), asPlainText: false) == .copiedOnly {
                showCopyOnlyToast()
            }
            requestTelemetryConsentAfterFirstValue()
            await reuseController.recordSnippetPaste(of: snippet)
        }
    }

    /// The snippet invoked by an exact keyword, if any (the panel's expansion).
    func snippet(matchingKeyword keyword: String) async -> ClipItem? {
        (try? await grdbStore?.snippet(matchingKeyword: keyword))
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

    var askAvailable: Bool { ClipboardQAService.isAvailable }

    /// Retrieve the most relevant clips (semantic when the embeddings are ready,
    /// else full-text) and have the on-device model answer grounded ONLY in them.
    /// Routes through the shared `ClipboardQA` coordinator — the SAME retrieval +
    /// sensitivity-filtering path iOS uses. macOS previously hand-rolled its own,
    /// which drifted from iOS; unifying them means a fix reaches both platforms.
    func askClipboard(_ question: String) async -> ClipboardAnswer? {
        guard let grdbStore else { return nil }
        switch await ClipboardQA().answer(
            question: question, store: grdbStore, useSemantic: intelligence.semanticSearch)
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

    func cyclicPaste() {
        guard let item = reuseController.nextCyclicItem() else { return }
        paste(item)
    }

    // MARK: - Paste stack (local; cross-device rides sync)

    /// Queue entries (each with a stable id independent of the clip), so the UI
    /// can render and address duplicates without ClipItem.id collisions.
    var pasteStackEntries: [PasteStack.Entry] { reuseController.pasteStackEntries }

    func pushToStack(_ item: ClipItem) {
        pushToStack([item])
    }

    func pushToStack(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        reuseController.pushToStack(items)
        toasts.show(GanchoToast(message: "Added to paste stack"))
    }

    func clearStack() {
        reuseController.clearStack()
    }

    func removeFromStack(entryID: Int) {
        reuseController.removeFromStack(entryID: entryID)
    }

    func moveInStack(fromOffsets source: IndexSet, toOffset destination: Int) {
        reuseController.moveInStack(fromOffsets: source, toOffset: destination)
    }

    func pasteNextFromStack() {
        guard let item = reuseController.popNextFromStack() else { return }
        paste(item)
        if pasteStackEntries.isEmpty {
            toasts.show(GanchoToast(message: "Paste stack finished"))
        }
    }

    /// Sync-aware delete: when iCloud sync is active, leave a tombstone and
    /// propagate the deletion; otherwise a plain local delete.
    /// Deferred + reversible delete. The clip disappears from the list at once,
    /// but the destructive removal (and the sync tombstone that propagates it to
    /// every device) only commits after the undo window — so a mis-tap never
    /// loses history, and pins/boards/timestamps survive an Undo intact. If the
    /// app quits mid-window the commit never runs, so the clip is kept (safe).
    func delete(_ item: ClipItem) {
        delete([item])
    }

    /// Deletes one visible-order selection behind one grace timer and exposes
    /// one Undo action for the entire transaction.
    func delete(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        let transaction = reuseController.delete(
            items,
            performDelete: { [weak self] ids in
                guard let self else { return }
                if syncController.isEnabled, let grdbStore {
                    for id in ids {
                        _ = try? await grdbStore.deleteForSync(id: id, now: .now)
                    }
                    await syncController.engine.enqueueDeletion(ids: ids)
                } else {
                    for id in ids { _ = try? await store.delete(id: id) }
                }
                // After the COMMIT, not the intent — an undone delete must
                // keep its Spotlight entry.
                await refreshSpotlight()
            })
        toasts.show(
            GanchoToast(
                message: "Deleted",
                action: ToastAction(title: "Undo", accessibilityIdentifier: "toast-undo") {
                    [weak self] in
                    self?.reuseController.undoDeletion(transaction)
                }))
    }

    func togglePause() {
        captureLifecycle.toggleCapture()
    }

    func togglePrivateMode() {
        captureLifecycle.togglePrivateMode()
    }

    func ignoreNextCopy() {
        captureLifecycle.ignoreNextCopy()
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

    /// Persists a user-authored title and schedules sync only after the durable
    /// write succeeds. The view owns draft/error presentation.
    func updateClipTitle(_ item: ClipItem, title: String) async -> Bool {
        guard let grdbStore else { return false }
        switch await editingController.updateTitle(
            item, title: title, store: grdbStore, engine: syncController.engine)
        {
        case .saved:
            await refreshRecents()
            // The donated title/preview may have just changed.
            refreshSpotlight()
            return true
        case .unchanged:
            return true
        case .emptyContent, .notEditable:
            return false
        case .clipUnavailable:
            await refreshRecents()
            return false
        case .failed:
            diagnostics.record("Editing", "Couldn’t save the title.")
            return false
        }
    }

    /// Persists an explicit text-body edit, refreshes visible metadata after a
    /// successful durable write, and never logs the user-authored content.
    func updateClipText(_ item: ClipItem, text: String) async -> Bool {
        guard let grdbStore else { return false }
        switch await editingController.updateText(
            item, text: text, store: grdbStore, engine: syncController.engine)
        {
        case .saved:
            await refreshRecents()
            // The donated title/preview may have just changed.
            refreshSpotlight()
            return true
        case .unchanged:
            return true
        case .emptyContent, .notEditable:
            return false
        case .clipUnavailable:
            await refreshRecents()
            return false
        case .failed:
            diagnostics.record("Editing", "Couldn’t save the content.")
            return false
        }
    }

    private func recordBoardFailure(_ message: String.LocalizationValue) {
        diagnostics.record(String(localized: "Boards"), String(localized: message))
    }

    func togglePin(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            switch await curationController.togglePin(
                item, tier: tier, store: grdbStore, engine: syncController.engine)
            {
            case .pinned:
                toasts.show(GanchoToast(message: "Pinned"))
                await refreshRecents()
                refreshSpotlight()
            case .unpinned:
                toasts.show(GanchoToast(message: "Unpinned"))
                await refreshRecents()
                refreshSpotlight()
            case .alreadyPinned, .alreadyUnpinned, .clipUnavailable:
                // Reconcile a stale row snapshot without claiming a mutation.
                await refreshRecents()
            case .freeLimitReached:
                paywallWindow.show(trigger: .freeLimitReached, model: self)
            case .failed:
                diagnostics.record("Pins", "Couldn’t update the pin.")
            }
        }
    }

    /// The signature gesture: clip → permanent snippet (⌘S in the panel).
    func promoteToSnippet(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            switch await curationController.promoteToSnippet(
                item, tier: tier, store: grdbStore)
            {
            case .promoted:
                toasts.show(GanchoToast(message: "Saved as snippet"))
                await refreshRecents()
                refreshSpotlight()
            case .freeLimitReached:
                paywallWindow.show(trigger: .freeLimitReached, model: self)
            case .clipUnavailable:
                await refreshRecents()
            case .failed:
                diagnostics.record("Snippets", "Couldn’t save the snippet.")
            }
        }
    }

    /// Re-donates the curated Library to Spotlight (or wipes the domain when
    /// the toggle is off). Fire-and-forget at utility priority — a reconcile
    /// recomputes the whole small curated set, so it never needs to know WHAT
    /// changed and never rides a user interaction's critical path.
    func refreshSpotlight() {
        guard let grdbStore else { return }
        let enabled = spotlightIndexing
        Task(priority: .utility) {
            await LibrarySpotlightService(index: CoreSpotlightIndexer())
                .reconcile(store: grdbStore, enabled: enabled)
        }
    }

    func refreshBoards() async {
        guard let grdbStore else { return }
        boards = (try? await grdbStore.pinboards()) ?? []
    }

    func assign(_ item: ClipItem, toBoard board: Pinboard) {
        assign([item], toBoard: board)
    }

    func assign(_ items: [ClipItem], toBoard board: Pinboard) {
        Task {
            guard await setBoardMembership(items, board: board, member: true) else { return }
            toasts.show(GanchoToast(message: "Added to board"))
        }
    }

    /// Assign + a one-tap Undo (the board-suggestion accept path). The action is
    /// reversible, so offer the reversal in the toast instead of making the user
    /// hunt through the board menu to take it back.
    func assignWithUndo(_ item: ClipItem, toBoard board: Pinboard) {
        Task {
            guard await setBoardMembership(item, board: board, member: true) else { return }
            toasts.show(
                GanchoToast(
                    message: "Added to board",
                    action: ToastAction(title: "Undo") { [weak self] in
                        self?.unassign(item, fromBoard: board)
                    }))
        }
    }

    func unassign(_ item: ClipItem, fromBoard board: Pinboard) {
        Task {
            _ = await setBoardMembership(item, board: board, member: false)
        }
    }

    func removeFromAllBoards(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            let outcome = await BoardsController().removeFromAllBoards(
                item, store: grdbStore, engine: syncController.engine)
            guard outcome == .changed else {
                if outcome == .failed {
                    recordBoardFailure("Couldn’t remove the clip from its boards.")
                }
                return
            }
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
    @discardableResult
    func createBoard(
        named name: String, assigning item: ClipItem? = nil
    ) async -> BoardsController.BoardCreateOutcome {
        guard let grdbStore else { return .failed }
        let outcome = await BoardsController().createBoard(
            name: name, filing: item, store: grdbStore, engine: syncController.engine,
            isPro: tier == .pro,
            onFreeLimit: { self.paywallWindow.show(trigger: .freeLimitReached, model: self) },
            onAssigned: { self.toasts.show(GanchoToast(message: "Added to board")) })
        if outcome == .failed {
            recordBoardFailure("Couldn’t create the board.")
        } else if item != nil, case .created(_, filedClip: false) = outcome {
            recordBoardFailure("The board was created, but the clip couldn’t be added.")
        }
        guard outcome != .blocked else { return outcome }
        await refreshBoards()
        if case .created(let boardID, filedClip: true) = outcome {
            lastAssignedBoardID = boardID
        }
        if item != nil { await refreshRecents() }
        return outcome
    }

    /// Rename / delete are no-ops on the built-in Favorites board, so the UI
    /// only needs to hide the affordances.
    func renameBoard(_ board: Pinboard, name: String) {
        guard let grdbStore else { return }
        Task {
            let outcome = await BoardsController().renameBoard(
                board, name: name, store: grdbStore, engine: syncController.engine)
            if outcome == .failed {
                recordBoardFailure("Couldn’t rename the board.")
            }
            await refreshBoards()
        }
    }

    @discardableResult
    func updateBoardIdentity(_ board: Pinboard, colorHex: String?, emoji: String?) async -> Bool {
        guard let grdbStore else { return false }
        let outcome = await BoardsController().updateBoardIdentity(
            board, colorHex: colorHex, emoji: emoji, store: grdbStore,
            engine: syncController.engine)
        if outcome == .failed {
            recordBoardFailure("Couldn’t update the board appearance.")
        }
        await refreshBoards()
        return outcome != .failed
    }

    func deleteBoard(_ board: Pinboard) {
        guard let grdbStore else { return }
        Task {
            let outcome = await BoardsController().deleteBoard(
                board, store: grdbStore, engine: syncController.engine,
                syncEnabled: syncController.isEnabled)
            if outcome == .failed {
                recordBoardFailure("Couldn’t delete the board.")
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

    /// Boards shared by every selected clip. The picker uses this intersection
    /// for one unambiguous checkmark in a mixed batch.
    func commonBoardMembership(for items: [ClipItem]) async -> Set<UUID> {
        guard let first = items.first else { return [] }
        var common = await boardMembership(for: first)
        for item in items.dropFirst() {
            guard !common.isEmpty else { break }
            common.formIntersection(await boardMembership(for: item))
        }
        return common
    }

    /// Add or remove a clip from one board (the peek's per-board toggle and the
    /// ⌘B picker). Remembers the board so ⇧⌘B can repeat it on the next clip.
    @discardableResult
    func setBoardMembership(_ item: ClipItem, board: Pinboard, member: Bool) async -> Bool {
        await setBoardMembership([item], board: board, member: member)
    }

    /// Applies one board membership choice to the selected clips atomically and
    /// refreshes presentation once after the durable transaction completes.
    @discardableResult
    func setBoardMembership(_ items: [ClipItem], board: Pinboard, member: Bool) async -> Bool {
        guard let grdbStore else { return false }
        guard !items.isEmpty else { return false }
        let succeeded = await BoardsController().setBoardMembership(
            items, board: board, member: member, store: grdbStore,
            engine: syncController.engine)
        guard succeeded else {
            recordBoardFailure(
                member
                    ? "Couldn’t add every clip to the board."
                    : "Couldn’t remove every clip from the board.")
            await refreshRecents()
            return false
        }
        if member { lastAssignedBoardID = board.id }
        await refreshRecents()
        return true
    }

    /// The last board a clip was filed into, for the ⇧⌘B "repeat" shortcut.
    /// Persisted (UserDefaults) so it survives relaunch, like the panel position.
    var lastAssignedBoardID: UUID? {
        get { defaults.string(forKey: "last-assigned-board").flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: "last-assigned-board") }
    }

    /// ⇧⌘B: file the clip into the last board used, so curating many clips into
    /// the same board is one keystroke each. A no-op (with a nudge) when there is
    /// no remembered board or it has since been deleted.
    func assignToLastBoard(_ item: ClipItem) {
        assignToLastBoard([item])
    }

    func assignToLastBoard(_ items: [ClipItem]) {
        guard let id = lastAssignedBoardID, let board = boards.first(where: { $0.id == id }) else {
            toasts.show(GanchoToast(message: "Pick a board with ⌘B first"))
            return
        }
        assign(items, toBoard: board)
    }

    // MARK: - Denylist & settings portability

    /// Bumped on every denylist mutation. The list itself lives inside the
    /// non-observable monitor, so the computed properties below read this
    /// stored value to give SwiftUI something to track — without it, a remove
    /// wouldn't refresh the Settings list until an unrelated state change.
    private(set) var denylistRevision = 0

    var denylistEntries: [String] {
        _ = denylistRevision
        let effective = SourceAppDenylist.suggestedBundleIDs
            .subtracting(monitor.denylist.disabledSuggestions)
            .union(monitor.denylist.userBundleIDs)
        return effective.sorted()
    }

    /// True when the user re-enabled captures from any built-in exclusion —
    /// gates the Settings "Restore default exclusions" button.
    var hasDisabledDenylistSuggestions: Bool {
        _ = denylistRevision
        return !monitor.denylist.disabledSuggestions.isEmpty
    }

    func addToDenylist(_ bundleID: String) {
        // Trim pasted whitespace/newlines so a manual entry actually matches the
        // frontmost app's bundle id (an untrimmed entry silently never matches).
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        monitor.denylist.add(trimmed)
        monitor.denylist.save(to: defaults)
        denylistRevision += 1
    }

    func removeFromDenylist(_ bundleID: String) {
        monitor.denylist.remove(bundleID)
        monitor.denylist.save(to: defaults)
        denylistRevision += 1
    }

    /// Puts every built-in exclusion back on the denylist (user-added entries
    /// are untouched).
    func restoreDenylistDefaults() {
        monitor.denylist.restoreSuggestions()
        monitor.denylist.save(to: defaults)
        denylistRevision += 1
    }

    /// Preferences only — never clips (reinstall portability).
    func settingsSnapshot() throws -> SettingsSnapshot {
        SettingsSnapshot(
            retention: retentionPolicy,
            capturePreferencesJSON: (try? JSONEncoder().encode(preferences)) ?? Data(),
            appSettings: [
                "panel-position": panel.position.rawValue,
                "appearance": appearance.rawValue
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
        if let raw = snapshot.appSettings["appearance"],
            let value = AppearancePreference(rawValue: raw)
        {
            appearance = value
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

    /// Periodic pull (and push of anything pending) for the Mac. CloudKit push
    /// drives sync while awake, but a menu-bar AGENT (`.accessory`, no key
    /// window, resident in the background) is not a reliable push target the way
    /// the foreground iPhone app is — so it also polls on a light cadence to pull
    /// clips copied on other devices and flush its own pending uploads (e.g. an
    /// AI title that landed a beat after the clip). `syncNow()` is a no-op when
    /// sync is off and cheap when the change token is already current, so an idle
    /// tick is just one small round-trip.
    private func scheduleSyncPoll() {
        syncPollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.syncController.syncNow() }
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
