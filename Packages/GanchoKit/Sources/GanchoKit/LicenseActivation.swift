import CryptoKit
import Foundation

/// Validates a purchased Lemon Squeezy license key against the Lemon Squeezy
/// License API exactly ONCE, at activation. Gancho then mints a locally-signed
/// `LicenseToken` (see `LicenseActivationService`) that is verified offline on
/// every later launch, so the app never depends on the network again.
///
/// The network egress is injected (`Transport`) instead of performed here, so
/// this type stays pure and testable and the single real network call is wired
/// at the app's composition root — GanchoKit itself never reaches the network.
public struct LemonSqueezyValidator: Sendable {
    public enum Result: Sendable, Equatable {
        case activated(licenseID: String)
        case rejected(reason: String)
        case unreachable(reason: String)
    }

    /// Performs the HTTP round-trip. The app passes a URLSession-backed closure;
    /// tests pass a canned one.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoint: URL
    private let transport: Transport

    public init(
        endpoint: URL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!,
        transport: @escaping Transport
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    public func activate(licenseKey: String, instanceName: String) async -> Result {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body =
            "license_key=\(Self.formEncoded(licenseKey))"
            + "&instance_name=\(Self.formEncoded(instanceName))"
        request.httpBody = Data(body.utf8)

        let data: Data
        do {
            (data, _) = try await transport(request)
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Response.self, from: data) else {
            return .unreachable(reason: "Unexpected Lemon Squeezy response")
        }
        if payload.activated, let id = payload.licenseKey?.id {
            return .activated(licenseID: String(id))
        }
        return .rejected(reason: payload.error ?? "License key is not active")
    }

    private static func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private struct Response: Decodable {
        let activated: Bool
        let error: String?
        let licenseKey: LemonSqueezyLicenseKey?
    }
}

private struct LemonSqueezyLicenseKey: Decodable {
    let id: Int
    let status: String?
}

/// Orchestrates activation: validate the Lemon Squeezy key online once, then
/// mint and sign the offline `LicenseToken`. A build without a signing key
/// (App Store or from-source) has nothing to mint and returns `notLicensable`.
///
/// `@unchecked Sendable`: every stored value is immutable and the Ed25519
/// private key is only ever read (signing is a pure operation), so sharing it
/// across isolation is safe.
public struct LicenseActivationService: @unchecked Sendable {
    public enum Outcome: Sendable, Equatable {
        case activated(signedToken: String)
        case rejected(reason: String)
        case unreachable(reason: String)
        case notLicensable
    }

    private let validator: LemonSqueezyValidator
    private let signingKey: Curve25519.Signing.PrivateKey?
    private let now: @Sendable () -> Date
    private let tokenLifetime: TimeInterval?
    private let fingerprintProvider: @Sendable () -> String?

    /// `tokenLifetime` and `fingerprintProvider` are OPT-IN issuance
    /// constraints (see `LicenseToken.expiresAt`/`boundFingerprint`). The
    /// defaults mint today's lifetime, unbound token, so existing call sites
    /// and existing activations are unchanged until issuance opts in.
    public init(
        validator: LemonSqueezyValidator,
        signingKey: Curve25519.Signing.PrivateKey?,
        now: @escaping @Sendable () -> Date = { Date() },
        tokenLifetime: TimeInterval? = nil,
        fingerprintProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.validator = validator
        self.signingKey = signingKey
        self.now = now
        self.tokenLifetime = tokenLifetime
        self.fingerprintProvider = fingerprintProvider
    }

    public func activate(licenseKey: String, instanceName: String) async -> Outcome {
        guard let signingKey else { return .notLicensable }
        switch await validator.activate(licenseKey: licenseKey, instanceName: instanceName) {
        case .activated(let licenseID):
            let issued = now()
            let token = LicenseToken(
                licenseID: licenseID, issuedAt: issued,
                expiresAt: tokenLifetime.map { issued.addingTimeInterval($0) },
                boundFingerprint: fingerprintProvider())
            guard let signed = try? LicenseSigner.sign(token, with: signingKey) else {
                return .rejected(reason: "Could not sign the license token")
            }
            return .activated(signedToken: signed)
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .unreachable(let reason):
            return .unreachable(reason: reason)
        }
    }
}

/// The Lemon Squeezy hosted checkout where a buyer purchases a direct-download
/// license. The paywall opens this; the buyer then activates the emailed key.
public enum LemonSqueezyStore {
    public static let checkoutURL = URL(
        string: "https://johnny4young.lemonsqueezy.com/checkout/buy/"
            + "be41fa28-055d-4803-893d-9ddada3cc89d")!
}
