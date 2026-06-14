import Foundation
import StoreKit

/// Native StoreKit 2 purchase handler — no third-party SDK. Loads products
/// by the `ProCatalog` IDs, drives the purchase/restore flow, and treats
/// `Transaction.currentEntitlements` as the authoritative source of the
/// user's tier. A RevenueCat-backed `PurchaseHandling` can be added later
/// for server-side validation/analytics; it would read these same
/// transactions, so nothing else in the app would change.
///
/// Testable locally with zero account via the `Gancho.storekit`
/// configuration (Scheme → Run → StoreKit Configuration). With neither a
/// config nor a real App Store account, entitlements come back empty and
/// the tier stays `.free` — the correct default.
@MainActor
public final class StoreKitPurchaseHandler: PurchaseHandling {
    /// Called whenever entitlements change (purchase, restore, or an
    /// out-of-process renewal/refund picked up by the listener).
    public var onTierChange: ((UserTier) -> Void)?

    private var updatesListener: Task<Void, Never>?

    public init() {
        // Catch transactions that happen outside an explicit purchase call:
        // renewals, Ask-to-Buy approvals, refunds, cross-device buys.
        updatesListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.notifyTierChange()
                }
            }
        }
    }

    deinit {
        updatesListener?.cancel()
    }

    public nonisolated var isPurchaseAvailable: Bool {
        AppStore.canMakePayments
    }

    public func availableProducts() async -> [ProProduct] {
        // The catalog defines what we offer; live prices are read from the
        // StoreKit `Product` objects in the UI layer when needed.
        ProCatalog.all
    }

    public func purchase(_ plan: ProProduct.Plan) async throws -> Bool {
        let productID = ProCatalog.product(for: plan).id
        guard let product = try await Product.products(for: [productID]).first else {
            return false
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            // The just-verified transaction is itself the proof of purchase.
            // Derive the tier from it directly rather than re-reading
            // `currentEntitlements`, which is eventually-consistent and can
            // momentarily return empty right after a purchase (notably under
            // Xcode StoreKit testing). Launch and restore still scan all
            // entitlements via `currentTier()`.
            let purchasedTier = StoreKitEntitlement.tier(
                forEntitledProductIDs: [transaction.productID])
            onTierChange?(purchasedTier)
            return purchasedTier == .pro
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    public func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        await notifyTierChange()
        return await currentTier() == .pro
    }

    public func currentTier() async -> UserTier {
        var entitledIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                entitledIDs.insert(transaction.productID)
            }
        }
        return StoreKitEntitlement.tier(forEntitledProductIDs: entitledIDs)
    }

    private func notifyTierChange() async {
        let tier = await currentTier()
        onTierChange?(tier)
    }
}
