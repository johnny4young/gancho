import Foundation

/// `PurchaseHandling` for the direct-download channel: Pro comes from a
/// locally-stored, Ed25519-signed Lemon Squeezy license token, verified
/// offline against the embedded public key. This handler is wired only in the
/// `GANCHO_DIRECT_DOWNLOAD` build; the App Store build uses
/// `StoreKitPurchaseHandler`.
@MainActor
public final class LicenseKeyPurchaseHandler: PurchaseHandling {
    private let store: any LicenseTokenStore
    private let verifier: LicenseVerifier
    private let activation: LicenseActivationService
    private let instanceName: String

    public init(
        store: any LicenseTokenStore,
        verifier: LicenseVerifier = .embedded,
        activation: LicenseActivationService,
        instanceName: String
    ) {
        self.store = store
        self.verifier = verifier
        self.activation = activation
        self.instanceName = instanceName
    }

    public nonisolated var isPurchaseAvailable: Bool { true }

    public func availableProducts() async -> [ProProduct] { ProCatalog.all }

    /// The purchase itself happens on Lemon Squeezy's site; the user then pastes
    /// the key (`activate`). There is no in-app transaction to drive here.
    public func purchase(_ plan: ProProduct.Plan) async throws -> Bool { false }

    public func restorePurchases() async throws -> Bool { await currentTier() == .pro }

    public func currentTier() async -> UserTier {
        guard let token = store.load(), verifier.verify(token) != nil else { return .free }
        return .pro
    }

    public func activate(licenseKey: String) async -> Bool {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard
            case .activated(let signed) = await activation.activate(
                licenseKey: trimmed, instanceName: instanceName)
        else { return false }
        try? store.save(signed)
        return verifier.verify(signed) != nil
    }
}
