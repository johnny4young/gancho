import Foundation
import Testing

@testable import GanchoKit

@MainActor
@Suite("Direct-download license purchase handler")
struct LicensePurchaseHandlerTests {
    private func service(activated: Bool) -> LicenseActivationService {
        // The happy path carries the pinned Gancho store/product identity,
        // mirroring what the live License API always sends. Derived from the
        // pinned constants so retuning them can't rot this fixture; the
        // literal identity is asserted once, in
        // `LicenseActivationTests.pinnedIdentityIsTheLiveProduct`.
        let json =
            activated
            ? #"{"activated":true,"valid":true,"instance":{"id":"inst-99"},"#
                + #""meta":{"store_id":\#(LemonSqueezyValidator.expectedStoreID),"#
                + #""product_id":\#(LemonSqueezyValidator.expectedProductID)}}"#
            : #"{"activated":false,"error":"license_key not found."}"#
        let transport: LemonSqueezyValidator.Transport = { request in
            (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        return LicenseActivationService(
            validator: LemonSqueezyValidator(transport: transport))
    }

    private func handler(
        store: any LicenseTokenStore, activated: Bool
    )
        -> LicenseKeyPurchaseHandler
    {
        LicenseKeyPurchaseHandler(
            store: store, activation: service(activated: activated),
            instanceName: "Test Mac")
    }

    @Test("No stored activation record means Free")
    func emptyIsFree() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: true)
        #expect(await handler.currentTier() == .free)
    }

    @Test("Activating a valid key stores a record and unlocks Pro")
    func activateUnlocksPro() async {
        let store = InMemoryLicenseTokenStore()
        let handler = handler(store: store, activated: true)
        #expect(await handler.activate(licenseKey: "GOOD-KEY") == true)
        #expect(await handler.currentTier() == .pro)
        #expect(store.load() != nil)
    }

    @Test("A key Lemon Squeezy rejects leaves the user Free")
    func rejectedStaysFree() async {
        let store = InMemoryLicenseTokenStore()
        let handler = handler(store: store, activated: false)
        #expect(await handler.activate(licenseKey: "BAD-KEY") == false)
        #expect(await handler.currentTier() == .free)
        #expect(store.load() == nil)
    }

    @Test("An empty key never calls out and stays Free")
    func emptyKeyRejected() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: true)
        #expect(await handler.activate(licenseKey: "   ") == false)
    }

    /// Whatever ends up in the Keychain slot, only a record Gancho can actually
    /// decode may unlock Pro — a stray value, a truncated write, or a leftover
    /// from an older format must read as Free rather than as an entitlement.
    @Test("Unreadable stored content is not an entitlement")
    func unreadableRecordRejected() async {
        for junk in ["", "not-json", #"{"licenseKey":"K"}"#, "eyJhIjoxfQ=="] {
            let handler = handler(
                store: InMemoryLicenseTokenStore(token: junk), activated: true)
            #expect(await handler.currentTier() == .free)
        }
    }

    // MARK: - Distinguishable activation results (drives the paywall's guidance)

    @Test("activateResult reports .activated for a good key")
    func resultActivated() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: true)
        #expect(await handler.activateResult(licenseKey: "GOOD-KEY") == .activated)
    }

    @Test("A key Lemon Squeezy rejects reports .invalidKey, not a network error")
    func resultInvalidKey() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: false)
        guard case .invalidKey = await handler.activateResult(licenseKey: "BAD-KEY") else {
            Issue.record("expected .invalidKey")
            return
        }
    }

    @Test("An empty key reports .invalidKey without ever calling out")
    func resultEmptyKey() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: true)
        guard case .invalidKey = await handler.activateResult(licenseKey: "   ") else {
            Issue.record("expected .invalidKey for an empty key")
            return
        }
    }

    @Test("A server that can't be reached reports .networkUnavailable")
    func resultNetworkUnavailable() async {
        let transport: LemonSqueezyValidator.Transport = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let handler = LicenseKeyPurchaseHandler(
            store: InMemoryLicenseTokenStore(),
            activation: LicenseActivationService(
                validator: LemonSqueezyValidator(transport: transport)),
            instanceName: "Test Mac")
        guard case .networkUnavailable = await handler.activateResult(licenseKey: "GOOD-KEY")
        else {
            Issue.record("expected .networkUnavailable")
            return
        }
    }

    @Test("A handler that can't license keys reports .notLicensable")
    func defaultReportsNotLicensable() async {
        #expect(
            await UnavailablePurchaseHandler().activateResult(licenseKey: "X") == .notLicensable)
        #expect(await UnavailablePurchaseHandler().activate(licenseKey: "X") == false)
    }

    @Test("A valid key whose record can't persist reports storage failure")
    func resultStorageUnavailable() async {
        let handler = LicenseKeyPurchaseHandler(
            store: FailingLicenseTokenStore(),
            activation: service(activated: true), instanceName: "Test Mac")
        guard case .storageUnavailable = await handler.activateResult(licenseKey: "GOOD-KEY")
        else {
            Issue.record("expected .storageUnavailable when the store can't save")
            return
        }
        // The entitlement must not have "taken" — currentTier still reads Free.
        #expect(await handler.currentTier() == .free)
    }

    /// A revocation that cannot be written to the Keychain must still revoke.
    /// Otherwise a failing clear would silently keep Pro alive on a refunded
    /// license — the exact outcome the "Lemon Squeezy is the authority" design
    /// exists to prevent.
    /// Encodes a record exactly as the handler persists it, so a test can seed
    /// a store with an activation that is already in place.
    private func storedJSON(_ record: LicenseActivationRecord) throws -> String {
        let data = try JSONEncoder.license.encode(record)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("A revoked license drops to Free even when the record can't be cleared")
    func revocationSticksWhenClearFails() async throws {
        let stored = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: Date(timeIntervalSince1970: 0))
        let store = UnclearableLicenseTokenStore(token: try storedJSON(stored))
        let transport: LemonSqueezyValidator.Transport = { request in
            (
                Data(#"{"valid":false,"error":"license_key is disabled."}"#.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        // Far past the revalidation interval, so the refresh actually runs.
        let later = Date(
            timeIntervalSince1970: LicenseEntitlementPolicy.revalidationInterval + 1)
        let handler = LicenseKeyPurchaseHandler(
            store: store,
            activation: LicenseActivationService(
                validator: LemonSqueezyValidator(transport: transport), now: { later }),
            instanceName: "Test Mac", now: { later })

        #expect(await handler.currentTier() == .pro)
        #expect(await handler.refreshIfNeeded() == .free)
        // The store still holds the stale record; the entitlement must not.
        #expect(store.load() != nil)
        #expect(await handler.currentTier() == .free)
    }

    @Test("Rate limits and server errors preserve the stored license and grace")
    func httpOutagePreservesStoredLicense() async throws {
        let stored = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: Date(timeIntervalSince1970: 0))
        let encoded = try storedJSON(stored)
        let later = Date(
            timeIntervalSince1970: LicenseEntitlementPolicy.revalidationInterval + 1)

        for status in [429, 500, 503] {
            let store = InMemoryLicenseTokenStore(token: encoded)
            let transport: LemonSqueezyValidator.Transport = { request in
                (
                    Data(#"{"valid":false,"error":"license_key is disabled."}"#.utf8),
                    HTTPURLResponse(
                        url: request.url!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
                )
            }
            let handler = LicenseKeyPurchaseHandler(
                store: store,
                activation: LicenseActivationService(
                    validator: LemonSqueezyValidator(transport: transport), now: { later }),
                instanceName: "Test Mac", now: { later })

            #expect(await handler.refreshIfNeeded() == .pro)
            #expect(store.load() == encoded)
            #expect(await handler.currentTier() == .pro)
        }
    }

    /// The paywall's "Check again" must work the moment a lapsed user
    /// reconnects. If it merely deferred to the schedule it would strand them
    /// until the next interval — so this asserts the schedule is BYPASSED:
    /// the record was just validated, `needsRevalidation` is false, and a
    /// recheck still reaches Lemon Squeezy and applies the answer.
    @Test("Check again revalidates immediately, even when not due")
    func recheckIgnoresTheSchedule() async throws {
        let stamp = Date(timeIntervalSince1970: 1_000)
        let stored = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: stamp, lastValidatedAt: stamp)
        #expect(!LicenseEntitlementPolicy.needsRevalidation(stored, now: stamp))

        final class Box: @unchecked Sendable { var calls = 0 }
        let box = Box()
        let transport: LemonSqueezyValidator.Transport = { request in
            box.calls += 1
            return (
                Data(#"{"valid":false,"error":"license_key is disabled."}"#.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let store = InMemoryLicenseTokenStore(token: try storedJSON(stored))
        let handler = LicenseKeyPurchaseHandler(
            store: store,
            activation: LicenseActivationService(
                validator: LemonSqueezyValidator(transport: transport), now: { stamp }),
            instanceName: "Test Mac", now: { stamp })

        // The scheduled path declines to call out; the on-demand path must not.
        #expect(await handler.refreshIfNeeded() == .pro)
        #expect(box.calls == 0)
        #expect(await handler.recheckNow() == .free)
        #expect(box.calls == 1)
    }

    /// Signing out releases the Lemon Squeezy slot. Even when that call cannot
    /// reach Lemon Squeezy, the local entitlement goes away: the user asked to
    /// sign out here, and the slot is reclaimable from their account.
    @Test("Deactivation drops Pro locally even when Lemon Squeezy is unreachable")
    func deactivateClearsLocallyWhenOffline() async throws {
        let stored = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: Date(timeIntervalSince1970: 0))
        let store = InMemoryLicenseTokenStore(token: try storedJSON(stored))
        // Just after the stamp: comfortably inside grace, so the record starts
        // out entitled and the test measures deactivation, not expiry.
        let soon = Date(timeIntervalSince1970: 60)
        let handler = LicenseKeyPurchaseHandler(
            store: store,
            activation: LicenseActivationService(
                validator: LemonSqueezyValidator(transport: { _ in
                    throw URLError(.notConnectedToInternet)
                }),
                now: { soon }),
            instanceName: "Test Mac", now: { soon })

        #expect(await handler.currentTier() == .pro)
        guard case .networkUnavailable = await handler.deactivate() else {
            Issue.record("expected the outage to be reported")
            return
        }
        #expect(store.load() == nil)
        #expect(await handler.currentTier() == .free)
    }
}

/// A store that holds a record but refuses to forget it — the Keychain clear
/// fails. Revocation must still take Pro away.
private final class UnclearableLicenseTokenStore: LicenseTokenStore, @unchecked Sendable {
    struct ClearFailed: Error {}
    private var token: String?
    init(token: String?) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { throw ClearFailed() }
}

/// A store whose Keychain write always fails — exercises the activation path
/// where the key validates but its activation record cannot be persisted.
private struct FailingLicenseTokenStore: LicenseTokenStore {
    struct WriteFailed: Error {}
    func load() -> String? { nil }
    func save(_ token: String) throws { throw WriteFailed() }
    func clear() throws {}
}
