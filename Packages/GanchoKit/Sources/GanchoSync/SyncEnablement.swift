import Foundation
import GanchoKit

/// When sync may run, and how to obtain an engine. Both app targets share
/// this so the rule lives in ONE place: sync is a Pro feature AND needs an
/// iCloud account. Free users and signed-out devices get a `NoopSyncEngine`
/// — the boundary is identical, so the rest of the app never branches.
public enum SyncEnablement {
    /// The production CloudKit container. Mirrors the app bundle id; the
    /// schema is promoted to production one-way at launch (see the mapper).
    public static let defaultContainerIdentifier = "iCloud.com.johnny4young.gancho"

    /// Sync is enabled only for Pro on a device with an iCloud account.
    /// Pure, so the truth table is unit-tested without touching CloudKit.
    public static func shouldEnable(tier: UserTier, iCloudAvailable: Bool) -> Bool {
        tier == .pro && iCloudAvailable
    }
}

/// Builds the engine the app drives through the `SyncEngine` boundary.
public enum SyncEngineFactory {
    /// Returns a live `CKSyncEngineAdapter` when sync is enabled, otherwise a
    /// `NoopSyncEngine`. Construction never touches CloudKit — the adapter
    /// creates its `CKSyncEngine` lazily on first `start()`/`enqueue` — so
    /// this is safe to call on every launch and tier change.
    public static func make(
        store: any SyncLocalStore,
        tier: UserTier,
        iCloudAvailable: Bool,
        containerIdentifier: String = SyncEnablement.defaultContainerIdentifier,
        stateStore: SyncStateStore,
        onStatus: (@Sendable (SyncStatus) -> Void)? = nil
    ) -> any SyncEngine {
        guard SyncEnablement.shouldEnable(tier: tier, iCloudAvailable: iCloudAvailable) else {
            return NoopSyncEngine()
        }
        return CKSyncEngineAdapter(
            store: store, containerIdentifier: containerIdentifier, stateStore: stateStore,
            onStatus: onStatus)
    }
}

/// Persistence for the opaque `CKSyncEngine` state blob (change tokens +
/// pending operations). Injected so `GanchoSync` never picks a storage
/// location: the Mac app keeps it in Application Support, iOS in the App
/// Group container.
public struct SyncStateStore: Sendable {
    public let load: @Sendable () -> Data?
    public let save: @Sendable (Data) -> Void

    public init(
        load: @escaping @Sendable () -> Data?, save: @escaping @Sendable (Data) -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// File-backed store at `url`; read/write failures degrade to "no saved
    /// state" rather than crashing (a lost token just forces a full refetch).
    public static func file(at url: URL) -> SyncStateStore {
        SyncStateStore(
            load: { try? Data(contentsOf: url) },
            save: { try? $0.write(to: url, options: .atomic) })
    }
}
