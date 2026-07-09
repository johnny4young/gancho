import CryptoKit
import Foundation

/// The payload Gancho signs into a direct-download (non-App-Store) license
/// token. It carries no secret — only the Lemon Squeezy license id, an issue
/// date, and optional constraints — so it is safe to store and inspect.
///
/// `expiresAt` and `boundFingerprint` are OPTIONAL: a missing field means "no
/// constraint", so tokens signed before these fields existed (payloads without
/// the keys) decode with nils and keep verifying — the signature covers each
/// token's own payload bytes, never a re-encoding. A lifetime, unbound token
/// simply carries neither field.
public struct LicenseToken: Codable, Equatable, Sendable {
    public let licenseID: String
    public let issuedAt: Date
    /// After this instant the token no longer unlocks Pro. `nil` = lifetime.
    public let expiresAt: Date?
    /// Install fingerprint (see `LicenseFingerprint`) this token is locked to.
    /// `nil` = usable on any install.
    public let boundFingerprint: String?

    public init(
        licenseID: String, issuedAt: Date,
        expiresAt: Date? = nil, boundFingerprint: String? = nil
    ) {
        self.licenseID = licenseID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.boundFingerprint = boundFingerprint
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
/// them — so a tampered payload or a foreign signature is rejected. After the
/// signature holds, the token's own optional constraints are enforced: an
/// `expiresAt` in the past or a `boundFingerprint` that does not match the
/// caller's fingerprint rejects the token. Tokens without those fields (all
/// tokens minted before they existed) carry no constraint and always pass.
public struct LicenseVerifier: Sendable {
    public let publicKey: Curve25519.Signing.PublicKey

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// - Parameters:
    ///   - now: the instant to evaluate `expiresAt` against.
    ///   - fingerprint: this install's fingerprint. A `boundFingerprint` token
    ///     is rejected unless it matches — including when the caller has none
    ///     to offer (fail closed). Unbound tokens ignore it.
    public func verify(
        _ token: String, now: Date = Date(), fingerprint: String? = nil
    ) -> LicenseToken? {
        let parts = token.split(
            separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
            let payload = Data(base64Encoded: String(parts[0])),
            let signature = Data(base64Encoded: String(parts[1])),
            publicKey.isValidSignature(signature, for: payload),
            let decoded = try? JSONDecoder.license.decode(LicenseToken.self, from: payload)
        else { return nil }
        if let expiresAt = decoded.expiresAt, expiresAt < now { return nil }
        if let bound = decoded.boundFingerprint, bound != fingerprint { return nil }
        return decoded
    }

    /// The public key baked into the app. Its matching private key is injected
    /// only at release time (see `LicenseSigningKey`); rotate the pair with
    /// `scripts/generate-license-keypair.swift` and replace the base64 below.
    public static let embedded: LicenseVerifier = {
        guard
            let publicKeyData = Data(
                base64Encoded: "J8LZORbLAEsr4ooyqQflmCmgfBhEAhcw5ncOXiotU9I="),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else {
            preconditionFailure("Invalid embedded license public key")
        }
        return LicenseVerifier(publicKey: publicKey)
    }()
}
