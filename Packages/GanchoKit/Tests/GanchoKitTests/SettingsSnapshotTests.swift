import Foundation
import Testing

@testable import GanchoKit

@Suite("Settings portability")
struct SettingsSnapshotTests {
    @Test("Snapshot round-trips retention, prefs payload, and app extras")
    func roundTrip() throws {
        let retention = RetentionPolicy(
            global: .week, perKind: [.image: .day], sensitiveLifetime: 300)
        let snapshot = SettingsSnapshot(
            retention: retention,
            capturePreferencesJSON: Data(#"{"captureImages":false}"#.utf8),
            appSettings: ["panel-position": "atCursor", "show-in-dock": "true"])

        let decoded = try SettingsSnapshot.decode(try snapshot.encoded())
        #expect(decoded == snapshot)
        #expect(decoded.version == 1)
    }

    @Test("Snapshots never carry clip content fields")
    func contentFree() throws {
        let snapshot = SettingsSnapshot(
            retention: RetentionPolicy(), capturePreferencesJSON: Data())
        let object = try JSONSerialization.jsonObject(with: snapshot.encoded())
        let keys = (object as? [String: Any])?.keys.sorted() ?? []
        #expect(keys == ["appSettings", "capturePreferencesJSON", "retention", "version"])
    }
}
