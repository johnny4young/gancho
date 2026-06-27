import Foundation

/// The entitlement the rest of the app consults. Purchases (StoreKit /
/// RevenueCat) later SET this; nothing else about enforcement changes —
/// that separation is what makes IAP a drop-in.
public enum UserTier: String, Sendable, Equatable, Codable {
    case free
    case pro

    private static let defaultsKey = "user-tier"

    public static func load(from defaults: UserDefaults) -> UserTier {
        UserTier(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .free
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Free-plan ceilings. Deliberately generous (the distribution engine):
/// everything works — history depth and pin counts are the gates.
public enum FreeTierLimits {
    public static let historyDays: TimeInterval = 30 * 86_400
    public static let historyItems = 2_000
    /// Pin/board ceilings live in `PinLimits`; snippet ceilings arrive with
    /// the library table.
}
