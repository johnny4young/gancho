import Foundation
import Testing

@testable import GanchoAI

@Suite("PII redactor — deterministic on-device redaction")
struct PIIRedactorTests {
    @Test("Redacts an email, preserving the surrounding text")
    func email() {
        #expect(
            PIIRedactor.redact("Email me at john@example.com please")
                == "Email me at [email] please")
    }

    @Test("Redacts a phone number")
    func phone() {
        let out = PIIRedactor.redact("Call me at (415) 555-0123 tomorrow")
        #expect(out.contains("[phone]"))
        #expect(!out.contains("555-0123"))
        #expect(out.hasPrefix("Call me at "))
        #expect(out.hasSuffix(" tomorrow"))
    }

    @Test("Redacts a US SSN")
    func ssn() {
        let out = PIIRedactor.redact("SSN 123-45-6789 on file")
        #expect(!out.contains("123-45-6789"))
        #expect(out.contains("[ssn]"))
    }

    @Test("Redacts a Luhn-valid card number with separators")
    func card() {
        let out = PIIRedactor.redact("Card 4111 1111 1111 1111 expires soon")
        #expect(!out.contains("4111"))
        #expect(out.contains("[card]"))
        #expect(out.hasPrefix("Card "))
    }

    @Test("A digit run that fails the Luhn check is left alone")
    func nonLuhnDigitsKept() {
        // 16 digits, not Luhn-valid → not a card, and too long to be a phone.
        #expect(
            PIIRedactor.redact("Order 1234567812345678 shipped") == "Order 1234567812345678 shipped"
        )
    }

    @Test("Text with no PII is returned byte-for-byte")
    func cleanTextUntouched() {
        let clean = "All systems nominal; latency well under budget."
        #expect(PIIRedactor.redact(clean) == clean)
    }

    @Test("Several PII spans in one string are all redacted, text between preserved")
    func multiplePII() {
        let out = PIIRedactor.redact("Reach me at jane@acme.io or 415-555-0123.")
        #expect(out == "Reach me at [email] or [phone].")
    }

    @Test("Empty input stays empty")
    func empty() {
        #expect(PIIRedactor.redact("").isEmpty)
    }

    @Test("A personal name is redacted")
    func personalName() {
        let out = PIIRedactor.redact("My manager Barack Obama approved the request.")
        #expect(out.contains("[name]"))
        #expect(!out.contains("Obama"))
    }
}
