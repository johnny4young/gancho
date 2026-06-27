import CryptoKit
import Foundation

/// The payload Gancho signs into a direct-download (non-App-Store) license
/// token. It carries no secret — only the Lemon Squeezy license id and an
/// issue date — so it is safe to store and inspect. A lifetime license never
/// expires; an optional `expiresAt` can be added later without breaking older
/// tokens.
public struct LicenseToken: Codable, Equatable, Sendable {
    public let licenseID: String
    public let issuedAt: Date

    public init(licenseID: String, issuedAt: Date) {
        self.licenseID = licenseID
        self.issuedAt = issuedAt
    }
}

extension JSONEncoder {
    /// Deterministic encoder (sorted keys + ISO-8601 dates) for stable signing.
    static var license: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var license: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Signs a license token with the holder's Ed25519 private key. Only the
/// release build (and the maintainer's signing tooling) ever holds the private
/// key — a from-source or App Store build has none and cannot mint tokens.
public enum LicenseSigner {
    public static func sign(
        _ token: LicenseToken, with privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let payload = try JSONEncoder.license.encode(token)
        let signature = try privateKey.signature(for: payload)
        return payload.base64EncodedString() + "." + signature.base64EncodedString()
    }
}

/// Verifies a license token OFFLINE against an embedded Ed25519 public key.
/// Token format: `base64(payload) + "." + base64(signature)`. Verification
/// checks the signature against the exact received payload bytes, then decodes
/// them — so a tampered payload or a foreign signature is rejected.
public struct LicenseVerifier: Sendable {
    public let publicKey: Curve25519.Signing.PublicKey

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    public func verify(_ token: String) -> LicenseToken? {
        let parts = token.split(
            separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
            let payload = Data(base64Encoded: String(parts[0])),
            let signature = Data(base64Encoded: String(parts[1])),
            publicKey.isValidSignature(signature, for: payload),
            let decoded = try? JSONDecoder.license.decode(LicenseToken.self, from: payload)
        else { return nil }
        return decoded
    }

    /// The public key baked into the app. Its matching private key is injected
    /// only at release time (see `LicenseSigningKey`); rotate the pair with
    /// `scripts/generate-license-keypair.swift` and replace the base64 below.
    public static let embedded = LicenseVerifier(
        publicKey: try! Curve25519.Signing.PublicKey(
            rawRepresentation: Data(
                base64Encoded: "J8LZORbLAEsr4ooyqQflmCmgfBhEAhcw5ncOXiotU9I=")!))
}
