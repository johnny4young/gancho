import Foundation
import Testing

@testable import GanchoKit

@Suite("Transport-neutral sync policy")
struct SyncPolicyTests {
    @Test(
        "Sync requires Pro, iCloud, and the transport entitlement",
        arguments: [
            (UserTier.pro, true, true, true),
            (.pro, false, true, false),
            (.pro, true, false, false),
            (.free, true, true, false),
            (.free, false, false, false)
        ])
    func enablementTruthTable(
        tier: UserTier,
        iCloudAvailable: Bool,
        hasEntitlement: Bool,
        expected: Bool
    ) {
        #expect(
            SyncEnablement.shouldEnable(
                tier: tier,
                iCloudAvailable: iCloudAvailable,
                hasCloudKitEntitlement: hasEntitlement) == expected)
    }

    @Test("Opaque sync state round-trips at the composition-root location")
    func fileStateStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-state-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let stateStore = SyncStateStore.file(at: url)
        let state = Data("opaque-state".utf8)

        #expect(stateStore.load() == nil)
        stateStore.save(state)

        #expect(stateStore.load() == state)
    }
}
