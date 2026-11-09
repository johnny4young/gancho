import Foundation

/// Portable settings document: everything
/// a reinstall needs, versioned, content-free by construction — preferences
/// only, never clips.
public struct SettingsSnapshot: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var retention: RetentionPolicy
    /// App-level extras (panel position, dock visibility…) as a flat string
    /// map so platform shells can round-trip their own keys without schema
    /// churn here.
    public var appSettings: [String: String]
    /// Capture preferences serialize through their own Codable.
    public var capturePreferencesJSON: Data

    public init(
        version: Int = SettingsSnapshot.currentVersion,
        retention: RetentionPolicy,
        capturePreferencesJSON: Data,
        appSettings: [String: String] = [:]
    ) {
        self.version = version
        self.retention = retention
        self.capturePreferencesJSON = capturePreferencesJSON
        self.appSettings = appSettings
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SettingsSnapshot {
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: data)
        guard snapshot.version == currentVersion else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Unsupported settings snapshot version \(snapshot.version)"))
        }
        return snapshot
    }
}
