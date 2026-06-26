import Testing

@testable import GanchoKit

@Suite("Pro catalog + entitlement rule")
struct ProProductsTests {
    @Test("Catalog is the single one-time lifetime product")
    func catalog() {
        #expect(ProCatalog.all.map(\.plan) == [.lifetime])
        #expect(ProCatalog.lifetime.id == "com.johnny4young.gancho.pro.lifetime")
        #expect(ProCatalog.ids.count == 1)
        #expect(ProCatalog.product(for: .lifetime).id == ProCatalog.lifetime.id)
    }

    @Test("Any Pro entitlement means Pro; nothing else means Free")
    func entitlementRule() {
        #expect(StoreKitEntitlement.tier(forEntitledProductIDs: []) == .free)
        #expect(
            StoreKitEntitlement.tier(forEntitledProductIDs: ["com.example.other"]) == .free)
        #expect(
            StoreKitEntitlement.tier(
                forEntitledProductIDs: [ProCatalog.lifetime.id]) == .pro)
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
        let purchased = try await handler.purchase(.lifetime)
        #expect(purchased == false)
    }
}
