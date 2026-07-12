/// Pure policy for deciding whether a sync transport may run. The concrete
/// transport and platform capability probes are injected by the app shell.
public enum SyncEnablement {
    /// Sync is enabled only for Pro on a device with an iCloud account and the
    /// required transport entitlement. Pure so every truth-table row can run
    /// without importing or constructing CloudKit.
    public static func shouldEnable(
        tier: UserTier,
        iCloudAvailable: Bool,
        hasCloudKitEntitlement: Bool = true
    ) -> Bool {
        tier == .pro && iCloudAvailable && hasCloudKitEntitlement
    }
}
