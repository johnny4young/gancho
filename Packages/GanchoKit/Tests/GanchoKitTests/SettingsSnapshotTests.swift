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

    @Test("An unsupported settings version cannot be imported", arguments: [-1, 0, 2, Int.max])
    func rejectsUnsupportedVersions(_ version: Int) throws {
        let snapshot = SettingsSnapshot(
            version: version,
            retention: RetentionPolicy(global: .day),
            capturePreferencesJSON: Data(#"{"captureImages":false}"#.utf8),
            appSettings: ["panel-position": "atCursor"])
        let data = try snapshot.encoded()

        #expect(throws: (any Error).self) {
            try SettingsSnapshot.decode(data)
        }
    }
}
