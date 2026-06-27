import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

/// The 50+ real-world case suite the tier-0 classifier must hold, false
/// positives included. Date/address cases use explicit formats so the suite
/// is locale-independent on CI runners.
@Suite("RuleClassifier — full case suite")
struct RuleClassifierSuiteTests {
    let classifier = RuleClassifier()

    static let cases: [(String, ClipContentKind)] = [
        // URLs (full-string only)
        ("https://example.com", .url),
        ("https://example.com/path?q=1&page=2", .url),
        ("http://sub.domain.example.org:8080/deep/path", .url),
        ("www.example.com", .url),
        ("ftp://files.example.com/archive.zip", .url),
        // Emails
        ("user@example.com", .email),
        ("first.last+tag@sub.example.co", .email),
        ("mailto:support@example.com", .email),
        // Phones
        ("+1 (415) 555-0199", .phoneNumber),
        ("415-555-0199", .phoneNumber),
        ("+44 20 7946 0958", .phoneNumber),
        // Addresses (full string)
        ("1 Infinite Loop, Cupertino, CA 95014", .address),
        ("1600 Pennsylvania Ave NW, Washington, DC 20500", .address),
        // Dates (explicit formats — locale-stable)
        ("2026-06-12", .date),
        ("06/12/2026 3:00 PM", .date),
        ("June 12, 2026", .date),
        // Colors
        ("#FF6B35", .color),
        ("#abc", .color),
        ("#80FF6B35", .color),
        ("rgb(255, 107, 53)", .color),
        ("rgba(255, 107, 53, 0.5)", .color),
        ("hsl(120, 50%, 50%)", .color),
        // JWT
        ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl", .jwt),
        // JSON
        ("{\"name\": \"gancho\", \"v\": 1}", .json),
        ("[1, 2, 3]", .json),
        ("{\"nested\": {\"deep\": [true, null]}}", .json),
        // UUID
        ("550e8400-e29b-41d4-a716-446655440000", .uuid),
        ("F968FC5B-51FC-4D48-B7CF-71BEF867B1B5", .uuid),
        // Credit cards (Luhn-valid)
        ("4111 1111 1111 1111", .creditCard),
        ("4111-1111-1111-1111", .creditCard),
        ("378282246310005", .creditCard),
        ("5555555555554444", .creditCard),
        // Tracking numbers
        ("1Z999AA10123456784", .trackingNumber),
        ("9400 1118 9922 3857 2418 99", .trackingNumber),
        // Code
        ("func capture() -> String { let x = 1; return \"\\(x)\" }", .code),
        ("def main():\n    import sys\n    print(sys.argv)", .code),
        ("const load = async () => { await fetch(url) }", .code),
        ("SELECT id, title FROM clips WHERE kind = 'url';", .code),
        ("#!/bin/sh\necho hello", .code),
        ("<div class=\"row\"><span>hi</span></div>", .code),
        // Plain text (the default)
        ("pick up the dry cleaning on thursday afternoon maybe", .text),
        ("Reunión movida al jueves, avísale al equipo por favor", .text),
        ("the meeting notes are attached below", .text),
        ("x", .text),
        // FALSE POSITIVES — the suite's reason to exist
        ("1.2.3", .text),  // version string is not a JWT
        ("550e8400-e29b-41d4-a716-446655440000.extra.parts", .text),  // UUID-ish is not a JWT
        ("{not json at all", .text),
        ("4111 1111 1111 1112", .text),  // fails Luhn → not a card
        ("123456789012345678901234567", .text),  // 27 digits: too long for card/tracking
        ("read https://example.com later today", .text),  // URL inside prose
        ("call me at 415-555-0199 tomorrow", .text),  // phone inside prose
        ("deadbeef", .text),  // bare hex run without # is a word/hash
        ("the function should return early", .text),  // 'function' alone ≠ code
        ("rgb(300, banana, 12)", .text),  // malformed color args
        ("#GGGGGG", .text),  // not hex digits
    ]

    @Test("Classifies the full suite", arguments: Self.cases)
    func classifies(input: String, expected: ClipContentKind) {
        #expect(classifier.classify(input) == expected, "input: \(input)")
    }

    @Test("Language detection refines code clips")
    func languageDetection() {
        #expect(
            CodeLanguageDetector.language(of: "func a() { let x = 1; guard x > 0 else { return } }")
                == .swift)
        #expect(
            CodeLanguageDetector.language(of: "def f():\n    import os\n    print(os)") == .python)
        #expect(
            CodeLanguageDetector.language(of: "const f = async () => { await g() }") == .javascript)
        #expect(CodeLanguageDetector.language(of: "SELECT * FROM t WHERE id = 1") == .sql)
        #expect(CodeLanguageDetector.language(of: "#!/usr/bin/env bash\necho hi") == .shell)
        #expect(CodeLanguageDetector.language(of: "<p>hello <b>world</b></p>") == .html)
        #expect(CodeLanguageDetector.language(of: "just some prose about functions") == nil)
    }

    @Test("Every kind maps to a distinct presentation symbol")
    func presentationMapping() {
        let symbols = ClipContentKind.allCases.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count, "symbols must be distinct per kind")
        #expect(ClipContentKind.secret.prefersMaskedPreview)
        #expect(ClipContentKind.creditCard.prefersMaskedPreview)
        #expect(!ClipContentKind.url.prefersMaskedPreview)
    }

    @Test("Classification stays under the 5ms p95 budget")
    func latencyBudget() {
        var latencies: [Duration] = []
        for (input, _) in Self.cases {
            let start = ContinuousClock.now
            _ = classifier.classify(input)
            latencies.append(ContinuousClock.now - start)
        }
        let sorted = latencies.sorted()
        let p95 = sorted[Int(0.95 * Double(sorted.count - 1))]
        // CI runs the suite with code coverage on, which instruments every
        // access and inflates wall-clock latency several-fold; relax the budget
        // there so the perf guard stays meaningful locally without flaking on
        // the coverage run.
        let budget: Duration =
            ProcessInfo.processInfo.environment["CI"] == nil
            ? .milliseconds(5) : .milliseconds(50)
        #expect(p95 < budget, "p95 \(p95) blew the \(budget) budget")
    }
}
