import CryptoKit
import Foundation

/// Reads the Ed25519 PRIVATE signing key from the app bundle, where the release
/// build injects it (project.yml expands `$(GANCHO_LICENSE_SIGNING_KEY)` into
/// the Info.plist key `GanchoLicenseSigningKey`).
///
/// Returns nil when the key is absent: a from-source, CI, or App Store build
/// has no signing key and therefore cannot mint direct-download license tokens.
/// That honor-model default is intentional — the App Store build uses StoreKit,
/// and a self-built copy stays Free.
public enum LicenseSigningKey {
    static let infoPlistKey = "GanchoLicenseSigningKey"

    public static var embedded: Curve25519.Signing.PrivateKey? {
        key(fromBase64: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Whether this build can actually activate a direct-download license (a
    /// signing key is baked). False for from-source / CI / unsigned builds — so
    /// the paywall can show an honest "coming soon" instead of dead-ending every
    /// license key on "could not be activated".
    public static var isConfigured: Bool { embedded != nil }

    /// Pure parser, testable without a bundle. Rejects an empty value and the
    /// unexpanded `$(GANCHO_LICENSE_SIGNING_KEY)` placeholder.
    public static func key(fromBase64 base64: String?) -> Curve25519.Signing.PrivateKey? {
        guard let base64, !base64.isEmpty, !base64.hasPrefix("$("),
            let raw = Data(base64Encoded: base64),
            let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        else { return nil }
        return key
    }
}
