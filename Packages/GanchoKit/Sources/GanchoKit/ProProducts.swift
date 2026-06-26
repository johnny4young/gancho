import Foundation

/// The Pro product catalog — the SINGLE source of the StoreKit product IDs.
/// These exact identifiers must be mirrored in App Store Connect and in the
/// local `Gancho.storekit` test configuration. Gancho Pro is one one-time,
/// family-shareable purchase (a non-consumable) — no subscriptions. Price: a
/// $19 launch price through 2026, rising to $25 afterwards. The real price
/// lives in App Store Connect; the value in the `.storekit` file is only for
/// local StoreKit testing.
public struct ProProduct: Sendable, Equatable, Identifiable {
    public enum Plan: String, Sendable, Equatable, CaseIterable, Codable {
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
    public static let lifetime = ProProduct(
        id: "com.johnny4young.gancho.pro.lifetime", plan: .lifetime,
        displayName: "Gancho Pro")

    public static let all = [lifetime]
    public static let ids = Set(all.map(\.id))

    public static func product(for plan: ProProduct.Plan) -> ProProduct {
        all.first { $0.plan == plan } ?? lifetime
    }
}

/// Pure entitlement rule, factored out so it is testable without StoreKit:
/// any active entitlement to a Pro product ⇒ `.pro`.
public enum StoreKitEntitlement {
    public static func tier(forEntitledProductIDs ids: Set<String>) -> UserTier {
        ids.isDisjoint(with: ProCatalog.ids) ? .free : .pro
    }
}
