import Foundation

/// The Pro product catalog — the SINGLE source of the StoreKit product IDs.
/// These exact identifiers must be mirrored in App Store Connect and in the
/// local `Gancho.storekit` test configuration. Pricing (decided 2026-06):
/// monthly $2.99 · annual $24.99 (default, 7-day trial) · lifetime $59.99;
/// Family Sharing on annual + lifetime.
public struct ProProduct: Sendable, Equatable, Identifiable {
    public enum Plan: String, Sendable, Equatable, CaseIterable, Codable {
        case annual
        case monthly
        case lifetime
    }

    public var id: String
    public var plan: Plan
    /// English display name; the live price comes from StoreKit at runtime.
    public var displayName: String

    public init(id: String, plan: Plan, displayName: String) {
        self.id = id
        self.plan = plan
        self.displayName = displayName
    }
}

public enum ProCatalog {
    public static let annual = ProProduct(
        id: "com.johnny4young.gancho.pro.annual", plan: .annual,
        displayName: "Gancho Pro (annual)")
    public static let monthly = ProProduct(
        id: "com.johnny4young.gancho.pro.monthly", plan: .monthly,
        displayName: "Gancho Pro (monthly)")
    public static let lifetime = ProProduct(
        id: "com.johnny4young.gancho.pro.lifetime", plan: .lifetime,
        displayName: "Gancho Pro (lifetime)")

    /// Display order: annual first (the visual default), then monthly, then
    /// lifetime.
    public static let all = [annual, monthly, lifetime]
    public static let ids = Set(all.map(\.id))

    public static func product(for plan: ProProduct.Plan) -> ProProduct {
        all.first { $0.plan == plan } ?? annual
    }
}

/// Pure entitlement rule, factored out so it is testable without StoreKit:
/// any active entitlement to a Pro product ⇒ `.pro`.
public enum StoreKitEntitlement {
    public static func tier(forEntitledProductIDs ids: Set<String>) -> UserTier {
        ids.isDisjoint(with: ProCatalog.ids) ? .free : .pro
    }
}
