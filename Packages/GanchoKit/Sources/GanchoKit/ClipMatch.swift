import Foundation

/// What a row marks while a search is showing.
public enum ClipMatch: Hashable, Sendable {
    /// Each word wherever it occurs, ignoring case and accents.
    case words(String)
    /// Every match of a regular expression, read as regex search reads it.
    case pattern(String)

    /// A blank query marks nothing.
    public var isBlank: Bool {
        switch self {
        case .words(let query), .pattern(let query):
            query.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

extension ClipSearchQuery {
    /// The one way a regex query is compiled, so search and its row marks agree.
    public static func regularExpression(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
