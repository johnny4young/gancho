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
            "30-day history, 2,000 items", "Smart AI titles to try",
            "Full search and paste-back", "15 pins, 3 boards, 20 snippets",
            "Developer actions", "All privacy features",
        ],
        proPoints: [
            "Unlimited history, pins, and boards", "On-device AI titles and search",
            "iCloud sync (coming soon)",
        ])
}

/// Purchase seam. `StoreKitPurchaseHandler` is the native implementation;
/// a RevenueCat-backed one can slot in later for server-side validation —
/// both read the same StoreKit transactions, so the rest of the app never
/// changes.
public protocol PurchaseHandling: Sendable {
    /// Whether the device can make payments at all (parental controls, MDM).
    var isPurchaseAvailable: Bool { get }
    /// Plans to offer, richest first (annual is the visual default).
    func availableProducts() async -> [ProProduct]
    /// Buys a plan; returns whether it left the user entitled to Pro.
    func purchase(_ plan: ProProduct.Plan) async throws -> Bool
    /// Restores prior purchases (new device, reinstall); returns Pro state.
    func restorePurchases() async throws -> Bool
    /// The tier StoreKit currently entitles — the source of truth.
    func currentTier() async -> UserTier
    /// Activates a direct-download license key (Lemon Squeezy). StoreKit-only
    /// handlers ignore it and return false; the license handler stores and
    /// verifies the signed token, then reports whether it unlocked Pro.
    func activate(licenseKey: String) async -> Bool
}

extension PurchaseHandling {
    public func activate(licenseKey: String) async -> Bool { false }
}

/// Honest placeholder used where no real handler is wired (previews, tests).
public struct UnavailablePurchaseHandler: PurchaseHandling {
    public init() {}
    public var isPurchaseAvailable: Bool { false }
    public func availableProducts() async -> [ProProduct] { [] }
    public func purchase(_ plan: ProProduct.Plan) async throws -> Bool { false }
    public func restorePurchases() async throws -> Bool { false }
    public func currentTier() async -> UserTier { .free }
}
