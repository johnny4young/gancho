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

    @Test("An expired token is rejected; before the deadline it still unlocks")
    func expiryEnforced() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let issued = Date(timeIntervalSince1970: 1_700_000_000)
        let token = LicenseToken(
            licenseID: "ls-order-42", issuedAt: issued, expiresAt: issued + 600)
        let signed = try LicenseSigner.sign(token, with: key)
        #expect(verifier.verify(signed, now: issued + 599) == token)
        #expect(verifier.verify(signed, now: issued + 601) == nil)
    }

    @Test("A fingerprint-bound token unlocks only on the matching install")
    func fingerprintEnforced() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let token = LicenseToken(
            licenseID: "ls-order-42",
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            boundFingerprint: "fp-alpha")
        let signed = try LicenseSigner.sign(token, with: key)
        #expect(verifier.verify(signed, fingerprint: "fp-alpha") == token)
        #expect(verifier.verify(signed, fingerprint: "fp-other") == nil)
        // No fingerprint offered at all → a bound token fails closed.
        #expect(verifier.verify(signed) == nil)
    }

    @Test("A legacy payload without the new keys still verifies, unconstrained")
    func legacyTokenStillUnlocks() throws {
        // Hand-built payload exactly as the pre-hardening app signed it: only
        // licenseID + issuedAt. Its signature covers these bytes, so it must
        // keep verifying and decode with nil (no-constraint) fields.
        let key = Curve25519.Signing.PrivateKey()
        let payload = Data(
            #"{"issuedAt":"2023-11-14T22:13:20Z","licenseID":"ls-order-42"}"#.utf8)
        let signature = try key.signature(for: payload)
        let signed = payload.base64EncodedString() + "." + signature.base64EncodedString()
        let verified = LicenseVerifier(publicKey: key.publicKey).verify(signed)
        #expect(verified == sample)
        #expect(verified?.expiresAt == nil)
        #expect(verified?.boundFingerprint == nil)
    }

    @Test("Expiry and fingerprint round-trip through sign→verify")
    func constrainedRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let issued = Date(timeIntervalSince1970: 1_700_000_000)
        let token = LicenseToken(
            licenseID: "ls-order-42", issuedAt: issued,
            expiresAt: issued + 3600, boundFingerprint: "fp-alpha")
        let signed = try LicenseSigner.sign(token, with: key)
        let verified = verifier.verify(signed, now: issued, fingerprint: "fp-alpha")
        #expect(verified == token)
        #expect(verified?.expiresAt == issued + 3600)
        #expect(verified?.boundFingerprint == "fp-alpha")
    }

    @Test("The install fingerprint is minted once and stays stable per store")
    func installFingerprintStable() {
        let store = InMemoryLicenseTokenStore()
        let first = LicenseFingerprint.current(in: store)
        let second = LicenseFingerprint.current(in: store)
        #expect(first == second)
        #expect(first.count == 64)  // SHA-256 hex digest
        // A different install (fresh store) gets a different fingerprint.
        #expect(LicenseFingerprint.current(in: InMemoryLicenseTokenStore()) != first)
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
