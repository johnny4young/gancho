import Foundation
import NaturalLanguage

/// Deterministic, on-device PII redaction for the "Redact PII" Smart Paste
/// action: replace personal-data spans — emails, phone numbers, postal
/// addresses, personal names, US SSNs, and card numbers — with bracketed
/// placeholders, leaving everything else byte-for-byte intact.
///
/// Deterministic on purpose. A redactor is a security tool: it must be reliable
/// and unit-testable, and it must NOT paraphrase the surrounding text the way a
/// generative rewrite would — you want the log or snippet untouched except for
/// the PII. Detection leans on the same on-device primitives the rest of the
/// app uses (`NSDataDetector`, `NLTagger`, the shared `Luhn` check). Zero network.
public enum PIIRedactor {
    private struct Span {
        let range: NSRange
        let placeholder: String
    }

    /// Returns `text` with every detected PII span replaced by a typed
    /// placeholder. Over-redaction is the safe failure mode, so detectors lean
    /// inclusive (e.g. any Luhn-valid 13–19 digit run is treated as a card).
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [Span] = []

        // Structured numbers first, so an SSN/card label wins an exact-overlap
        // tie against NSDataDetector's looser phone match.
        spans.append(
            contentsOf: regexSpans(#"\b\d{3}-\d{2}-\d{4}\b"#, in: text, full: full, as: "[ssn]"))
        for range in regexRanges(#"\b\d(?:[ -]?\d){12,18}\b"#, in: text, full: full) {
            let digits = ns.substring(with: range).filter(\.isNumber)
            if (13...19).contains(digits.count), Luhn.validates(digits) {
                spans.append(Span(range: range, placeholder: "[card]"))
            }
        }

        // Emails (mailto links), phone numbers, postal addresses.
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType([.phoneNumber, .address, .link]).rawValue)
        {
            detector.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                switch match.resultType {
                case .phoneNumber: spans.append(Span(range: match.range, placeholder: "[phone]"))
                case .address: spans.append(Span(range: match.range, placeholder: "[address]"))
                case .link where match.url?.scheme == "mailto":
                    spans.append(Span(range: match.range, placeholder: "[email]"))
                default: break
                }
            }
        }

        // Personal names (joined into whole names); places/orgs are left alone
        // to avoid mangling ordinary prose.
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            if tag == .personalName {
                spans.append(Span(range: NSRange(range, in: text), placeholder: "[name]"))
            }
            return true
        }

        return apply(spans, to: ns)
    }

    /// Replace accepted spans left-to-right, skipping any that overlap one
    /// already taken. Earlier-inserted spans win an exact-position tie, which
    /// is why the structured-number detectors run first.
    private static func apply(_ spans: [Span], to ns: NSString) -> String {
        guard !spans.isEmpty else { return ns as String }
        let ordered = spans.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if left.range.location != right.range.location {
                return left.range.location < right.range.location
            }
            if left.range.length != right.range.length {
                return left.range.length > right.range.length
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        var result = ""
        var cursor = 0
        for span in ordered where span.range.location >= cursor {
            if span.range.location > cursor {
                result += ns.substring(
                    with: NSRange(location: cursor, length: span.range.location - cursor))
            }
            result += span.placeholder
            cursor = span.range.location + span.range.length
        }
        if cursor < ns.length { result += ns.substring(from: cursor) }
        return result
    }

    private static func regexRanges(_ pattern: String, in text: String, full: NSRange) -> [NSRange]
    {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: full).map(\.range)
    }

    private static func regexSpans(
        _ pattern: String, in text: String, full: NSRange, as placeholder: String
    ) -> [Span] {
        regexRanges(pattern, in: text, full: full).map { Span(range: $0, placeholder: placeholder) }
    }
}
