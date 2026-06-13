import Testing

@testable import GanchoKit

@Suite("Pro catalog + entitlement rule")
struct ProProductsTests {
    @Test("Catalog IDs are the agreed bundle-scoped identifiers, annual first")
    func catalog() {
        #expect(ProCatalog.all.map(\.plan) == [.annual, .monthly, .lifetime])
        #expect(ProCatalog.annual.id == "com.johnny4young.gancho.pro.annual")
        #expect(ProCatalog.monthly.id == "com.johnny4young.gancho.pro.monthly")
        #expect(ProCatalog.lifetime.id == "com.johnny4young.gancho.pro.lifetime")
        #expect(ProCatalog.ids.count == 3)
        #expect(ProCatalog.product(for: .lifetime).id == ProCatalog.lifetime.id)
    }

    @Test("Any Pro entitlement means Pro; nothing else means Free")
    func entitlementRule() {
        #expect(StoreKitEntitlement.tier(forEntitledProductIDs: []) == .free)
        #expect(
            StoreKitEntitlement.tier(forEntitledProductIDs: ["com.example.other"]) == .free)
        #expect(
            StoreKitEntitlement.tier(
                forEntitledProductIDs: [ProCatalog.monthly.id]) == .pro)
        #expect(
            StoreKitEntitlement.tier(
                forEntitledProductIDs: [ProCatalog.lifetime.id, "com.example.other"]) == .pro)
    }

    @Test("The unavailable handler reports free and offers nothing")
    func unavailableHandler() async throws {
        let handler = UnavailablePurchaseHandler()
        #expect(handler.isPurchaseAvailable == false)
        #expect(await handler.availableProducts().isEmpty)
        #expect(await handler.currentTier() == .free)
        let purchased = try await handler.purchase(.annual)
        #expect(purchased == false)
    }
}
