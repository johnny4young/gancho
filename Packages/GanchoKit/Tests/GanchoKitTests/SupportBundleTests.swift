import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Support bundle — counters only")
struct SupportBundleTests {
    @Test("Statistics gather counters and the schema carries no content field")
    func gatherAndSchema() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("support-\(UUID().uuidString)")))
        try store.migrate()
        try await store.insert(
            ClipItem(preview: "secret-ish body", contentHash: "h", isPinned: true),
            content: .text("the actual clipboard content"))

        let stats = try await SupportBundle.gatherStatistics(from: store)
        #expect(stats.visibleClips == 1)
        #expect(stats.pinnedClips == 1)

        let bundle = SupportBundle(
            appVersion: "0.1.0", osVersion: "26.5",
            settings: SettingsSnapshot(
                retention: RetentionPolicy(), capturePreferencesJSON: Data()),
            statistics: stats, telemetryCounts: ["app_launched": 3])
        let json = try #require(String(bytes: try bundle.encoded(), encoding: .utf8))

        #expect(!json.contains("the actual clipboard content"))
        #expect(!json.contains("secret-ish body"))
        #expect(json.contains("\"visibleClips\" : 1"))
    }
}
