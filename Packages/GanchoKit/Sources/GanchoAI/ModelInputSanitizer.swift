import Foundation

/// Deterministic, span-level redaction of secret-SHAPED tokens from text that
/// is about to be sent to the on-device model. The live prompt evaluation
/// proved that instructions alone cannot stop the system model from echoing a
/// key that appears in its input ("faithful" summaries reproduce it), so the
/// only reliable guarantee is structural: the model never sees the secret in
/// the first place — what it never saw, it cannot echo.
///
/// Scope is deliberately narrow: structured secrets (PEM blocks, known token
/// prefixes, JWTs, bearer headers, KEY=value assignments, Luhn-valid card
/// runs). General PII stays with `PIIRedactor` — that is a USER action with
/// its own semantics, while this is an internal boundary applied to every
/// model call. Callers still gate whole sensitive clips off before this runs;
/// this catches the mixed-content case (one key line inside an ordinary memo).
public enum ModelInputSanitizer {
    public static let placeholder = "[redacted]"

    /// Replaces every secret-shaped span with `[redacted]` (assignments keep
    /// their variable name so the surrounding text still reads). Idempotent.
    public static func sanitized(_ text: String) -> String {
        var output = text
        for pattern in Self.spanPatterns {
            output = pattern.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output),
                withTemplate: placeholder)
        }
        output = Self.assignmentPattern.stringByReplacingMatches(
            in: output, range: NSRange(output.startIndex..., in: output),
            withTemplate: "$1 \(placeholder)")
        return redactingLuhnRuns(in: output)
    }

    // MARK: - Patterns

    /// Whole-span secrets: PEM blocks, vendor token prefixes, JWTs, bearer
    /// credentials. Compiled once; a pattern that fails to compile is a
    /// programmer error caught by the unit tests.
    private static let spanPatterns: [NSRegularExpression] = [
        // PEM private key blocks (multi-line).
        "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        // Vendor-prefixed API tokens (OpenAI/Stripe-style sk-/pk-/rk-, GitHub,
        // Slack, AWS access key ids).
        "\\b(?:sk|pk|rk)-[A-Za-z0-9_-]{8,}\\b",
        "\\bghp_[A-Za-z0-9]{20,}\\b",
        "\\bgithub_pat_[A-Za-z0-9_]{20,}\\b",
        "\\bxox[a-z]-[A-Za-z0-9-]{10,}\\b",
        "\\bAKIA[0-9A-Z]{16}\\b",
        // JWTs (three base64url segments, the first decoding to a JSON header).
        "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}\\b",
        // Bearer / Authorization credentials.
        "(?i)\\bbearer\\s+[A-Za-z0-9._~+/=-]{16,}"
    ].map {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: $0)
    }

    /// `API_KEY=…` / `password: …` assignments — the VALUE is redacted, the
    /// name survives so the sentence still reads. The name must be the word
    /// `key`/`token`/`secret`/`password` (or end in `_key`, `-key`, `apikey`),
    /// so `keyword:` or `monkey:` never match.
    private static let assignmentPattern: NSRegularExpression = {
        let name = "[A-Za-z0-9_-]*(?:api[_-]?key|[_-]key|secret|token|password|passwd)|key"
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: "(?i)\\b((?:\(name))s?\\b\\s*[=:])\\s*[^\\s\"']{8,}")
    }()

    /// Card-shaped digit runs (13–19 digits with optional spaces/dashes) are
    /// redacted only when they Luhn-validate — order numbers and phone-like
    /// runs fail the checksum and survive.
    private static let digitRunPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "\\b\\d(?:[ -]?\\d){12,18}\\b")
    }()

    private static func redactingLuhnRuns(in text: String) -> String {
        let matches = digitRunPattern.matches(
            in: text, range: NSRange(text.startIndex..., in: text))
        var output = text
        // Replace back-to-front so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let digits = output[range].filter(\.isNumber)
            guard Luhn.validates(String(digits)) else { continue }
            output.replaceSubrange(range, with: placeholder)
        }
        return output
    }
}
