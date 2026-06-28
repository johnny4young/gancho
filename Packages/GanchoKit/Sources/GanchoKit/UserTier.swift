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

    /// A free "taste" of on-device intelligence: the first N text clips a free
    /// user copies get a real AI title, so they see the magic on their OWN clips
    /// before deciding. Titles only — semantic search and OCR stay Pro.
    public static let freeAITitleTaste = 25

    /// How many taste titles remain given how many have been spent. Pure so the
    /// conversion gate stays unit-testable.
    public static func freeAITitlesRemaining(used: Int) -> Int {
        max(0, freeAITitleTaste - used)
    }

    /// How close a free user is to their boards/snippets ceilings. Drives the
    /// Library's footer nudge so the upsell FOREWARNS (a count that's almost
    /// full, then the wall) instead of ambushing them at the limit. Pure so the
    /// thresholds stay unit-testable.
    public enum Pressure: Sendable, Equatable {
        /// Plenty of room — the neutral "Pro goes unlimited" footer.
        case comfortable
        /// One slot left on either axis — a soft "almost full" warning.
        case almostFull
        /// A ceiling is hit — the next create opens the paywall.
        case reached
    }

    public static func pressure(
        boardsUsed: Int, snippetsUsed: Int, isPro: Bool
    ) -> Pressure {
        guard !isPro else { return .comfortable }
        let boardsLeft = PinLimits.freeMaxPinboards - boardsUsed
        let snippetsLeft = SnippetLimits.freeMaxSnippets - snippetsUsed
        let left = min(boardsLeft, snippetsLeft)
        if left <= 0 { return .reached }
        if left == 1 { return .almostFull }
        return .comfortable
    }
}
