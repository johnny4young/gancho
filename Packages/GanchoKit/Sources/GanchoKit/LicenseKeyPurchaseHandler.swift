import Foundation

/// `PurchaseHandling` for the direct-download channel: Pro comes from a Lemon
/// Squeezy license the user activates once, recorded in the Keychain and
/// re-confirmed with Lemon Squeezy on a schedule. Lemon Squeezy is the
/// authority — this build mints nothing and carries no signing key, so there is
/// no secret in it to extract. This handler is wired only in the
/// `GANCHO_DIRECT_DOWNLOAD` build; the App Store build uses
/// `StoreKitPurchaseHandler`.
@MainActor
public final class LicenseKeyPurchaseHandler: PurchaseHandling {
    private let store: any LicenseTokenStore
    private let activation: LicenseActivationService
    private let instanceName: String
    private let now: @Sendable () -> Date

    public init(
        store: any LicenseTokenStore,
        activation: LicenseActivationService,
        instanceName: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.activation = activation
        self.instanceName = instanceName
        self.now = now
    }

    nonisolated public var isPurchaseAvailable: Bool { true }

    public func availableProducts() async -> [ProProduct] { ProCatalog.all }

    /// The purchase itself happens on Lemon Squeezy's site; the user then pastes
    /// the key (`activate`). There is no in-app transaction to drive here.
    public func purchase(_ plan: ProProduct.Plan) async throws -> Bool { false }

    public func restorePurchases() async throws -> Bool { await currentTier() == .pro }

    /// Reads the entitlement WITHOUT touching the network, so launch is never
    /// gated on Lemon Squeezy being reachable. `refreshIfNeeded()` is what
    /// eventually re-confirms or revokes it.
    public func currentTier() async -> UserTier {
        LicenseEntitlementPolicy.entitlement(for: storedRecord(), now: now()) == .pro
            ? .pro : .free
    }

    /// Asks Lemon Squeezy again when the stored record is due, and applies the
    /// answer: a confirmation refreshes the grace clock, a rejection clears the
    /// record so Pro drops, and an unreachable network changes nothing.
    ///
    /// Safe to call on every launch — it no-ops until the record is due.
    @discardableResult
    public func refreshIfNeeded() async -> UserTier {
        guard let record = storedRecord(),
            LicenseEntitlementPolicy.needsRevalidation(record, now: now())
        else { return await currentTier() }

        switch await activation.refresh(record) {
        case .confirmed(let refreshed):
            try? persist(refreshed)
        case .revoked:
            try? store.clear()
        case .unreachable:
            break
        }
        return await currentTier()
    }

    /// Releases this Mac's activation slot with Lemon Squeezy and forgets the
    /// license locally. The local record is cleared even when the call cannot
    /// reach Lemon Squeezy: the user asked to sign out here, and the slot can be
    /// reclaimed from their Lemon Squeezy account.
    public func deactivate() async -> LicenseActivationResult {
        guard let record = storedRecord() else { return .activated }
        let outcome = await activation.deactivate(record)
        do {
            try store.clear()
        } catch {
            return .storageUnavailable(reason: error.localizedDescription)
        }
        if case .unreachable(let reason) = outcome {
            return .networkUnavailable(reason: reason)
        }
        return .activated
    }

    /// Activates the key with Lemon Squeezy, records the result, and reports a
    /// distinguishable outcome so the UI can guide the user. `activate(_:)` (the
    /// Bool convenience) is derived from this by the protocol default.
    public func activateResult(licenseKey: String) async -> LicenseActivationResult {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey(reason: "Empty key") }
        switch await activation.activate(licenseKey: trimmed, instanceName: instanceName) {
        case .activated(let record):
            // Persist, then confirm it reads back. A Keychain write can fail; if
            // it does, the entitlement wouldn't survive a relaunch (currentTier
            // reads from the store), so report it instead of a false success.
            do {
                try persist(record)
            } catch {
                return .storageUnavailable(reason: error.localizedDescription)
            }
            // Compare identity, not the whole record: the stamps round-trip
            // through ISO-8601, which drops sub-second precision, so a
            // byte-equality check here would fail every successful activation.
            // What must be proven is that the license survived the write.
            let stored = storedRecord()
            guard stored?.licenseKey == record.licenseKey,
                stored?.instanceID == record.instanceID
            else {
                return .storageUnavailable(reason: "The license did not persist on this device")
            }
            return .activated
        case .rejected(let reason):
            return .invalidKey(reason: reason)
        case .unreachable(let reason):
            return .networkUnavailable(reason: reason)
        }
    }

    /// The record travels through the existing string-shaped Keychain store as
    /// JSON, so the storage layer and its access-group behavior are unchanged.
    private func storedRecord() -> LicenseActivationRecord? {
        guard let raw = store.load(), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder.license.decode(LicenseActivationRecord.self, from: data)
    }

    private func persist(_ record: LicenseActivationRecord) throws {
        let data = try JSONEncoder.license.encode(record)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw RecordCodingError.notUTF8
        }
        try store.save(json)
    }

    private enum RecordCodingError: Error { case notUTF8 }
}
