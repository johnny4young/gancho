import Foundation
import GanchoKit

/// Tier-0 classifier (backlog E5.1): deterministic, <5ms, zero network,
/// runs on every device — no Apple Intelligence required. Foundation Models
/// (tier 1) builds on top of this; it never replaces it.
public struct RuleClassifier: Sendable {
    public init() {}

    public func classify(_ text: String) -> ClipContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if isJWT(trimmed) { return .jwt }
        if UUID(uuidString: trimmed) != nil { return .uuid }
        if isHexColor(trimmed) { return .color }
        if isJSON(trimmed) { return .json }
        if let detected = dataDetectorKind(trimmed) { return detected }
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

    private func isHexColor(_ text: String) -> Bool {
        var hex = text
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard [3, 6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    private func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// URL / email / phone via NSDataDetector — only when the match covers
    /// the whole string (a link inside a sentence is still text).
    private func dataDetectorKind(_ text: String) -> ClipContentKind? {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: fullRange)
        guard let match = matches.first, match.range == fullRange else { return nil }
        switch match.resultType {
        case .link:
            return match.url?.scheme == "mailto" ? .email : .url
        case .phoneNumber:
            return .phoneNumber
        default:
            return nil
        }
    }
}
