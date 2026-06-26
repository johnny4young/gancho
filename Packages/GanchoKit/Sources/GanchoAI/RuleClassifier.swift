import Foundation
import GanchoKit

/// Tier-0 classifier: deterministic, <5ms, zero network,
/// runs on every device — no Apple Intelligence required. Foundation Models
/// (tier 1) builds on top of this; it never replaces it.
///
/// Detection precedence runs structural formats first (JWT, UUID, color,
/// JSON, card, tracking) because they are unambiguous; NSDataDetector kinds
/// (URL, email, phone, address, date) apply only when the match covers the
/// WHOLE string; code heuristics run last before falling back to text.
public struct RuleClassifier: Sendable {
    public init() {}

    public func classify(_ text: String) -> ClipContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if isJWT(trimmed) { return .jwt }
        if UUID(uuidString: trimmed) != nil { return .uuid }
        if isColor(trimmed) { return .color }
        if isJSON(trimmed) { return .json }
        if isCreditCard(trimmed) { return .creditCard }
        if isTrackingNumber(trimmed) { return .trackingNumber }
        if let detected = dataDetectorKind(trimmed) { return detected }
        if CodeLanguageDetector.language(of: trimmed) != nil { return .code }
        return .text
    }

    // MARK: - Detectors

    /// Three base64url segments AND a decodable JSON header containing "alg".
    /// The header requirement keeps version strings like "1.2.3" out.
    private func isJWT(_ text: String) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, segments.allSatisfy(isBase64URL) else { return false }
        guard let headerData = base64URLDecode(String(segments[0])),
            let object = try? JSONSerialization.jsonObject(with: headerData),
            let header = object as? [String: Any]
        else { return false }
        return header["alg"] != nil
    }

    private func isBase64URL(_ segment: Substring) -> Bool {
        !segment.isEmpty
            && segment.allSatisfy {
                $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "="
            }
    }

    private func base64URLDecode(_ segment: String) -> Data? {
        var base64 =
            segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    /// #hex (3/6/8), rgb()/rgba(), hsl()/hsla().
    private func isColor(_ text: String) -> Bool {
        if isHexColor(text) { return true }
        let lowered = text.lowercased()
        guard lowered.hasSuffix(")"),
            let open = lowered.firstIndex(of: "(")
        else { return false }
        let function = String(lowered[..<open])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(function) else { return false }
        let body = lowered[lowered.index(after: open)..<lowered.index(before: lowered.endIndex)]
        let parts = body.split(separator: ",")
        guard (3...4).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            let value = part.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "%", with: "")
            return Double(value) != nil
        }
    }

    /// Requires the leading '#': bare hex runs ("deadbeef", commit SHAs)
    /// are words and hashes far more often than colors.
    private func isHexColor(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let hex = text.dropFirst()
        guard [3, 6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    private func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// 13–19 digits (spaces/dashes allowed) that pass Luhn. The checksum is
    /// what keeps random digit runs and phone numbers out.
    private func isCreditCard(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard (13...19).contains(stripped.count), stripped.allSatisfy(\.isNumber) else {
            return false
        }
        return Luhn.validates(stripped)
    }

    /// Conservative carrier formats only — shapes that cannot be phone
    /// numbers or cards: UPS "1Z…" (18 chars) and USPS 9xx… (20–26 digits).
    /// Plain 10–15 digit runs are deliberately NOT tracking numbers.
    private func isTrackingNumber(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        if compact.hasPrefix("1Z"), compact.count == 18,
            compact.dropFirst(2).allSatisfy({ $0.isNumber || ($0.isLetter && $0.isASCII) })
        {
            return true
        }
        if compact.first == "9", (20...26).contains(compact.count),
            compact.allSatisfy(\.isNumber)
        {
            return true
        }
        return false
    }

    /// URL / email / phone / address / date via NSDataDetector — only when
    /// the match covers the whole string (a link inside a sentence is text).
    private func dataDetectorKind(_ text: String) -> ClipContentKind? {
        let types: NSTextCheckingResult.CheckingType = [
            .link, .phoneNumber, .address, .date,
        ]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: fullRange)
        guard let match = matches.first, match.range == fullRange else { return nil }
        switch match.resultType {
        case .link:
            return match.url?.scheme == "mailto" ? .email : .url
        case .phoneNumber:
            // E.164 caps phone numbers at 15 digits; the system detector is
            // looser and would tag 16-digit runs (failed-Luhn card typos).
            let digits = text.count(where: \.isNumber)
            return digits <= 15 ? .phoneNumber : nil
        case .address:
            return .address
        case .date:
            return .date
        default:
            return nil
        }
    }
}

/// Heuristic code-language detection: cheap keyword/shape scoring, no parsing.
/// The kind is
/// `code`; the language refines previews and syntax-aware actions.
public enum CodeLanguageDetector {
    public enum Language: String, Sendable, Equatable, CaseIterable {
        case swift, python, javascript, sql, shell, html
    }

    /// nil = not recognizably code (prose, identifiers, plain data).
    public static func language(of text: String) -> Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("#!") { return .shell }
        if trimmed.hasPrefix("<") && trimmed.contains(">")
            && trimmed.range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil
        {
            return .html
        }

        let upper = trimmed.uppercased()
        if ["SELECT ", "INSERT ", "UPDATE ", "DELETE FROM ", "CREATE TABLE"].contains(
            where: upper.hasPrefix)
        {
            return .sql
        }

        let scores: [(Language, [String])] = [
            (.swift, ["func ", "let ", "var ", "guard ", "extension ", "@MainActor", "-> "]),
            (.python, ["def ", "import ", "self.", "elif ", "lambda ", "print("]),
            (
                .javascript,
                ["const ", "=> ", "function ", "console.log", "async ", "await ", "let "]
            ),
            (.shell, ["$(", "echo ", "| grep", "&& ", "fi\n", "exit 1"]),
        ]
        var best: (Language, Int)?
        for (language, markers) in scores {
            let hits = markers.count(where: trimmed.contains)
            if hits >= 2, hits > (best?.1 ?? 0) {
                best = (language, hits)
            }
        }
        return best?.0
    }
}
