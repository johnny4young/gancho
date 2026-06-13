import Foundation

/// Pure text transforms applied AT PASTE TIME (the stored clip is never
/// mutated). Exposed in the panel's "Paste as…" menu and as intents.
public enum PasteTransform: String, Sendable, CaseIterable, Codable {
    case plainText
    case lowercase
    case uppercase
    case trimmed
    case singleLine

    /// English titles; UI localizes via catalog keys.
    public var title: String {
        switch self {
        case .plainText: "Plain text"
        case .lowercase: "lowercase"
        case .uppercase: "UPPERCASE"
        case .trimmed: "Trimmed"
        case .singleLine: "Single line"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .plainText: text
        case .lowercase: text.lowercased()
        case .uppercase: text.uppercased()
        case .trimmed: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .singleLine:
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}
