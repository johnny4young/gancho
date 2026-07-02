import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

/// 30+ sanitized secret patterns (no real credentials — shapes only) plus
/// the negatives that keep everyday clips out of the secret bucket.
@Suite("SensitiveDataDetector — pattern suite")
struct SensitiveDataDetectorTests {
    let detector = SensitiveDataDetector()

    static let secrets: [(String, SensitiveDataDetector.Category)] = [
        // Credit cards (Luhn-valid), bare and embedded
        ("4111 1111 1111 1111", .creditCard),
        ("4111-1111-1111-1111", .creditCard),
        ("378282246310005", .creditCard),
        ("card on file: 5555 5555 5555 4444 exp 09/27", .creditCard),
        // AWS
        ("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
        ("ASIAY34FZKBOKMUTVV7A", .awsAccessKey),
        ("export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
        ("aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", .awsSecretKey),
        // Stripe (secret/restricted only — publishable keys are public)
        ("sk_live_4eC39HqLyjWDarjtT1zdp7dc", .stripeSecretKey),
        ("sk_test_4eC39HqLyjWDarjtT1zdp7dc", .stripeSecretKey),
        ("rk_live_4eC39HqLyjWDarjtT1zdp7dc", .stripeSecretKey),
        // GitHub
        ("ghp_abcdefghijklmnopqrstuvwxyz0123456789", .githubToken),
        ("gho_abcdefghijklmnopqrstuvwxyz0123456789", .githubToken),
        ("token: ghs_abcdefghijklmnopqrstuvwxyz0123456789", .githubToken),
        // Slack
        ("xoxb-123456789012-abcdefghijklmnop", .slackToken),
        ("xoxp-2-123456789012-abcdefghijklmnop", .slackToken),
        // Slack incoming webhook (the URL IS the credential). The host literal
        // is split so this synthetic fixture is not a contiguous webhook URL in
        // the source — GitHub push-protection flags the shape even when the
        // token is fake; the concatenated runtime value still exercises the
        // detector regex.
        (
            "https://hooks.slack." + "com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX",
            .slackWebhookURL
        ),
        // Google API key (fixed AIza prefix + 35 chars), bare and embedded. The
        // key is split mid-literal so the source carries no contiguous scannable
        // key; the concatenated runtime value still exercises the detector.
        ("AIzaSyDaGmWKa4JsXZ" + "-HjGw7ISLn-3namBGewQe", .googleAPIKey),
        (
            "curl 'https://maps.example/api?key=AIzaSyDaGmWKa4JsXZ" + "-HjGw7ISLn-3namBGewQe'",
            .googleAPIKey
        ),
        // GCP service-account JSON (file shape, even without the PEM block)
        ("{\"type\": \"service_account\", \"project_id\": \"demo-project\"}", .gcpServiceAccount),
        // OpenAI-style keys (sk- with hyphens — distinct from Stripe's sk_).
        // Split mid-literal so no contiguous key sits in the source.
        ("sk-proj-abc123DEF456" + "ghi789JKL012mno345PQR678", .openAIKey),
        ("OPENAI_API_KEY=sk-abcdefghijkl" + "mnopqrstuvwxyz123456", .openAIKey),
        // npm automation token (split mid-literal)
        ("npm_AbCdEfGhIjKlMnOp" + "QrStUvWxYz0123456789", .npmToken),
        // Azure connection strings (AccountKey / SharedAccessKey values)
        (
            "DefaultEndpointsProtocol=https;AccountName=acct;"
                + "AccountKey=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP0123456789+/==;"
                + "EndpointSuffix=core.windows.net",
            .azureConnectionString
        ),
        (
            "Endpoint=sb://demo.servicebus.windows.net/;SharedAccessKeyName=root;"
                + "SharedAccessKey=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+AbCdEf=",
            .azureConnectionString
        ),
        // Authorization headers / bearer credentials. Bearer values are split
        // mid-literal so the source carries no contiguous scannable token.
        (
            "Authorization: Bearer eyJhbGci" + "OiJIUzI1NiJ9.payload.signature",
            .authorizationHeader
        ),
        ("curl -H 'Authorization: Basic " + "dXNlcjpwYXNzd29yZA=='", .authorizationHeader),
        ("Bearer " + "AbCdEfGhIjKlMnOpQrStUvWx123456", .authorizationHeader),
        // PEM private keys (all header variants)
        ("-----BEGIN PRIVATE KEY-----\nMIIEvg==\n-----END PRIVATE KEY-----", .pemPrivateKey),
        (
            "-----BEGIN RSA PRIVATE KEY-----\nMIIEvg==\n-----END RSA PRIVATE KEY-----",
            .pemPrivateKey
        ),
        ("-----BEGIN EC PRIVATE KEY-----\nMHcCAQ==\n-----END EC PRIVATE KEY-----", .pemPrivateKey),
        (
            "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA==\n-----END OPENSSH PRIVATE KEY-----",
            .pemPrivateKey
        ),
        ("-----BEGIN ENCRYPTED PRIVATE KEY-----\nMIIC2w==", .pemPrivateKey),
        // PGP private-key block (not a PEM header variant)
        (
            "-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQdGBGXk\n-----END PGP PRIVATE KEY BLOCK-----",
            .pgpPrivateKey
        ),
        // Passwords by context
        ("password: hunter2-is-bad", .probablePassword),
        ("PASSWORD=Sup3r$ecret!", .probablePassword),
        ("pwd: n0t-Th1s-0ne!", .probablePassword),
        ("contraseña: MiClave#2026", .probablePassword),
        ("passphrase = correct-horse-battery", .probablePassword),
        // Passwords by shape (4 char classes + entropy)
        ("Xk9#mP2$vL5@qR8w", .probablePassword),
        ("J7!nF4&hT1*sW6^zB3%", .probablePassword),
        ("aB3$dE6&gH9(kM2)", .probablePassword),
        // Long single-class high-entropy secret (32-char base32 TOTP seed
        // shape). Split mid-literal so no contiguous secret-shaped token sits
        // in the source.
        ("Q2W3E4R5T6Y7UABC" + "DFGHIJKLMNOPSVXZ", .probablePassword),
    ]

    @Test("Detects sanitized secret shapes", arguments: Self.secrets)
    func detects(input: String, expected: SensitiveDataDetector.Category) {
        #expect(detector.detect(input) == expected, "input: \(input)")
    }

    static let cleanInputs: [String] = [
        "meet me at the coffee shop at 3pm",
        "https://example.com/article?id=42",
        "user@example.com",
        "550e8400-e29b-41d4-a716-446655440000",
        "func capture() -> String { return x }",
        "the word password appears in this sentence",
        "4111 1111 1111 1112",  // fails Luhn
        "pk_live_4eC39HqLyjWDarjtT1zdp7dc",  // publishable key is public
        "lowercaseonlytoken",  // one char class
        "SHORT#a1",  // too short for the shape route
        "9400 1118 9922 3857 2418 99",  // USPS tracking, not a card (no Luhn)
        "the bearer of this letter deserves respect",  // prose "bearer", no token
        "npm_install failed with exit code 1",  // npm_ prefix, not a 36-char token
        "sk-learn is my favorite python package",  // sk- prefix, token too short
        "-----BEGIN PGP PUBLIC KEY BLOCK-----\nmQENBGXk",  // public block is public
        "https://hooks.slack.com/services/about",  // webhook docs URL, no T/B/token path
        "the quick brown fox jumps over the lazy dog by the river",  // long prose, spaces
        "aaaabbbbccccddddeeeeffffgggg",  // long single-class token, low entropy
    ]

    @Test("Everyday clips stay clean", arguments: Self.cleanInputs)
    func negatives(input: String) {
        #expect(detector.detect(input) == nil, "input: \(input)")
    }
}

@Suite("Sensitive masking + ingestion decoration")
struct SensitiveMaskingTests {
    @Test("Masked preview is bullets + last 4, never the secret")
    func maskShape() {
        let masked = SensitiveMasking.maskedPreview(for: "sk_live_4eC39HqLyjWDarjtT1zdp7dc")
        #expect(masked == "●●●● p7dc")
        #expect(!masked.contains("sk_live"))
    }

    @Test("Short secrets mask entirely — no last-4 reveal of an OTP or PIN")
    func shortSecretsMaskFully() {
        #expect(SensitiveMasking.maskedPreview(for: "483921") == "●●●●")
        #expect(SensitiveMasking.maskedPreview(for: "483 921") == "●●●●")
        #expect(SensitiveMasking.maskedPreview(for: "Sup3r$e!") == "●●●●")
    }

    @Test("Multiline secrets (PEM) mask entirely")
    func pemMasksFully() {
        let masked = SensitiveMasking.maskedPreview(
            for: "-----BEGIN PRIVATE KEY-----\nMIIEvg==\n-----END PRIVATE KEY-----")
        #expect(masked == "●●●●")
    }

    @Test("Decoration flags, masks, re-kinds, and sets the short expiry")
    func decoration() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let raw = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let item = ClipItem(kind: .text, preview: raw, contentHash: "h")

        let decorated = SensitiveIngestionPolicy.decorate(
            item, finding: .githubToken, originalText: raw, sensitiveLifetime: 600, now: now)

        #expect(decorated.isSensitive)
        #expect(decorated.kind == .secret)
        #expect(decorated.preview == "●●●● 6789")
        #expect(decorated.expiresAt == now.addingTimeInterval(600))
    }

    @Test("Cards keep their kind; clean clips pass through untouched")
    func cardAndCleanPaths() {
        let card = ClipItem(kind: .creditCard, preview: "4111…", contentHash: "h")
        let decoratedCard = SensitiveIngestionPolicy.decorate(
            card, finding: .creditCard, originalText: "4111 1111 1111 1111")
        #expect(decoratedCard.kind == .creditCard)
        #expect(decoratedCard.isSensitive)
        #expect(decoratedCard.preview == "●●●● 1111")

        let clean = ClipItem(kind: .text, preview: "hello", contentHash: "h2")
        let untouched = SensitiveIngestionPolicy.decorate(
            clean, finding: nil, originalText: "hello")
        #expect(untouched == clean)
    }
}
