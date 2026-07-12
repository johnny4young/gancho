import Foundation
import GanchoKit

#if os(macOS)
    import Security
#endif

/// Runtime entitlement probe for the current binary. This is intentionally
/// separate from `CKContainer`: reading code-signing entitlements is safe in
/// unsigned test builds, while constructing a CloudKit container can trap if
/// the process lacks the required container/service entitlements.
public enum CloudKitEntitlements {
    /// The production CloudKit container. Mirrors the app bundle identifier.
    public static let defaultContainerIdentifier = "iCloud.com.johnny4young.gancho"

    private static let containerKey = "com.apple.developer.icloud-container-identifiers"
    private static let servicesKey = "com.apple.developer.icloud-services"

    /// Returns whether the current process is signed for Gancho's CloudKit
    /// private database. Used before creating `CKContainer`.
    public static func currentTaskAllowsSync(
        containerIdentifier: String = defaultContainerIdentifier
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
        containerIdentifier: String = CloudKitEntitlements.defaultContainerIdentifier,
        stateStore: SyncStateStore,
        onStatus: (@Sendable (SyncStatus) -> Void)? = nil,
        diagnostics: DiagnosticLog? = nil,
        pollStateStore: SyncStateStore? = nil
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
            onStatus: onStatus, diagnostics: diagnostics, pollStateStore: pollStateStore)
    }
}
