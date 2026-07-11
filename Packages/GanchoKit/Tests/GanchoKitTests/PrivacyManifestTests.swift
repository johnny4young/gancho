import Foundation
import Testing

/// Compliance gate: every app/extension target ships a privacy manifest
/// that matches the threat model — no tracking or tracking domains; only the
/// two app bundles may declare explicitly-consented product analytics.
@Suite("Privacy manifests — match the threat model")
struct PrivacyManifestTests {
    struct ManifestExpectation: Sendable {
        let path: String
        let collectsDiagnostics: Bool
    }

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let manifests = [
        ManifestExpectation(
            path: "Apps/GanchoMac/PrivacyInfo.xcprivacy", collectsDiagnostics: true),
        ManifestExpectation(
            path: "Apps/GanchoiOS/PrivacyInfo.xcprivacy", collectsDiagnostics: true),
        ManifestExpectation(
            path: "Apps/GanchoShare/PrivacyInfo.xcprivacy", collectsDiagnostics: false),
        ManifestExpectation(
            path: "Apps/GanchoWidgets/PrivacyInfo.xcprivacy", collectsDiagnostics: false),
        ManifestExpectation(
            path: "Apps/GanchoKeyboard/PrivacyInfo.xcprivacy", collectsDiagnostics: false)
    ]

    @Test(
        "Manifests declare analytics only for consenting app bundles",
        arguments: Self.manifests)
    func manifestHolds(expectation: ManifestExpectation) throws {
        let path = expectation.path
        let url = Self.repoRoot.appendingPathComponent(path)
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])

        #expect(plist["NSPrivacyTracking"] as? Bool == false, "\(path)")
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true, "\(path)")

        let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
        #expect(collected.count == (expectation.collectsDiagnostics ? 1 : 0), "\(path)")
        for entry in collected {
            #expect(
                entry["NSPrivacyCollectedDataType"] as? String
                    == "NSPrivacyCollectedDataTypeProductInteraction",
                "\(path)")
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == false, "\(path)")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(path)")
            #expect(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
                    == ["NSPrivacyCollectedDataTypePurposeAnalytics"],
                "\(path)")
        }
    }
}
