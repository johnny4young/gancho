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
            "1-year history, 10,000 items", "Smart AI titles to try",
            "Full search and paste-back", "15 pins, 3 boards, 20 snippets",
            "Developer actions", "All privacy features",
        ],
        proPoints: [
            "Unlimited history, pins, and boards", "On-device AI titles and search",
            "Encrypted iCloud sync",
        ])
}

/// The distinguishable outcomes of a direct-download license activation, so the
/// UI can tell the user *why* a key didn't take — a wrong or used-up key, a
/// network problem, or a build that can't license at all — instead of one flat
/// "couldn't activate". `reason` carries the upstream detail for diagnostics;
/// the UI maps the *case* (not the raw reason) to a localized message.
public enum LicenseActivationResult: Sendable, Equatable {
    case activated
    case invalidKey(reason: String)
    case networkUnavailable(reason: String)
    /// The key validated, but the signed token couldn't be persisted on this
    /// device (e.g. a Keychain write failure) — so the entitlement wouldn't
    /// survive a relaunch. Its own case so the UI never claims Pro while
    /// `currentTier()` would still read `.free`.
    case storageUnavailable(reason: String)
    case notLicensable
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
    /// Activates a direct-download license key (Lemon Squeezy) and reports the
    /// distinguishable outcome. StoreKit-only handlers can't activate keys and
    /// report `.notLicensable`; the license handler stores and verifies the
    /// signed token, then reports `.activated` or why it failed.
    func activateResult(licenseKey: String) async -> LicenseActivationResult
    /// Convenience: whether activation unlocked Pro. Derived from
    /// `activateResult` by default — implementors override the result, not this.
    func activate(licenseKey: String) async -> Bool
}

extension PurchaseHandling {
    public func activateResult(licenseKey: String) async -> LicenseActivationResult {
        .notLicensable
    }

    public func activate(licenseKey: String) async -> Bool {
        if case .activated = await activateResult(licenseKey: licenseKey) { return true }
        return false
    }
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
