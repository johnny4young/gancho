import CryptoKit
import Foundation
import Testing

@testable import GanchoKit

@MainActor
@Suite("Direct-download license purchase handler")
struct LicensePurchaseHandlerTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func service(activated: Bool) -> LicenseActivationService {
        let json =
            activated
            ? #"{"activated":true,"license_key":{"id":99,"status":"active"}}"#
            : #"{"activated":false,"error":"license_key not found."}"#
        let transport: LemonSqueezyValidator.Transport = { request in
            (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        return LicenseActivationService(
            validator: LemonSqueezyValidator(transport: transport), signingKey: key)
    }

    private func handler(
        store: any LicenseTokenStore, activated: Bool
    )
        -> LicenseKeyPurchaseHandler
    {
        LicenseKeyPurchaseHandler(
            store: store, verifier: LicenseVerifier(publicKey: key.publicKey),
            activation: service(activated: activated), instanceName: "Test Mac")
    }

    @Test("No stored token means Free")
    func emptyIsFree() async {
        let handler = handler(store: InMemoryLicenseTokenStore(), activated: true)
        #expect(await handler.currentTier() == .free)
    }

    @Test("Activating a valid key stores a token and unlocks Pro")
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

    @Test("A token signed by a foreign key is not honored")
    func foreignTokenRejected() async throws {
        let foreign = try LicenseSigner.sign(
            LicenseToken(licenseID: "x", issuedAt: .now),
            with: Curve25519.Signing.PrivateKey())
        let handler = handler(
            store: InMemoryLicenseTokenStore(token: foreign), activated: true)
        #expect(await handler.currentTier() == .free)
    }
}
