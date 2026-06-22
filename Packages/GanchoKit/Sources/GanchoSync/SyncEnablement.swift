import Foundation
import GanchoKit

#if os(macOS)
    import Security
#endif

/// When sync may run, and how to obtain an engine. Both app targets share
/// this so the rule lives in ONE place: sync is a Pro feature AND needs an
/// iCloud account. Free users and signed-out devices get a `NoopSyncEngine`
/// — the boundary is identical, so the rest of the app never branches.
public enum SyncEnablement {
    /// The production CloudKit container. Mirrors the app bundle id; the
    /// schema is promoted to production one-way at launch (see the mapper).
    public static let defaultContainerIdentifier = "iCloud.com.johnny4young.gancho"

    /// Sync is enabled only for Pro on a device with an iCloud account and
    /// CloudKit entitlements. The entitlement check is as important as the
    /// account check: unsigned UI-test/debug builds can have an iCloud token
    /// but still trap when CloudKit is touched.
    /// Pure, so the truth table is unit-tested without touching CloudKit.
    public static func shouldEnable(
        tier: UserTier,
        iCloudAvailable: Bool,
        hasCloudKitEntitlement: Bool = true
    ) -> Bool {
        tier == .pro && iCloudAvailable && hasCloudKitEntitlement
    }
}

/// Runtime entitlement probe for the current binary. This is intentionally
/// separate from `CKContainer`: reading code-signing entitlements is safe in
/// unsigned test builds, while constructing a CloudKit container can trap if
/// the process lacks the required container/service entitlements.
public enum CloudKitEntitlements {
    private static let containerKey = "com.apple.developer.icloud-container-identifiers"
    private static let servicesKey = "com.apple.developer.icloud-services"

    /// Returns whether the current process is signed for Gancho's CloudKit
    /// private database. Used before creating `CKContainer`.
    public static func currentTaskAllowsSync(
        containerIdentifier: String = SyncEnablement.defaultContainerIdentifier
    ) -> Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil) else { return false }
            let containers = SecTaskCopyValueForEntitlement(task, containerKey as CFString, nil)
            let services = SecTaskCopyValueForEntitlement(task, servicesKey as CFString, nil)
            return contains(containers, containerIdentifier) && contains(services, "CloudKit")
        #else
            // iOS binaries are always code-signed to run on device, and this
            // package's iOS build gate compiles without runtime entitlements.
            // Keep the pure enablement rule injectable for tests; the runtime
            // probe is macOS-only because `SecTask` is unavailable on iOS.
            return true
        #endif
    }

    static func contains(_ entitlement: CFTypeRef?, _ expected: String) -> Bool {
        guard let entitlement else { return false }
        if let value = entitlement as? String {
            return value == expected
        }
        if let values = entitlement as? [String] {
            return values.contains(expected)
        }
        if let values = entitlement as? Set<String> {
            return values.contains(expected)
        }
        if let values = entitlement as? NSArray {
            return values.compactMap { $0 as? String }.contains(expected)
        }
        return false
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
        hasCloudKitEntitlement: Bool = true,
        containerIdentifier: String = SyncEnablement.defaultContainerIdentifier,
        stateStore: SyncStateStore,
        onStatus: (@Sendable (SyncStatus) -> Void)? = nil
    ) -> any SyncEngine {
        guard
            SyncEnablement.shouldEnable(
                tier: tier, iCloudAvailable: iCloudAvailable,
                hasCloudKitEntitlement: hasCloudKitEntitlement)
        else {
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
