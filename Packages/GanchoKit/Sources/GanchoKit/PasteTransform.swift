import CryptoKit
import Foundation

/// Pure, deterministic text transforms applied AT PASTE TIME (the stored clip
/// is never mutated). Exposed in the panel's "Paste as…" menu and the peek /
/// detail "Transform" menus. Deliberately no model dependency: every case
/// works on any hardware, with Apple Intelligence off.
public enum PasteTransform: String, Sendable, CaseIterable, Codable {
    case plainText
    case lowercase
    case uppercase
    case titleCase
    case trimmed
    case singleLine
    case collapseSpaces
    case sortLines
    case dedupeLines
    case urlEncode
    case urlDecode
    case sha256Hex

    /// English titles; UI localizes via catalog keys.
    public var title: String {
        switch self {
        case .plainText: "Plain text"
        case .lowercase: "lowercase"
        case .uppercase: "UPPERCASE"
        case .titleCase: "Title Case"
        case .trimmed: "Trimmed"
        case .singleLine: "Single line"
        case .collapseSpaces: "Collapse spaces"
        case .sortLines: "Sort lines"
        case .dedupeLines: "Dedupe lines"
        case .urlEncode: "URL-encode"
        case .urlDecode: "URL-decode"
        case .sha256Hex: "SHA-256"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .plainText: return text
        case .lowercase: return text.lowercased()
        case .uppercase: return text.uppercased()
        // `capitalized` (not `localizedCapitalized`): the canonical mapping is
        // locale-independent, so the same clip transforms identically on every
        // device — determinism over locale nuance.
        case .titleCase: return text.capitalized
        case .trimmed: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .singleLine:
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        // Collapses runs of spaces/tabs inside each line to one space (also
        // trimming the line's edges); the line structure itself is preserved.
        case .collapseSpaces:
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                        .joined(separator: " ")
                }
                .joined(separator: "\n")
        // Plain lexicographic order (`<`), not locale-aware collation — the
        // same input must sort identically everywhere.
        case .sortLines:
            return text.components(separatedBy: "\n").sorted().joined(separator: "\n")
        // First occurrence wins; order is otherwise preserved. Empty lines
        // dedupe like any other line (the first blank survives).
        case .dedupeLines:
            var seen = Set<String>()
            return text.components(separatedBy: "\n")
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        // RFC 3986 unreserved set: everything else (including &, =, ?, /) is
        // percent-encoded, so the result is safe inside any URL component.
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? text
        // Malformed sequences (a stray "%ZZ") decode to nil — pass the text
        // through unchanged rather than pasting nothing.
        case .urlDecode:
            return text.removingPercentEncoding ?? text
        case .sha256Hex:
            return SHA256.hash(data: Data(text.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
