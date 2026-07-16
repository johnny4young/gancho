import Foundation
import Testing

@testable import GanchoAI

/// The structural pre-model redaction boundary: what the model never sees, it
/// cannot echo. Every rule redacts its target and — just as important — every
/// look-alike survives, because over-redaction silently degrades summaries and
/// titles of ordinary text.
@Suite("Model input sanitizer — structural secret redaction")
struct ModelInputSanitizerTests {
    @Test("Vendor tokens, JWTs, AWS ids, and bearer credentials are redacted")
    func tokens() {
        let cases = [
            "the key is sk-test-gancho-4242424242424242, rotate it",
            "push token ghp_abcdefghijklmnopqrstuv1234567890",
            "slack xoxb-123456789012-abcdefghijkl",
            "aws AKIAIOSFODNN7EXAMPLE id",
            "jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.dQw4w9WgXcQ_signature",
            "Authorization: Bearer abcdef0123456789abcdef0123456789"
        ]
        for text in cases {
            let out = ModelInputSanitizer.sanitized(text)
            #expect(out.contains(ModelInputSanitizer.placeholder), "must redact: \(text)")
        }
        #expect(
            !ModelInputSanitizer.sanitized("sk-test-gancho-4242424242424242")
                .contains("4242"))
    }

    @Test("PEM private key blocks are redacted whole")
    func pemBlocks() {
        let pem = """
            before
            -----BEGIN RSA PRIVATE KEY-----
            MIIEowIBAAKCAQEA0Zx...
            -----END RSA PRIVATE KEY-----
            after
            """
        let out = ModelInputSanitizer.sanitized(pem)
        #expect(!out.contains("MIIEowIBAAKCAQEA0Zx"))
        #expect(out.contains("before") && out.contains("after"))
    }

    @Test("Assignments keep the variable name and lose only the value")
    func assignments() {
        let out = ModelInputSanitizer.sanitized(
            "export STAGING_API_KEY=super$ecretValue99 # rotate")
        #expect(!out.contains("super$ecretValue99"))
        #expect(out.contains("STAGING_API_KEY"), "the name must survive")

        let colon = ModelInputSanitizer.sanitized("password: correcthorsebatterystaple")
        #expect(!colon.contains("correcthorsebatterystaple"))
    }

    @Test("Luhn-valid card runs are redacted; non-validating digit runs survive")
    func luhnRuns() {
        let card = ModelInputSanitizer.sanitized("charge 4242 4242 4242 4242 today")
        #expect(!card.contains("4242 4242 4242 4242"))

        let order = "order number 1234 5678 9012 3456 shipped"  // fails Luhn
        #expect(ModelInputSanitizer.sanitized(order) == order)
    }

    @Test("Ordinary prose, URLs, UUIDs, and near-miss names survive untouched")
    func noOverRedaction() {
        let benign = [
            "meet me at the coffee shop on 5th at 3pm tomorrow",
            "https://developer.apple.com/documentation/foundationmodels",
            "id 550e8400-e29b-41d4-a716-446655440000 created",
            "keyword: analytics dashboard refresh",
            "the monkey: a natural history",
            "La reunión se movió para el jueves a las 10am",
            "Total: $1,284.50 (includes 8.5% tax)"
        ]
        for text in benign {
            #expect(ModelInputSanitizer.sanitized(text) == text, "must survive: \(text)")
        }
    }

    @Test("Sanitizing is idempotent")
    func idempotent() {
        let once = ModelInputSanitizer.sanitized(
            "key: sk-test-gancho-4242424242424242 and card 4242 4242 4242 4242")
        #expect(ModelInputSanitizer.sanitized(once) == once)
    }
}
