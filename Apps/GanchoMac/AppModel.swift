import AppIntents
import AppKit
import ApplicationServices
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
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

    /// UI-test paste sink: writes nothing, so a paste flow can run on a
    /// developer's desktop without replacing their clipboard. Opted in by launch
    /// argument only (see `AppModel.makePasteBackService`).
    private struct UITestDiscardingPasteboardWriter: PasteboardWriting {
        func write(_ content: ClipContent, asPlainText: Bool) {}
        func currentText() -> String? { nil }
    }

    /// UI-test paste sink: posts no ⌘V, so a test can never type into another app.
    private struct UITestDiscardingKeyEventPoster: KeyEventPosting {
        func postCommandKey(keyCode: CGKeyCode) {}
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
    /// Clips inside an undo window. The panel watches this to reconcile its
    /// cached list on the delete AND on the undo; `recentItems` only moves on
    /// the delete.
    var pendingDeletionIDs: Set<UUID> { reuseController.pendingDeletionIDs }
    /// True when the durable store failed to open and the app is running on the
    /// in-memory fallback — history won't survive a relaunch, so the panel warns.
    var storageIsEphemeral: Bool { !store.isDurable }

    /// Durable store under Application Support; falls back to in-memory if
    /// the disk store cannot open (never block launch on a storage error).
    let store: any ClipboardStore
    /// Atomic migration surface over the same concrete store. Kept separate
    /// from `ClipboardStore` so test doubles and ordinary clients do not gain
    /// import-only responsibilities.
    let migrationStore: any ClipImporting
    /// Full first-party store surface, downcast once from `store`; nil on the
    /// in-memory fallback. Feature code (this model and the views) reaches every
    /// capability through it instead of downcasting to the concrete class.
    ///
    /// Named for the facet, NOT the implementation, and deliberately so: this
    /// was `grdbStore`, which read as a concrete `GRDBClipboardStore` handle
    /// and sent readers looking for GRDB APIs that are not on it. The concrete
    /// handle is the next property, and it says so.
    let fullStore: (any FullClipStore)?
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
    let pasteBack = AppModel.makePasteBackService()
    let privacyEvents = InMemoryPrivacyEventRecorder()
    /// Content-free log of recent operational issues (storage that wouldn't
    /// open, a sync that failed) for the Privacy Center and support — never any
    /// clip text, never persisted or uploaded.
    let diagnostics = DiagnosticLog()
    let panel: PanelController
    /// Transient HUD for action feedback (copy-only paste, pin/unpin).
    let toasts = ToastPresenter()
    /// Content-free store-mutation fan-out. Mutation sites post here instead of
    /// each remembering to call every reconciler; the `SpotlightCoordinator`
    /// subscribes and rebuilds the curated Spotlight set once per burst. This
    /// closes the "forgot to refresh X" class of bug (the two Spotlight-
    /// staleness blockers were exactly that).
    let storeChanges = StoreChangeBus()
    /// Owns the curated-Spotlight reconcile (bus subscription + debounce + the
    /// single donate/wipe worker). Reads the store and toggle at reconcile
    /// time, so it always donates the current curated set. Built and retained in
    /// `init` (not an inline property initializer: its `@MainActor` reconcile
    /// closures can only be formed inside an isolated body, never a default-
    /// argument context). `@ObservationIgnored` — it is infrastructure, never
    /// observed.
    @ObservationIgnored private var spotlightCoordinator: SpotlightCoordinator?
    let welcomeWindow = WelcomeWindowController()
    let privacyCenterWindow = PrivacyCenterWindowController()
    let paywallWindow = PaywallWindowController()
    let permissionWindow = PasteboardPermissionWindowController()
    let libraryWindow = LibraryWindowController()
    let savedFilters: SavedFiltersController
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

    /// Local MCP server opt-in + per-client grants, persisted beside the store
    /// so the `gancho` CLI and app resolve the same live authorization state.
    private(set) var mcpConfig: MCPServerConfig = .init()
    private let mcpConfigDirectory: URL

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
    private let deletionWorkflow = ClipDeletionWorkflow()
    private let editingController = ClipEditingController()
    private let ingestionCoordinator = ClipIngestionCoordinator()
    private let enrichmentScheduler = EnrichmentScheduler()
    private let defaults: UserDefaults
    private let activationTracker: ActivationTracker
    private var retentionTimer: Timer?
    /// Light periodic sync pull for the menu-bar agent (see `scheduleSyncPoll`).
    private var syncPollTimer: Timer?
    /// Held so the observer outlives `init`; set by the UI-test launch hook in
    /// `AppModel+UITestLaunch`, which is why it is not private.
    var uiTestPanelObserver: NSObjectProtocol?
    var uiTestPanelHasOpened = false
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
        // Launch → durable store ready (the panel's first usable moment).
        let launchInterval = Signpost.launchToStoreReady.begin()
        let appDefaults = Self.defaultsForLaunch()
        // One-way migration from versions that allowed a Dock override. Gancho
        // is now permanently menu-bar-only, so an existing `true` must not
        // survive as latent configuration or reappear in an exported snapshot.
        appDefaults.removeObject(forKey: "show-in-dock")
        defaults = appDefaults
        panel = PanelController(defaults: appDefaults)
        activationTracker = ActivationTracker(defaults: appDefaults)
        let directory = SharedStorageLocation.macAppStoreDirectory
        // Which store this launch wants, and opening it, both live in
        // `StoreBootstrap` — including the two UI-test hooks (a throwaway
        // durable store, and the forced in-memory fallback that makes the
        // "history isn't being saved" warning drivable). The throwaway store is
        // encrypted here so the Mac UI tests exercise the real open path.
        let storeRequest = StoreBootstrap.request()
        let opened = StoreBootstrap.open(
            storeRequest,
            configuration: StoreBootstrap.Configuration(
                productionDirectory: { directory },
                throwawayIsEncrypted: true,
                throwawayDirectoryPrefix: "gancho-uitest-store"))
        let grdb = opened.durable
        // MCP config follows the store: into the throwaway directory for a UI
        // test, into a scratch directory when there is no store at all, and
        // beside the real database otherwise. `opened.directory` reports the
        // chosen location even when the open failed, which is what keeps the
        // config file from moving on exactly those launches.
        let mcpConfigDirectory =
            opened.directory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "gancho-uitest-mcp-\(UUID().uuidString)", isDirectory: true)
        self.mcpConfigDirectory = mcpConfigDirectory
        self.fullStore = grdb
        self.savedFilters = SavedFiltersController(store: grdb)
        self.grdbForEngines = grdb
        if let grdb {
            self.store = grdb
            self.migrationStore = grdb
        } else {
            let memoryStore = InMemoryClipboardStore()
            self.store = memoryStore
            self.migrationStore = memoryStore
        }
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
        var loadedMCPConfig = MCPServerConfig.load(fromStoreDirectory: mcpConfigDirectory)
        #if DEBUG
            // Only ever into a THROWAWAY store — seeding grants beside the
            // user's real database would rewrite their MCP config. The guard
            // used to read "a temp directory exists", which meant the same
            // thing by accident; now it says it.
            if ProcessInfo.processInfo.arguments.contains("-seed-mcp-grants"),
                storeRequest == .throwaway
            {
                loadedMCPConfig = Self.sampleMCPConfig()
                try? loadedMCPConfig.save(toStoreDirectory: mcpConfigDirectory)
            }
        #endif
        self.mcpConfig = loadedMCPConfig

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
            let loadedAutoPauseOnScreenShare =
                CommandLine.arguments.contains("-disable-screen-share-auto-pause")
                ? false : appDefaults.object(forKey: "auto-pause-screen-share") as? Bool ?? true
        #else
            let loadedAutoPauseOnScreenShare =
                appDefaults.object(forKey: "auto-pause-screen-share") as? Bool ?? true
        #endif
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
        if telemetryConsent != .disabled { activationTracker.start() }

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
            reader: Self.pasteboardReaderForLaunch(),
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
            guard let self else { return }
            privacyEvents.record(IgnoredCaptureEvent(reason: reason))
            Task {
                try? await fullStore?.recordPrivateSkippedCapture(
                    isProtected: reason == .sensitiveType, count: 1, at: .now)
            }
        }
        // Turning "remember searches" off promises the stored queries are
        // gone. Report a failed erase instead of leaving the toggle reading
        // "off" over a history that is still on disk.
        reuseController.setSearchHistoryClearFailureObserver { [weak self] in
            self?.diagnostics.record(
                String(localized: "Privacy"),
                String(
                    localized: "Stored searches couldn’t be erased. Try turning it off again."))
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
        // UI-test hook: this seed must land BEFORE the launch pass, so the
        // receipt can only show its expiry if the scheduled pass really ran.
        let expiredSensitiveSeed = seedExpiredSensitiveClipIfRequested()
        let launchRetentionPass = scheduleRetention(after: expiredSensitiveSeed)
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
        // StoreKit streams out-of-process tier changes. The direct-download
        // handler instead reconciles Lemon Squeezy on the scheduled launch
        // refresh below.
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
                #if GANCHO_DIRECT_DOWNLOAD
                    // Re-confirm the Lemon Squeezy license when it is due. This
                    // runs AFTER the offline tier is applied, so a slow or
                    // unreachable network never delays launch — and a revoked
                    // license still drops Pro on the next launch that reaches
                    // Lemon Squeezy.
                    if let license = purchases as? LicenseKeyPurchaseHandler {
                        let refreshed = await license.refreshIfNeeded()
                        if refreshed != tier { applyTier(refreshed) }
                    }
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
        // Whatever waits on the seeds must also wait on the launch pass: the pass
        // is what turns the expired-secret seed into a receipt entry. Built in one
        // expression so the array stays a `let` the seed-waiting tasks can capture.
        let uiTestSeedTasks =
            seedUITestFixturesIfRequested()
            + (expiredSensitiveSeed.map { [$0, launchRetentionPass] } ?? [])
        // Post-launch maintenance, sequential at utility priority once the UI
        // is wired up: the cosmetic legacy-preview backfill (moved off the
        // synchronous store open — it scanned image rows on every launch),
        // then the embedding refresh (a model bump leaves old vectors behind;
        // no-op while the pipeline version is unchanged), then the Spotlight
        // reconcile (repairs any curation change the app missed and applies
        // the toggle state). None of them ever touch capture or the first
        // panel open.
        // Curated-Spotlight coordinator: one reconcile worker for both the
        // launch repair and the bus-driven refresh. Reads the store and toggle
        // at reconcile time via `[weak self]`, so it always donates the current
        // set (and stays correct across a store re-key).
        let coordinator = SpotlightCoordinator(
            coalescer: SpotlightCoordinator.defaultCoalescer,
            reconcile: { [weak self] in
                guard let self, let store = fullStore else { return nil }
                return await LibrarySpotlightService(index: CoreSpotlightIndexer())
                    .reconcile(store: store, enabled: spotlightIndexing)
            },
            onFailure: { [weak self] in
                self?.diagnostics.record("Spotlight", "Couldn’t update the Spotlight index.")
            })
        spotlightCoordinator = coordinator

        if let grdb {
            // The ordered post-launch maintenance pipeline (backfill → optional
            // embedding refresh → Spotlight reconcile). The order and the
            // gating live in the declared steps, not an inline Task, so they
            // are unit-tested in MaintenanceRunnerTests.
            let steps = [
                MaintenanceStep("legacy-preview-backfill") {
                    try? await grdb.backfillLegacyPreviews()
                },
                MaintenanceStep("embedding-refresh", isEnabled: intelligence.semanticSearch) {
                    await EmbeddingRefreshService().run(store: grdb)
                },
                // Same reconcile worker the bus uses — repairs any curation
                // change missed while not running and applies the toggle state.
                MaintenanceStep("spotlight-reconcile") {
                    await coordinator.reconcileNow()
                }
            ]
            Task(priority: .utility) { await MaintenanceRunner().run(steps) }
        }

        Signpost.launchToStoreReady.end(launchInterval)

        Task { await savedFilters.load(migrating: defaults) }
        coordinator.start(subscribingTo: storeChanges)

        // What a launch opens is one decision (`LaunchPresentation`), taken here
        // and presented by the shell. The UI-test hooks that open a window
        // directly live in `AppModel+UITestLaunch`.
        switch LaunchPresentation.decide(
            opensPanel: CommandLine.arguments.contains("-open-panel-on-launch"),
            forcesWelcome: CommandLine.arguments.contains("-open-welcome-on-launch"),
            hasSeenWelcome: defaults.bool(forKey: "has-seen-welcome"),
            monitorStatus: monitor.status)
        {
        case .panel:
            showPanelOnLaunchForUITest(afterSeeds: uiTestSeedTasks)
        case .welcome:
            Task { welcomeWindow.show(model: self) }
        case .pasteboardPermission:
            Task { permissionWindow.show(model: self) }
        case .menuBarOnly:
            break
        }
        openUITestWindowsIfRequested(afterSeeds: uiTestSeedTasks)
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    // MARK: - Capture pipeline

    func ingest(_ capture: PasteboardCapture) {
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
                allowsFreeTitle: freeAITitlesRemaining > 0,
                sourceDeviceName: DeviceProvenance.currentDeviceName())
            // Closed by the coordinator the moment the insert phase ends, on
            // success and on failure both — NOT when `ingest` returns. `ingest`
            // also awaits the sync enqueue, which builds `CKSyncEngine` on
            // first use, and folding CloudKit setup into a capture metric would
            // make the first capture after launch an outlier about something
            // else entirely.
            let ingestInterval = Signpost.captureToInsert.begin()
            guard
                let outcome = try? await ingestionCoordinator.ingest(
                    capture,
                    configuration: configuration,
                    store: store,
                    syncEngine: syncController.engine,
                    didFinishInsert: { Signpost.captureToInsert.end(ingestInterval) })
            else { return }
            // Bucketized analytics: kind + a length BUCKET, never the content.
            telemetry.record(
                .itemCaptured(
                    type: outcome.item.kind,
                    lengthBucket: .init(characterCount: outcome.contentLength)))
            if outcome.isNew { recordActivationMilestone(.firstCapture) }
            try? await fullStore?.recordPrivateCapture(
                sourceAppBundleID: capture.sourceAppBundleID,
                count: 1,
                at: capture.capturedAt)
            await refreshRecents()
            enrich(outcome)
        }
    }

    #if DEBUG
        private static func sampleMCPConfig() -> MCPServerConfig {
            let now = Date()
            let context = MCPContextPack(
                name: "Favorites · last 7 days",
                boardID: Pinboard.favoritesID,
                boardName: "Favorites",
                timeScope: .lastWeek)
            return MCPServerConfig(
                isEnabled: true,
                grants: [
                    MCPClientGrant(
                        id: UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!,
                        clientName: "Claude Desktop",
                        scope: .all,
                        accessMode: .readOnly,
                        contextPack: context,
                        createdAt: now.addingTimeInterval(-3_600),
                        expiresAt: now.addingTimeInterval(6 * 86_400)),
                    MCPClientGrant(
                        id: UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!,
                        clientName: "Cursor",
                        scope: .metadata,
                        accessMode: .readOnly,
                        contextPack: context,
                        createdAt: now.addingTimeInterval(-10 * 86_400),
                        expiresAt: now.addingTimeInterval(-3 * 86_400)),
                    MCPClientGrant(
                        id: UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!,
                        clientName: "Local scripts",
                        scope: .boards,
                        accessMode: .readWrite,
                        contextPack: context,
                        createdAt: now.addingTimeInterval(-2 * 86_400),
                        expiresAt: now.addingTimeInterval(5 * 86_400),
                        revokedAt: now.addingTimeInterval(-300))
                ])
        }
    #endif
    /// Pro-tier async enrichment — never blocks capture: OCR makes image
    /// clips searchable; the tiered annotator titles text clips.
    private func enrich(_ outcome: ClipIngestionCoordinator.Outcome) {
        guard !outcome.enrichment.isEmpty, let fullStore else { return }
        let syncEngine: (any SyncEngine)? =
            syncController.isEnabled ? syncController.engine : nil
        Task(priority: .utility) { [enrichmentScheduler] in
            // Bounded: a burst of copies used to leave one enrichment in
            // flight per clip, each holding its own model session and
            // competing for the same Neural Engine.
            await enrichmentScheduler.run(copiedAt: outcome.item.createdAt) {
                await ingestionCoordinator.enrich(
                    outcome,
                    store: fullStore,
                    syncEngine: syncEngine
                ) { @MainActor [self] in
                    if outcome.enrichment.usesFreeTitle {
                        consumeFreeAITitle()
                        // The moment the taste runs out is the conversion
                        // moment: a gentle, tappable nudge — never an
                        // interrupting gateway.
                        if freeAITitlesRemaining == 0 { showAITasteEndedNudge() }
                    }
                    await refreshRecents()
                }
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

    /// The real paste-back service or, in DEBUG UI tests only, one that writes
    /// nothing and posts nothing. `-ui-test-paste-sink pasted` answers as if
    /// Accessibility were granted; any other value, or none, answers copy-only.
    /// It fails safe: a mistyped value still never reaches the real pasteboard
    /// or types ⌘V into whatever app is frontmost.
    private static func makePasteBackService() -> PasteBackService {
        #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "-ui-test-paste-sink") {
                let answersPasted =
                    CommandLine.arguments.indices.contains(index + 1)
                    && CommandLine.arguments[index + 1] == "pasted"
                return PasteBackService(
                    writer: UITestDiscardingPasteboardWriter(),
                    poster: UITestDiscardingKeyEventPoster(),
                    isAccessibilityTrusted: { answersPasted })
            }
        #endif
        return PasteBackService()
    }

    /// The paste sequence every entry point below shares; see `PasteBackWorkflow`.
    private var pasteBackWorkflow: PasteBackWorkflow {
        PasteBackWorkflow(
            effects: .init(
                hidePanel: { [panel] in panel.hide() },
                // One beat for focus to return to the app the user was in.
                waitForFocusToReturn: { try? await Task.sleep(for: .milliseconds(80)) },
                paste: { [pasteBack] content, asPlainText in
                    pasteBack.paste(content, asPlainText: asPlainText)
                },
                noticeCopyOnly: { [weak self] in self?.showCopyOnlyToast() }))
    }

    /// Paste a stored clip into the frontmost app (panel Enter / menu click).
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        let intendedTarget = currentReuseTargetBundleID()
        Task {
            // Paste action → event posted. The target app's behavior and the
            // reuse bookkeeping are deliberately outside the interval, and an
            // unreadable clip closes it too, so it never reads as an eternal paste.
            let interval = Signpost.pasteDispatch.begin()
            let content = try? await store.content(for: item.id)
            let delivery = await pasteBackWorkflow.deliver(
                content,
                asPlainText: asPlainText,
                intendedTarget: intendedTarget,
                endInterval: { Signpost.pasteDispatch.end(interval) },
                recordReuse: { confirmedTarget in
                    await recordSuccessfulReuse(
                        .paste, items: [item], targetBundleID: confirmedTarget)
                })
            guard case .delivered(let outcome) = delivery else { return }
            if outcome == .pasted, asPlainText {
                toasts.show(GanchoToast(message: "Pasted as plain text"))
            }
            // Activation metric (local, content-free): first paste-back ever.
            if defaults.object(forKey: "first-pasteback-at") == nil {
                defaults.set(Date().timeIntervalSince1970, forKey: "first-pasteback-at")
            }
            defaults.set(
                defaults.integer(forKey: "pasteback-count") + 1, forKey: "pasteback-count")
            if let suggestion = await reuseController.recordPaste(of: item),
                shouldPresentReuseSuggestion(after: outcome)
            {
                await presentReuseSuggestion(suggestion)
            }
        }
    }

    func setTelemetryConsent(_ consent: TelemetryConsent) {
        guard consent != .notAsked, consent != telemetryConsent else { return }
        if consent == .enabled { activationTracker.start() }
        telemetryConsent = consent
        if consent == .enabled {
            telemetry.record(.activationSnapshot(activationTracker.snapshot()))
        } else {
            activationTracker.reset()
        }
    }

    func requestTelemetryConsentAfterFirstValue() {
        guard telemetryConsent == .notAsked else { return }
        isTelemetryConsentPromptPresented = true
    }

    func privateActivityReceipt() async -> PrivateActivityReceipt {
        (try? await fullStore?.privateActivityReceipt(now: .now)) ?? .empty()
    }

    func clearPrivateActivityReceipt() async {
        try? await fullStore?.clearPrivateActivityReceipt()
    }

    func recordActivationMilestone(_ milestone: ActivationMilestone) {
        guard telemetryConsent != .disabled,
            let receipt = activationTracker.record(milestone)
        else { return }
        guard telemetryConsent == .enabled else { return }
        telemetry.record(
            .activationMilestone(
                milestone: receipt.milestone, elapsedBucket: receipt.elapsedBucket))
    }

    private func recordSuccessfulReuse(
        _ method: SuccessfulReuseMethod,
        items: [ClipItem],
        itemCount: Int? = nil,
        targetBundleID: String?
    ) async {
        let count = itemCount ?? items.count
        guard count > 0 else { return }
        try? await fullStore?.recordPrivateReuse(
            targetAppBundleID: targetBundleID, itemCount: count, at: .now)
        recordActivationMilestone(.firstSuccessfulReuse)
        let ageBucket: TelemetryEvent.AgeBucket =
            items.count == 1
            ? .init(age: Date().timeIntervalSince(items[0].createdAt)) : .unknown
        telemetry.record(
            .successfulReuse(
                method: method, batchSize: .init(count: count), ageBucket: ageBucket))
        requestTelemetryConsentAfterFirstValue()
    }

    /// The production panel is nonactivating, so the OS frontmost application
    /// remains the intended destination while Gancho floats above it. UI tests
    /// activate Gancho itself; treat that as unknown rather than recording a
    /// false self-target.
    private func currentReuseTargetBundleID() -> String? {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard bundleID != Bundle.main.bundleIdentifier else { return nil }
        return bundleID
    }

    func finishOnboarding(completed: Bool, openPanel: Bool) {
        defaults.set(true, forKey: "has-seen-welcome")
        if completed { recordActivationMilestone(.onboardingCompleted) }
        welcomeWindow.close()
        if openPanel { panel.show(model: self) }
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
        guard !items.isEmpty else { return }
        let targetBundleID = currentReuseTargetBundleID()
        var firstSuggestion: ClipItem?
        for item in items {
            if let suggestion = await reuseController.recordDragDelivery(of: item),
                firstSuggestion == nil
            {
                firstSuggestion = suggestion
            }
        }
        if let firstSuggestion { await presentReuseSuggestion(firstSuggestion) }
        await recordSuccessfulReuse(.drag, items: items, targetBundleID: targetBundleID)
    }

    /// Paste with a pure transform applied at paste time.
    func paste(_ item: ClipItem, transform: PasteTransform) {
        let intendedTarget = currentReuseTargetBundleID()
        Task {
            guard case .text(let text)? = try? await store.content(for: item.id) else {
                paste(item, asPlainText: transform == .plainText)
                return
            }
            let delivery = await pasteBackWorkflow.deliver(
                .text(transform.apply(to: text)),
                asPlainText: true,
                intendedTarget: intendedTarget,
                recordReuse: { confirmedTarget in
                    await recordSuccessfulReuse(
                        .transform, items: [item], targetBundleID: confirmedTarget)
                })
            guard case .delivered(let outcome) = delivery else { return }
            if let suggestion = await reuseController.recordPaste(of: item),
                shouldPresentReuseSuggestion(after: outcome)
            {
                await presentReuseSuggestion(suggestion)
            }
        }
    }

    /// Operational paste feedback outranks optional curation: a copy-only paste
    /// is already showing the Accessibility notice, so no suggestion competes
    /// with it. UI tests reach the suggestion honestly, through
    /// `-ui-test-paste-sink pasted`, rather than through an exception here.
    private func shouldPresentReuseSuggestion(after outcome: PasteBackOutcome) -> Bool {
        outcome == .pasted
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
        guard fullStore != nil else { return }
        let intendedTarget = currentReuseTargetBundleID()
        Task {
            guard case .text(let body)? = try? await store.content(for: snippet.id) else { return }
            await pasteBackWorkflow.deliver(
                .text(SnippetTemplate.fill(body, values: values)),
                asPlainText: false,
                intendedTarget: intendedTarget,
                recordReuse: { confirmedTarget in
                    await recordSuccessfulReuse(
                        .snippet, items: [snippet], targetBundleID: confirmedTarget)
                })
            await reuseController.recordSnippetPaste(of: snippet)
        }
    }

    /// The snippet invoked by an exact keyword, if any (the panel's expansion).
    func snippet(matchingKeyword keyword: String) async -> ClipItem? {
        (try? await fullStore?.snippet(matchingKeyword: keyword))
    }

    // MARK: - Smart paste (deterministic + on-device Apple Intelligence)

    private let intelligenceFacade = ClipIntelligenceFacade()

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
        intelligence.smartPaste && ClipIntelligenceFacade.modelAvailable
    }

    func smartPaste(_ text: String, action: SmartPasteAction) async -> String? {
        await intelligenceFacade.transform(text, action: action)
    }

    func smartTranslate(_ text: String, to target: Locale.Language) async -> String? {
        await intelligenceFacade.translate(text, to: target)
    }

    // MARK: - Ask your clipboard (grounded on-device QA)

    /// A grounded answer plus the clips it was drawn from (for citing/pasting).
    struct ClipboardAnswer: Identifiable, Sendable {
        let id = UUID()
        let answer: String
        let sources: [ClipItem]
    }

    var askAvailable: Bool { ClipIntelligenceFacade.askAvailable }

    /// Maps the shared ask-your-clipboard outcome onto this app's localized
    /// answer copy. Retrieval, the sensitive-clip filter and availability all
    /// live in the facade; only these strings are macOS's own.
    func askClipboard(_ question: String) async -> ClipboardAnswer? {
        switch await intelligenceFacade.ask(
            question, store: fullStore, useSemantic: intelligence.semanticSearch)
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
        let intendedTarget = currentReuseTargetBundleID()
        Task {
            await pasteBackWorkflow.deliver(
                .text(text),
                asPlainText: false,
                intendedTarget: intendedTarget,
                recordReuse: { confirmedTarget in
                    await recordSuccessfulReuse(
                        .smartPaste, items: [], itemCount: 1, targetBundleID: confirmedTarget)
                })
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
                let outcome = await deletionWorkflow.delete(
                    ids: ids,
                    store: store,
                    syncStore: fullStore,
                    engine: syncController.engine,
                    syncEnabled: syncController.isEnabled)
                reportDeletionFailure(outcome)
                // After the COMMIT, not the intent — an undone delete must
                // keep its Spotlight entry.
                refreshSpotlight(for: .clips)
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

    @discardableResult
    func createMCPGrant(
        clientName: String,
        scope: MCPAccessScope,
        accessMode: MCPAccessMode,
        board: Pinboard,
        timeScope: MCPTimeScope,
        expiresAt: Date?
    ) -> MCPClientGrant {
        let contextName = "\(board.name) · \(timeScope.rawValue)"
        let grant = MCPClientGrant(
            clientName: String(
                clientName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(MCPClientGrant.maximumClientNameLength)),
            scope: scope,
            accessMode: accessMode,
            contextPack: MCPContextPack(
                name: contextName,
                boardID: board.id,
                boardName: board.name,
                timeScope: timeScope),
            expiresAt: expiresAt)
        updateMCPConfig {
            $0.isEnabled = true
            $0.grants.append(grant)
        }
        return grant
    }

    func revokeMCPGrant(id: UUID) {
        updateMCPConfig { config in
            guard let index = config.grants.firstIndex(where: { $0.id == id }) else { return }
            config.grants[index].revokedAt = .now
        }
    }

    private func updateMCPConfig(_ mutate: (inout MCPServerConfig) -> Void) {
        var config = mcpConfig
        mutate(&config)
        do {
            try config.save(toStoreDirectory: mcpConfigDirectory)
            mcpConfig = config
        } catch {
            // A failed save leaves the in-memory config untouched, so the row
            // simply does not change state. Without a toast that is
            // indistinguishable from "the click never landed" — the exact
            // ambiguity that makes a revoke look like it worked when it did
            // not.
            toasts.show(
                GanchoToast(
                    message: "Couldn’t save local agent access settings.", style: .warning))
            diagnostics.record(
                String(localized: "MCP Access"),
                String(localized: "Couldn’t save local agent access settings."))
        }
    }

    /// Recent MCP/CLI accesses for the Privacy Center (metadata only).
    func recentMCPAccesses(limit: Int = 20) async -> [MCPAccessEvent] {
        guard let grdbForEngines else { return [] }
        return (try? await grdbForEngines.recentMCPAccesses(limit: limit)) ?? []
    }

    func buyPlan(_ plan: ProProduct.Plan) {
        defaults.set(defaults.integer(forKey: "upgrade-started") + 1, forKey: "upgrade-started")
        Task {
            do {
                // Only a cancel is silent. A product that would not load or a
                // transaction StoreKit could not verify used to be
                // indistinguishable from one, which left the user staring at an
                // unchanged tier with nothing said.
                switch try await purchases.purchase(plan) {
                case .entitled:
                    defaults.set(
                        defaults.integer(forKey: "upgrade-completed") + 1,
                        forKey: "upgrade-completed")
                case .cancelled:
                    break
                case .pending:
                    toasts.show(
                        GanchoToast(
                            message: "Your purchase is waiting for approval.", style: .pending))
                case .failed:
                    toasts.show(
                        GanchoToast(message: "Couldn’t complete the purchase.", style: .warning))
                }
            } catch {
                toasts.show(
                    GanchoToast(message: "Couldn’t complete the purchase.", style: .warning))
            }
        }
    }

    func restorePurchases() {
        Task {
            do {
                _ = try await purchases.restorePurchases()
            } catch {
                // "Nothing to restore" and "the request failed" are different
                // answers; only the second is worth interrupting for.
                toasts.show(
                    GanchoToast(message: "Couldn’t restore purchases.", style: .warning))
            }
        }
    }

    #if GANCHO_DIRECT_DOWNLOAD
        /// What the stored Lemon Squeezy activation is worth right now, so the
        /// paywall can tell "never bought" apart from "bought, but not confirmed
        /// lately" and offer the right way forward.
        var licenseEntitlement: LicenseEntitlement {
            (purchases as? LicenseKeyPurchaseHandler)?.entitlement ?? .none
        }

        /// Asks Lemon Squeezy again right now, regardless of the schedule — the
        /// "check again" the paywall offers a lapsed license.
        func recheckLicense() async {
            guard let license = purchases as? LicenseKeyPurchaseHandler else { return }
            applyTier(await license.recheckNow())
        }

        /// Releases this Mac's activation slot so the license can move.
        @discardableResult
        func deactivateLicense() async -> LicenseActivationResult {
            guard let license = purchases as? LicenseKeyPurchaseHandler else {
                return .notLicensable
            }
            let result = await license.deactivate()
            applyTier(await purchases.currentTier())
            return result
        }
    #endif

    /// Activates a direct-download Lemon Squeezy license key. Reports the
    /// distinguishable outcome (activated / wrong key / no network / not
    /// licensable) so the paywall can guide the user instead of dead-ending
    /// every failure on one message. The tier is reconciled from the persisted
    /// activation record either way.
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
                        transport: { try await licenseURLSession.data(for: $0) })),
                instanceName: Host.current().localizedName ?? "Mac")
        #else
            return StoreKitPurchaseHandler()
        #endif
    }

    /// License requests never need the shared session's cache, cookies, or
    /// open-ended connectivity waiting. A short-lived failure stays a network
    /// outcome and lets the entitlement policy preserve the offline grace
    /// window rather than stranding app launch behind a request.
    private static let licenseURLSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    // MARK: - Pins & boards

    private(set) var boards: [Pinboard] = []

    /// Persists a user-authored title and schedules sync only after the durable
    /// write succeeds. The view owns draft/error presentation.
    func updateClipTitle(_ item: ClipItem, title: String) async -> Bool {
        guard let fullStore else { return false }
        switch await editingController.updateTitle(
            item, title: title, store: fullStore, engine: syncController.engine)
        {
        case .saved:
            await refreshRecents()
            // The donated title/preview may have just changed.
            refreshSpotlight(for: .clips)
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
        guard let fullStore else { return false }
        switch await editingController.updateText(
            item, text: text, store: fullStore, engine: syncController.engine)
        {
        case .saved:
            await refreshRecents()
            // The donated title/preview may have just changed.
            refreshSpotlight(for: .clips)
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

    /// Content-free note when a delete did not fully land. `refreshRecents`
    /// (via the deletion coordinator's `didFinish`) puts the surviving row
    /// back on screen, so the user sees the clip return; this says why.
    private func reportDeletionFailure(_ outcome: ClipDeletionWorkflow.Outcome) {
        switch outcome {
        case .deleted:
            return
        case .partial, .failed:
            diagnostics.record(
                String(localized: "History"),
                String(localized: "Couldn’t delete every clip — the ones that remain were kept."))
        }
    }

    private func recordBoardFailure(_ message: String.LocalizationValue) {
        diagnostics.record(String(localized: "Boards"), String(localized: message))
    }

    func togglePin(_ item: ClipItem) {
        guard let fullStore else { return }
        Task {
            switch await curationController.togglePin(
                item, tier: tier, store: fullStore, engine: syncController.engine)
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
        guard let fullStore else { return }
        Task {
            switch await curationController.promoteToSnippet(
                item, tier: tier, store: fullStore)
            {
            case .promoted:
                toasts.show(GanchoToast(message: "Saved as snippet"))
                recordActivationMilestone(.firstSnippetCreated)
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
    /// changed and never rides a user interaction's critical path. Posting to
    /// the bus (rather than reconciling inline) lets a burst — e.g. a
    /// 50-clip batch delete — collapse into one reconcile.
    func refreshSpotlight(for change: StoreChange = .curation) {
        storeChanges.post(change)
    }

    func refreshBoards() async {
        guard let fullStore else { return }
        boards = (try? await fullStore.pinboards()) ?? []
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
        guard let fullStore else { return }
        Task {
            let outcome = await BoardsController().removeFromAllBoards(
                item, store: fullStore, engine: syncController.engine)
            guard outcome == .changed else {
                if outcome == .failed {
                    recordBoardFailure("Couldn’t remove the clip from its boards.")
                }
                return
            }
            await refreshRecents()
        }
    }

    /// Suggest the board this clip probably belongs to. The toggle, the
    /// sensitive-clip rule and the vote all live in the facade so iOS cannot
    /// answer this differently.
    func suggestedBoard(for item: ClipItem) async -> Pinboard? {
        await intelligenceFacade.suggestedBoard(
            for: item, store: fullStore, autoBoardEnabled: intelligence.autoBoard)
    }

    /// Creates a board and, when `assigning` is set, files that clip into it —
    /// the per-clip "Add to board → New board…" path expects the clip to land in
    /// the board it just named.
    @discardableResult
    func createBoard(
        named name: String, assigning item: ClipItem? = nil
    ) async -> BoardsController.BoardCreateOutcome {
        guard let fullStore else { return .failed }
        let outcome = await BoardsController().createBoard(
            name: name, filing: item, store: fullStore, engine: syncController.engine,
            isPro: tier == .pro,
            onFreeLimit: { self.paywallWindow.show(trigger: .freeLimitReached, model: self) },
            onAssigned: { self.toasts.show(GanchoToast(message: "Added to board")) })
        if outcome == .failed {
            recordBoardFailure("Couldn’t create the board.")
        } else if item != nil, case .created(_, filedClip: false) = outcome {
            recordBoardFailure("The board was created, but the clip couldn’t be added.")
        }
        guard outcome != .blocked else { return outcome }
        if case .created = outcome { recordActivationMilestone(.firstBoardCreated) }
        await refreshBoards()
        if case .created(let boardID, filedClip: true) = outcome {
            lastAssignedBoardID = boardID
        }
        if item != nil { await refreshRecents() }
        return outcome
    }

    /// Rename / delete are no-ops on the built-in Favorites board, so the UI
    /// only needs to hide the affordances.
    /// `async` so a caller can act on the result instead of guessing when the
    /// write lands. It used to kick its own `Task` and return immediately,
    /// which left views sleeping a fixed 140 ms and hoping — too long on a fast
    /// write, and simply wrong on a slow one.
    @discardableResult
    func renameBoard(_ board: Pinboard, name: String) async -> Bool {
        guard let fullStore else { return false }
        let outcome = await BoardsController().renameBoard(
            board, name: name, store: fullStore, engine: syncController.engine)
        if outcome == .failed {
            recordBoardFailure("Couldn’t rename the board.")
        }
        await refreshBoards()
        return outcome == .changed
    }

    @discardableResult
    func updateBoardIdentity(_ board: Pinboard, colorHex: String?, emoji: String?) async -> Bool {
        guard let fullStore else { return false }
        let outcome = await BoardsController().updateBoardIdentity(
            board, colorHex: colorHex, emoji: emoji, store: fullStore,
            engine: syncController.engine)
        if outcome == .failed {
            recordBoardFailure("Couldn’t update the board appearance.")
        }
        await refreshBoards()
        return outcome != .failed
    }

    /// `async` for the same reason as ``renameBoard(_:name:)``, and the return
    /// matters here: a view that moves the sidebar selection off a board should
    /// only do so once the board is actually gone.
    @discardableResult
    func deleteBoard(_ board: Pinboard) async -> Bool {
        guard let fullStore else { return false }
        let outcome = await BoardsController().deleteBoard(
            board, store: fullStore, engine: syncController.engine,
            syncEnabled: syncController.isEnabled)
        if outcome == .failed {
            recordBoardFailure("Couldn’t delete the board.")
        }
        await refreshBoards()
        await refreshRecents()
        return outcome == .changed
    }

    /// The boards a clip belongs to — drives the peek's board menu checkmarks.
    func boardMembership(for item: ClipItem) async -> Set<UUID> {
        guard let fullStore else { return [] }
        return (try? await fullStore.boardIDs(forClip: item.id)) ?? []
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
        guard let fullStore else { return false }
        guard !items.isEmpty else { return false }
        let succeeded = await BoardsController().setBoardMembership(
            items, board: board, member: member, store: fullStore,
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
                PanelTextSize.storageKey: panel.textSize.rawValue,
                "panel-content-width": String(describing: panel.preferredContentSize.width),
                "panel-content-height": String(describing: panel.preferredContentSize.height),
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
        if let raw = snapshot.appSettings[PanelTextSize.storageKey] {
            panel.textSize = PanelTextSize.resolved(raw)
        }
        if let widthRaw = snapshot.appSettings["panel-content-width"],
            let heightRaw = snapshot.appSettings["panel-content-height"],
            let width = Double(widthRaw), let height = Double(heightRaw)
        {
            panel.resizeContent(to: CGSize(width: width, height: height))
        }
    }

    // MARK: - Retention

    /// Starts the launch pass and the five-minute timer, returning the launch
    /// pass so a UI-test flow can wait for the run it triggered.
    ///
    /// - Parameter seed: a UI-test fixture the launch pass must see; the pass
    ///   waits for it before purging. Nil on every normal launch, which makes
    ///   the wait a no-op and leaves launch behavior unchanged.
    @discardableResult
    private func scheduleRetention(after seed: Task<Void, Never>? = nil) -> Task<Void, Never> {
        let launch = runRetention(after: seed)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
        return launch
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

    @discardableResult
    private func runRetention(after seed: Task<Void, Never>? = nil) -> Task<Void, Never> {
        let policy = retentionPolicy
        return Task {
            await seed?.value
            await runRetentionPass(policy: policy)
        }
    }

    /// One retention pass through the shared `RetentionPass`, refreshing the recent
    /// list only when the pass actually moved rows — an idle tick every five
    /// minutes has nothing to reload. The tier is read inside the pass, at the
    /// moment its limits are enforced.
    private func runRetentionPass(policy: RetentionPolicy) async {
        guard let grdbForEngines else { return }
        let changed = await RetentionPass(steps: .live(store: grdbForEngines, sync: syncController))
            .run(policy: policy, tier: { self.tier }, now: Date())
        if changed { await refreshRecents() }
    }
}
