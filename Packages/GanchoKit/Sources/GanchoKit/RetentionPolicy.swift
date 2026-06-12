import Foundation

/// How long history lives. Three layers, most specific wins:
/// per-item `expiresAt` → sensitive lifetime → per-kind window → global
/// window. Pins are exempt from ALL of them.
public struct RetentionPolicy: Sendable, Equatable, Codable {
    public enum Window: String, Sendable, Equatable, Codable, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"
        case quarter = "90d"
        case never

        /// Seconds of life, nil = unlimited.
        public var lifetime: TimeInterval? {
            switch self {
            case .day: 86_400
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            case .quarter: 90 * 86_400
            case .never: nil
            }
        }
    }

    public var global: Window
    /// Per-kind overrides (e.g. images 7d while text keeps 90d) — the
    /// differentiator nobody in the market ships natively.
    public var perKind: [ClipContentKind: Window]
    /// Sensitive items self-destruct after this many seconds (default 10
    /// minutes, configurable).
    public var sensitiveLifetime: TimeInterval

    public init(
        global: Window = .month,
        perKind: [ClipContentKind: Window] = [:],
        sensitiveLifetime: TimeInterval = 600
    ) {
        self.global = global
        self.perKind = perKind
        self.sensitiveLifetime = sensitiveLifetime
    }

    /// Oldest allowed creation date for a kind (nil = keep forever).
    public func cutoff(for kind: ClipContentKind, now: Date) -> Date? {
        let window = perKind[kind] ?? global
        guard let lifetime = window.lifetime else { return nil }
        return now.addingTimeInterval(-lifetime)
    }

    private static let defaultsKey = "retention-policy"

    public static func load(from defaults: UserDefaults) -> RetentionPolicy {
        guard let data = defaults.data(forKey: defaultsKey),
            let policy = try? JSONDecoder().decode(RetentionPolicy.self, from: data)
        else { return RetentionPolicy() }
        return policy
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// What one purge run removed — persisted to the purge log so the Privacy
/// Center can show "X items cleaned up" without ever knowing what they were.
public struct PurgeSummary: Sendable, Equatable, Codable {
    public var expiredByOwnDate: Int
    public var sensitiveExpired: Int
    public var byKindWindow: Int
    public var byGlobalWindow: Int
    public var orphanedBlobsRemoved: Int

    public var totalRowsPurged: Int {
        expiredByOwnDate + sensitiveExpired + byKindWindow + byGlobalWindow
    }

    public init(
        expiredByOwnDate: Int = 0, sensitiveExpired: Int = 0,
        byKindWindow: Int = 0, byGlobalWindow: Int = 0, orphanedBlobsRemoved: Int = 0
    ) {
        self.expiredByOwnDate = expiredByOwnDate
        self.sensitiveExpired = sensitiveExpired
        self.byKindWindow = byKindWindow
        self.byGlobalWindow = byGlobalWindow
        self.orphanedBlobsRemoved = orphanedBlobsRemoved
    }
}
