import Foundation
import GanchoKit
import GanchoSync

/// Owns the iCloud sync engine LIFECYCLE for both app shells: the live
/// `SyncEngine` instance, the cached enablement flag, and the make/start/stop/
/// reset plumbing that used to be duplicated in `AppModel.configureSync` and
/// `IOSAppModel.configureSync`. The shells keep their own `@Observable` sync
/// STATUS state (`syncStatus`) and its UI mapping — this controller never
/// touches SwiftUI — and receive engine transitions through the injected
/// callbacks, so no view changes are needed.
///
/// The two shells had diverged only in platform-mechanical ways, all captured
/// as constructor dependencies so this is a behavior-preserving extraction, not
/// a merge:
/// - the state-file location (`stateStoreURL`): Application Support on macOS,
///   the App Group container on iOS;
/// - the store handle (`store`): the concrete GRDB store on macOS, the same
///   store downcast to `SyncLocalStore` on iOS — both `any SyncLocalStore`, and
///   both nil on the in-memory fallback (sync then stays a no-op);
/// - the status/idle mapping, which each shell wires to its own `syncStatus`.
///
/// Explicitly `@MainActor`: SwiftPM targets do not default to main-actor
/// isolation the way the app targets do, and every mutation here (the engine
/// swap, the enabled flag) races the UI otherwise.
@MainActor
public final class SyncController {
    /// The live engine the shells drive (`enqueue`/`enqueueDeletion`/…). A
    /// `NoopSyncEngine` until `configure(tier:)` arms the real adapter, and back
    /// to a `NoopSyncEngine` when enablement drops.
    public private(set) var engine: any SyncEngine = NoopSyncEngine()

    /// The cached enablement decision, read wherever a shell used to consult its
    /// `syncEnabled` flag to choose a sync-aware write (tombstone vs plain
    /// delete, whether to sweep pending deletions). Only `configure(tier:)`
    /// changes it, so it stays stable between reconfigurations exactly as the
    /// stored flag did.
    public var isEnabled: Bool { enabled }
    private var enabled = false

    /// nil on the in-memory fallback (no durable, sync-capable store), in which
    /// case `configure(tier:)` is a complete no-op — mirroring both shells'
    /// `guard let …` at the top of `configureSync`.
    private let store: (any SyncLocalStore)?
    private let stateStoreURL: URL
    private let iCloudAvailable: @Sendable () -> Bool
    private let hasCloudKitEntitlement: @Sendable () -> Bool
    private let makeEngine: EngineFactory

    /// Maps an engine status to the shell's UI (macOS `applySyncStatus`; iOS its
    /// inline mapping). Runs on the main actor: the make() closure hops through
    /// `Task { @MainActor in … }` exactly as the inlined code did. Set by the
    /// shell before the first `configure(tier:)` (Swift init ordering forbids a
    /// self-capturing closure in the shell's own stored-property init).
    public var onStatus: (@MainActor (SyncStatus) async -> Void)?

    /// The disable transition's raw `syncStatus = .idle`. Kept separate from
    /// `onStatus` on purpose: both shells' disable branch assigns `.idle`
    /// DIRECTLY, bypassing the status mapping's side effects (privacy events,
    /// refresh-on-settle) — routing it through `onStatus` would change behavior.
    public var onIdle: (@MainActor () -> Void)?

    /// Content-free sync-trouble sink handed to the live adapter, so fetch/apply
    /// failures surface in the shells' "Recent issues" log instead of vanishing.
    /// Set by the shell before the first `configure(tier:)`, like `onStatus`
    /// (Swift init ordering forbids referencing the shell's own stored log in
    /// its stored-property init).
    public var diagnostics: DiagnosticLog?

    /// Builds the engine `configure(tier:)` installs. Injected so tests can
    /// substitute a fake engine; the default is the production factory, so the
    /// live behavior is unchanged.
    public typealias EngineFactory =
        @MainActor (
            _ store: any SyncLocalStore,
            _ tier: UserTier,
            _ iCloudAvailable: Bool,
            _ hasCloudKitEntitlement: Bool,
            _ stateStore: SyncStateStore,
            _ onStatus: @escaping @Sendable (SyncStatus) -> Void,
            _ diagnostics: DiagnosticLog?
        ) -> any SyncEngine

    public init(
        store: (any SyncLocalStore)?,
        stateStoreURL: URL,
        iCloudAvailable: @escaping @Sendable () -> Bool = {
            FileManager.default.ubiquityIdentityToken != nil
        },
        hasCloudKitEntitlement: @escaping @Sendable () -> Bool = {
            CloudKitEntitlements.currentTaskAllowsSync()
        },
        onStatus: (@MainActor (SyncStatus) async -> Void)? = nil,
        onIdle: (@MainActor () -> Void)? = nil,
        makeEngine: @escaping EngineFactory = {
            store, tier, iCloud, entitled, state, onStatus, diagnostics in
            SyncEngineFactory.make(
                store: store, tier: tier, iCloudAvailable: iCloud,
                hasCloudKitEntitlement: entitled, stateStore: state, onStatus: onStatus,
                diagnostics: diagnostics)
        }
    ) {
        self.store = store
        self.stateStoreURL = stateStoreURL
        self.iCloudAvailable = iCloudAvailable
        self.hasCloudKitEntitlement = hasCloudKitEntitlement
        self.onStatus = onStatus
        self.onIdle = onIdle
        self.makeEngine = makeEngine
    }

    /// Arms or disarms sync to match the current tier + account, rebuilding only
    /// when the enablement decision flips — safe to call on launch and on every
    /// tier/account change. Mirrors both shells' `configureSync` body exactly.
    public func configure(tier: UserTier) {
        guard let store else { return }
        let enable = SyncEnablement.shouldEnable(
            tier: tier,
            iCloudAvailable: iCloudAvailable(),
            hasCloudKitEntitlement: hasCloudKitEntitlement())
        guard enable != enabled else { return }
        enabled = enable

        let previous = engine
        Task { await previous.stop() }
        engine = makeEngine(
            store, tier, iCloudAvailable(), hasCloudKitEntitlement(),
            .file(at: stateStoreURL),
            { [weak self] status in
                Task { @MainActor in await self?.onStatus?(status) }
            }, diagnostics)
        if enable {
            let engine = engine
            Task { try? await engine.start() }
        } else {
            onIdle?()
        }
    }

    /// Pull the latest from iCloud (and push pending) RIGHT NOW. The engine is
    /// push-driven on its own (`CKSyncEngine` auto-fetches when CloudKit
    /// notifies it of remote changes); the shells call this when a surface
    /// comes forward as a latency belt-and-braces — instant freshness, and
    /// catch-up for pushes missed while asleep. A no-op when sync is off.
    public func syncNow() {
        guard enabled else { return }
        let engine = engine
        Task { try? await engine.start() }
    }

    /// User-triggered sync cycle (macOS "Force sync"; iOS pull-to-refresh).
    /// Awaits the cycle's kickoff so the iOS shell can chain its `refreshHints`
    /// after it, exactly as before; the macOS shell wraps it in a fire-and-forget
    /// `Task` to keep its synchronous call site.
    public func forceSync() async {
        let engine = engine
        try? await engine.start()
    }

    /// Drop the persisted engine state and re-arm from scratch (the "reset &
    /// re-pull" affordance). Mirrors both shells' `resetSyncAndRepull`: remove
    /// the state file, force the enabled flag down, and reconfigure — so the
    /// flip rebuilds the engine over a fresh state file.
    public func reset(tier: UserTier) {
        try? FileManager.default.removeItem(at: stateStoreURL)
        enabled = false
        configure(tier: tier)
    }
}
