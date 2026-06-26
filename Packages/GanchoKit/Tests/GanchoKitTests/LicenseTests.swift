import CryptoKit
import Foundation
import Testing

@testable import GanchoKit

@Suite("Direct-download license tokens")
struct LicenseTests {
    private let sample = LicenseToken(
        licenseID: "ls-order-42", issuedAt: Date(timeIntervalSince1970: 1_700_000_000))

    @Test("A signed token verifies and round-trips its payload")
    func roundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let signed = try LicenseSigner.sign(sample, with: key)
        #expect(verifier.verify(signed) == sample)
    }

    @Test("A token signed by a different key is rejected")
    func foreignKeyRejected() throws {
        let signed = try LicenseSigner.sign(sample, with: Curve25519.Signing.PrivateKey())
        let otherVerifier = LicenseVerifier(
            publicKey: Curve25519.Signing.PrivateKey().publicKey)
        #expect(otherVerifier.verify(signed) == nil)
    }

    @Test("A tampered payload is rejected even with a real signature")
    func tamperRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let signed = try LicenseSigner.sign(sample, with: key)
        let signature = signed.split(separator: ".", maxSplits: 1)[1]
        let forgedPayload = try JSONEncoder.license.encode(
            LicenseToken(licenseID: "forged", issuedAt: .now)
        ).base64EncodedString()
        #expect(verifier.verify("\(forgedPayload).\(signature)") == nil)
    }

    @Test("Garbage and malformed tokens are rejected, not crashed")
    func malformedRejected() {
        let verifier = LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        for bad in ["", "not-a-token", "only.onepart-but-bad", "$$$.$$$"] {
            #expect(verifier.verify(bad) == nil)
        }
        // Accessing the embedded verifier proves the baked-in key initializes.
        #expect(LicenseVerifier.embedded.verify("garbage") == nil)
    }

    @Test("The signing-key parser rejects empty and unexpanded values")
    func signingKeyParser() {
        #expect(LicenseSigningKey.key(fromBase64: nil) == nil)
        #expect(LicenseSigningKey.key(fromBase64: "") == nil)
        #expect(LicenseSigningKey.key(fromBase64: "$(GANCHO_LICENSE_SIGNING_KEY)") == nil)
        #expect(LicenseSigningKey.key(fromBase64: "not-base64!!!") == nil)
        let real = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        #expect(LicenseSigningKey.key(fromBase64: real) != nil)
    }
}
