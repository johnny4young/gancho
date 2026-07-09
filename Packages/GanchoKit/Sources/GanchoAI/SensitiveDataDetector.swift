import Foundation
import GanchoKit

/// On-device secret detection: if the user copies an API key by accident,
/// Gancho treats it as a secret — masked preview, short expiry. 100%
/// deterministic, zero network; patterns over CONTAINED text (a key inside
/// a config line still counts, unlike the full-string tier-0 classifier).
public struct SensitiveDataDetector: Sendable {
    public enum Category: String, Sendable, Equatable, CaseIterable {
        case creditCard
        case awsAccessKey
        case awsSecretKey
        case stripeSecretKey
        case githubToken
        case slackToken
        case slackWebhookURL
        case googleAPIKey
        case gcpServiceAccount
        case openAIKey
        case npmToken
        case azureConnectionString
        case authorizationHeader
        case pemPrivateKey
        case pgpPrivateKey
        case probablePassword
    }

    public init() {}

    // Detection order is the policy: strongest structured signals first, then
    // loose password heuristics last.
    // swiftlint:disable cyclomatic_complexity
    /// First (highest-confidence) category found, or nil for clean text.
    /// Order matters: structured key formats are unambiguous; the entropy
    /// password heuristic runs last because it is the loosest.
    public func detect(_ text: String) -> Category? {
        // swiftlint:enable cyclomatic_complexity
        if containsPEMPrivateKey(text) { return .pemPrivateKey }
        if matches(#"-----BEGIN PGP PRIVATE KEY BLOCK-----"#, in: text) {
            return .pgpPrivateKey
        }
        if matches(#"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#, in: text) { return .awsAccessKey }
        if matches(
            #"aws_secret_access_key\s*[=:]\s*[0-9A-Za-z/+=]{40}"#, in: text,
            caseInsensitive: true)
        {
            return .awsSecretKey
        }
        if matches(#"\b(sk|rk)_(live|test)_[0-9a-zA-Z]{10,}\b"#, in: text) {
            return .stripeSecretKey
        }
        if matches(#"\bgh[pousr]_[0-9A-Za-z]{36,}\b"#, in: text) { return .githubToken }
        if matches(#"\bxox[baprs]-[0-9A-Za-z-]{10,}\b"#, in: text) { return .slackToken }
        // Incoming-webhook URL: possession alone lets anyone post to the
        // workspace, so the URL itself is the credential.
        if matches(
            #"hooks\.slack\.com/services/T[0-9A-Z]{5,}/B[0-9A-Z]{5,}/[0-9A-Za-z]{10,}"#,
            in: text)
        {
            return .slackWebhookURL
        }
        // Google API key: fixed AIza prefix + 35 URL-safe chars.
        if matches(#"\bAIza[0-9A-Za-z_-]{35}\b"#, in: text) { return .googleAPIKey }
        // GCP service-account JSON — the credential FILE, even when the
        // embedded PEM block was truncated away.
        if matches(#""type"\s*:\s*"service_account""#, in: text) { return .gcpServiceAccount }
        // OpenAI-style keys: `sk-` + optional project/service segment. Distinct
        // from Stripe, which uses `sk_live_`/`sk_test_` (underscores).
        if matches(#"\bsk-(proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}\b"#, in: text) {
            return .openAIKey
        }
        if matches(#"\bnpm_[0-9A-Za-z]{36}\b"#, in: text) { return .npmToken }
        // Azure storage / Service Bus connection strings — AccountKey and
        // SharedAccessKey values are long base64 secrets.
        if matches(
            #"\b(AccountKey|SharedAccessKey)\s*=\s*[0-9A-Za-z+/=]{40,}"#, in: text,
            caseInsensitive: true)
        {
            return .azureConnectionString
        }
        if containsAuthorizationSecret(text) { return .authorizationHeader }
        if let card = containedCardCandidate(text), Luhn.validates(card) {
            return .creditCard
        }
        if isProbablePassword(text) { return .probablePassword }
        return nil
    }

    // MARK: - Patterns

    private func containsPEMPrivateKey(_ text: String) -> Bool {
        matches(
            #"-----BEGIN (RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"#, in: text)
    }

    /// HTTP credential material: an `Authorization:` header line with a
    /// Bearer/Basic/Token credential, or a bare `Bearer <long opaque token>`
    /// (curl snippets). The 20-char floor on the bare form keeps prose that
    /// merely contains the word "bearer" out of the secret bucket.
    private func containsAuthorizationSecret(_ text: String) -> Bool {
        if matches(
            #"(?i)\bauthorization\s*:\s*(bearer|basic|token)\s+[A-Za-z0-9\-._~+/=]{8,}"#,
            in: text)
        {
            return true
        }
        return matches(#"(?i)\bbearer\s+[A-Za-z0-9\-._~+/]{20,}=*"#, in: text)
    }

    /// 13–19 digit run (spaces/dashes allowed) anywhere in the text.
    private func containedCardCandidate(_ text: String) -> String? {
        guard
            let range = text.range(
                of: #"(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])"#,
                options: .regularExpression)
        else { return nil }
        let digits = text[range].filter(\.isNumber)
        return (13...19).contains(digits.count) ? String(digits) : nil
    }

    /// Three routes, all conservative:
    /// 1. Context: "password:"/"pwd ="/"contraseña:" followed by a token.
    /// 2. Shape: a single 12–64 char token using all four character classes
    ///    with high Shannon entropy — random generator output, not prose.
    /// 3. Shape: a single ≥24 char all-alphanumeric token with very high
    ///    entropy — base32 TOTP seeds, random generator output.
    private func isProbablePassword(_ text: String) -> Bool {
        if let range = text.range(
            of: #"(?i)(password|passwd|pwd|contraseña|passphrase)\s*[:=]\s*\S{8,}"#,
            options: .regularExpression), !range.isEmpty
        {
            return true
        }

        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (12...64).contains(token.count), !token.contains(where: \.isWhitespace) else {
            return false
        }
        // Known PUBLIC key formats (Stripe publishable) are high-entropy by
        // design but secret by no definition — masking them is pure noise.
        if token.range(of: #"^pk_(live|test)_"#, options: .regularExpression) != nil {
            return false
        }
        let classes = [
            token.contains(where: \.isUppercase),
            token.contains(where: \.isLowercase),
            token.contains(where: \.isNumber),
            token.contains { !$0.isLetter && !$0.isNumber }
        ]
        if classes.allSatisfy({ $0 }) {
            return shannonEntropy(token) > 3.0
        }
        // 3. Shape: a long single-token alphanumeric with very high entropy —
        //    base32 TOTP seeds, generator output. Fewer character classes, so
        //    the bar is higher: ≥24 chars AND entropy > 4.0. Prose never
        //    qualifies (whitespace fails the token guard above), and ordinary
        //    long identifiers repeat characters, landing well below 4 bits.
        guard token.count >= 24,
            token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return false }
        return shannonEntropy(token) > 4.0
    }

    /// Bits per character; random 4-class tokens land well above 3.
    private func shannonEntropy(_ text: String) -> Double {
        var counts: [Character: Int] = [:]
        for character in text {
            counts[character, default: 0] += 1
        }
        let length = Double(text.count)
        return counts.values.reduce(0) { entropy, count in
            let p = Double(count) / length
            return entropy - p * log2(p)
        }
    }

    private func matches(
        _ pattern: String, in text: String, caseInsensitive: Bool = false
    ) -> Bool {
        text.range(
            of: pattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil
    }
}

/// Shared Luhn checksum (cards) — used by the tier-0 classifier and the
/// sensitive detector.
enum Luhn {
    static func validates(_ digits: String) -> Bool {
        guard digits.allSatisfy(\.isNumber), !digits.isEmpty else { return false }
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            var digit = character.wholeNumberValue ?? 0
            if offset % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum.isMultiple(of: 10)
    }
}

/// Masked rendering policy: previews of sensitive clips NEVER contain the
/// secret — the stored preview is already masked; revealing reads the full
/// content explicitly (optionally behind Touch ID, a UI concern).
public enum SensitiveMasking {
    /// "●●●● 1111" — bullets plus the last 4 non-whitespace characters.
    /// Multiline payloads (PEM blocks) and short values (an OTP, a PIN —
    /// where 4 chars would reveal most of the secret) mask entirely.
    public static func maskedPreview(for text: String) -> String {
        guard !text.contains("\n") else { return "●●●●" }
        let stripped = text.filter { !$0.isWhitespace }
        guard stripped.count > 8 else { return "●●●●" }
        return "●●●● \(String(stripped.suffix(4)))"
    }
}

/// Decorates a freshly classified clip when the detector fires: secret kind,
/// sensitive flag, masked preview, and the short expiry the retention engine
/// enforces (default 10 minutes). Pure — the capture pipelines call it.
public enum SensitiveIngestionPolicy {
    public static func decorate(
        _ item: ClipItem,
        finding: SensitiveDataDetector.Category?,
        originalText: String,
        sensitiveLifetime: TimeInterval = 600,
        now: Date = .now
    ) -> ClipItem {
        guard let finding else { return item }
        var decorated = item
        decorated.isSensitive = true
        decorated.expiresAt = now.addingTimeInterval(sensitiveLifetime)
        decorated.preview = SensitiveMasking.maskedPreview(for: originalText)
        // Cards keep their kind (drives the card icon); everything else
        // becomes a secret.
        if finding != .creditCard {
            decorated.kind = .secret
        }
        return decorated
    }
}
