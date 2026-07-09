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

    nonisolated public var isPurchaseAvailable: Bool { true }

    public func availableProducts() async -> [ProProduct] { ProCatalog.all }

    /// The purchase itself happens on Lemon Squeezy's site; the user then pastes
    /// the key (`activate`). There is no in-app transaction to drive here.
    public func purchase(_ plan: ProProduct.Plan) async throws -> Bool { false }

    public func restorePurchases() async throws -> Bool { await currentTier() == .pro }

    public func currentTier() async -> UserTier {
        guard let token = store.load(), verifier.verify(token) != nil else { return .free }
        return .pro
    }

    /// Validates the key online once, stores the signed token, and reports the
    /// distinguishable outcome so the UI can guide the user. `activate(_:)` (the
    /// Bool convenience) is derived from this by the protocol default.
    public func activateResult(licenseKey: String) async -> LicenseActivationResult {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey(reason: "Empty key") }
        switch await activation.activate(licenseKey: trimmed, instanceName: instanceName) {
        case .activated(let signed):
            // Verify BEFORE persisting — never store a token that doesn't check
            // out against the embedded public key.
            guard verifier.verify(signed) != nil else {
                return .invalidKey(reason: "Signed token failed local verification")
            }
            // Persist, then confirm it reads back. A Keychain write can fail; if
            // it does, the entitlement wouldn't survive a relaunch (currentTier
            // reads from the store), so report it instead of a false success.
            do {
                try store.save(signed)
            } catch {
                return .storageUnavailable(reason: error.localizedDescription)
            }
            guard let stored = store.load(), verifier.verify(stored) != nil else {
                return .storageUnavailable(reason: "The license did not persist on this device")
            }
            return .activated
        case .rejected(let reason):
            return .invalidKey(reason: reason)
        case .unreachable(let reason):
            return .networkUnavailable(reason: reason)
        case .notLicensable:
            return .notLicensable
        }
    }
}
