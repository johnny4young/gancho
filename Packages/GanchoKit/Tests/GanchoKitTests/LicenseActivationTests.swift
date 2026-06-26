import CryptoKit
import Foundation
import Testing

@testable import GanchoKit

@Suite("Lemon Squeezy activation")
struct LicenseActivationTests {
    /// A canned transport that returns a fixed JSON body and HTTP status.
    private static func transport(
        _ json: String, status: Int = 200
    )
        -> LemonSqueezyValidator.Transport
    {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
    }

    @Test("An active license key yields its Lemon Squeezy id")
    func activated() async {
        let json = #"{"activated":true,"error":null,"license_key":{"id":42,"status":"active"}}"#
        let validator = LemonSqueezyValidator(transport: Self.transport(json))
        let result = await validator.activate(licenseKey: "K-1", instanceName: "Mac")
        #expect(result == .activated(licenseID: "42"))
    }

    @Test("An unknown or inactive key is rejected with the server's reason")
    func rejected() async {
        let json = #"{"activated":false,"error":"license_key not found.","license_key":null}"#
        let validator = LemonSqueezyValidator(transport: Self.transport(json))
        let result = await validator.activate(licenseKey: "bad", instanceName: "Mac")
        #expect(result == .rejected(reason: "license_key not found."))
    }

    @Test("A transport failure surfaces as unreachable, never a crash")
    func unreachable() async {
        let validator = LemonSqueezyValidator(transport: { _ in
            throw URLError(.notConnectedToInternet)
        })
        guard case .unreachable = await validator.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("expected unreachable")
            return
        }
    }

    @Test("The request posts the key and instance name, form-encoded")
    func requestShape() async {
        final class Box: @unchecked Sendable { var request: URLRequest? }
        let box = Box()
        let validator = LemonSqueezyValidator(transport: { request in
            box.request = request
            let body = #"{"activated":true,"license_key":{"id":1}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        })
        _ = await validator.activate(licenseKey: "ABC", instanceName: "My Mac")
        let body = String(data: box.request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(box.request?.httpMethod == "POST")
        #expect(body.contains("license_key=ABC"))
        #expect(body.contains("instance_name=My%20Mac"))
    }

    @Test("On success the service mints a token that verifies with the public key")
    func serviceSignsVerifiableToken() async {
        let key = Curve25519.Signing.PrivateKey()
        let json = #"{"activated":true,"license_key":{"id":7,"status":"active"}}"#
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(json)),
            signingKey: key, now: { Date(timeIntervalSince1970: 1) })
        guard
            case .activated(let signed) =
                await service.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("expected activated")
            return
        }
        let verified = LicenseVerifier(publicKey: key.publicKey).verify(signed)
        #expect(verified == LicenseToken(licenseID: "7", issuedAt: Date(timeIntervalSince1970: 1)))
    }

    @Test("A build with no signing key is not licensable")
    func notLicensable() async {
        let json = #"{"activated":true,"license_key":{"id":1}}"#
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(json)), signingKey: nil)
        let outcome = await service.activate(licenseKey: "K", instanceName: "M")
        #expect(outcome == .notLicensable)
    }
}
