import Foundation

/// The diagnostic file users attach to support emails. Content-free BY
/// SCHEMA: versions, settings snapshot (itself content-free, tested),
/// store statistics, and telemetry counters. There is no field a clip
/// could ride in — the threat-model release checklist depends on that.
public struct SupportBundle: Sendable, Codable {
    public var generatedAt: Date
    public var appVersion: String
    public var osVersion: String
    public var settings: SettingsSnapshot
    public var statistics: Statistics
    public var telemetryCounts: [String: Int]

    public struct Statistics: Sendable, Codable, Equatable {
        public var visibleClips: Int
        public var archivedClips: Int
        public var pinnedClips: Int
        public var pinboards: Int
        public var purgedLastWeek: Int

        public init(
            visibleClips: Int = 0, archivedClips: Int = 0, pinnedClips: Int = 0,
            pinboards: Int = 0, purgedLastWeek: Int = 0
        ) {
            self.visibleClips = visibleClips
            self.archivedClips = archivedClips
            self.pinnedClips = pinnedClips
            self.pinboards = pinboards
            self.purgedLastWeek = purgedLastWeek
        }
    }

    public init(
        generatedAt: Date = .now, appVersion: String, osVersion: String,
        settings: SettingsSnapshot, statistics: Statistics, telemetryCounts: [String: Int]
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.settings = settings
        self.statistics = statistics
        self.telemetryCounts = telemetryCounts
    }

    /// Gathers statistics from the store (counters only — no row data).
    public static func gatherStatistics(
        from store: GRDBClipboardStore
    ) async throws
        -> Statistics
    {
        Statistics(
            visibleClips: try await store.count(),
            archivedClips: try await store.archivedCount(),
            pinnedClips: try await store.pinnedCount(),
            pinboards: try await store.pinboards().count,
            purgedLastWeek: try await store.purgedItemCount(
                since: Date(timeIntervalSinceNow: -7 * 86_400)))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
