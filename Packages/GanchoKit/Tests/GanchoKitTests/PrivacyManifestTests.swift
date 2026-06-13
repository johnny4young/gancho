import Foundation
import Testing

/// Compliance gate: every app/extension target ships a privacy manifest
/// that matches the threat model — no tracking, no tracking domains, only
/// unlinked product-interaction analytics.
@Suite("Privacy manifests — match the threat model")
struct PrivacyManifestTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let manifests = [
        "Apps/GanchoMac/PrivacyInfo.xcprivacy",
        "Apps/GanchoiOS/PrivacyInfo.xcprivacy",
        "Apps/GanchoShare/PrivacyInfo.xcprivacy",
    ]

    @Test(
        "Manifests exist, declare no tracking, and collect buckets only",
        arguments: Self.manifests)
    func manifestHolds(path: String) throws {
        let url = Self.repoRoot.appendingPathComponent(path)
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])

        #expect(plist["NSPrivacyTracking"] as? Bool == false, "\(path)")
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true, "\(path)")

        let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
        for entry in collected {
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == false, "\(path)")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(path)")
        }
    }
}
