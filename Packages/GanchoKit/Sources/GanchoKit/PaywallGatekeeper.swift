import Foundation

/// When the paywall may appear. The product rule, enforced in one place:
/// contextual triggers fire ONLY after the user's first successful
/// paste-back (value before paywall, same day — the trial-start window);
/// the Settings Pro section is user-initiated navigation and always allowed.
public enum PaywallGatekeeper {
    public enum Trigger: String, Sendable, Codable, CaseIterable {
        case freeLimitReached
        case proFeatureTouched
        case settingsPro
    }

    public static func shouldShow(
        trigger: Trigger, tier: UserTier, hasPastedBackOnce: Bool
    ) -> Bool {
        guard tier == .free else { return false }
        switch trigger {
        case .settingsPro:
            return true
        case .freeLimitReached, .proFeatureTouched:
            return hasPastedBackOnce
        }
    }
}

/// Paywall copy as data: defaults ship in the binary; a remote JSON override
/// later swaps order/copy without an app update (A/B-ready by format, the
/// remote channel itself is a launch-infrastructure concern).
public struct PaywallCopy: Sendable, Equatable, Codable {
    public var headline: String
    public var freeForeverPoints: [String]
    public var proPoints: [String]

    public init(headline: String, freeForeverPoints: [String], proPoints: [String]) {
        self.headline = headline
        self.freeForeverPoints = freeForeverPoints
        self.proPoints = proPoints
    }

    public static let standard = PaywallCopy(
        headline: "Gancho is free forever. Pro goes further.",
        freeForeverPoints: [
            "7-day history, 500 items", "Full search and paste-back",
            "Developer actions", "All privacy features",
        ],
        proPoints: [
            "Unlimited history and pins", "iCloud sync across your devices",
            "On-device AI titles and search",
        ])
}

/// Purchase seam: StoreKit/RevenueCat implement this when accounts exist.
public protocol PurchaseHandling: Sendable {
    var isPurchaseAvailable: Bool { get }
    func purchasePro() async throws
}

/// Honest placeholder until the IAP infrastructure lands.
public struct UnavailablePurchaseHandler: PurchaseHandling {
    public init() {}
    public var isPurchaseAvailable: Bool { false }
    public func purchasePro() async throws {}
}
