import Foundation

/// A history search request. `text` is raw user input — sanitization is the
/// store's job, never the caller's (reliability rule: no input may break
/// the query).
public struct ClipSearchQuery: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// Whole input as one phrase, in order.
        case exact
        /// Every token prefix-matches (type-to-search from the 1st key).
        case fuzzy
        /// Regular expression over content/preview (scan, not FTS).
        case regex
    }

    public var text: String
    public var mode: Mode
    /// Restrict to these kinds (nil = all).
    public var kinds: Set<ClipContentKind>?
    /// Restrict to one source app (bundle ID).
    public var sourceAppBundleID: String?
    /// Restrict by creation date.
    public var dateRange: ClosedRange<Date>?
    /// Restrict to clips that belong to this board (nil = any board).
    public var boardID: UUID?
    /// Restrict to user-marked clips: pinned or assigned to at least one board.
    public var markedOnly: Bool
    /// Restrict to an explicit local id set (nil = any id). Used by curated
    /// context packs so unauthorized rows cannot consume the result limit.
    public var includedIDs: Set<UUID>?
    /// Veto detector-flagged rows in SQL rather than filtering them after the
    /// limit. Normal history search keeps its existing inclusive default.
    public var excludesSensitive: Bool

    public init(
        text: String,
        mode: Mode = .fuzzy,
        kinds: Set<ClipContentKind>? = nil,
        sourceAppBundleID: String? = nil,
        dateRange: ClosedRange<Date>? = nil,
        boardID: UUID? = nil,
        markedOnly: Bool = false,
        includedIDs: Set<UUID>? = nil,
        excludesSensitive: Bool = false
    ) {
        self.text = text
        self.mode = mode
        self.kinds = kinds
        self.sourceAppBundleID = sourceAppBundleID
        self.dateRange = dateRange
        self.boardID = boardID
        self.markedOnly = markedOnly
        self.includedIDs = includedIDs
        self.excludesSensitive = excludesSensitive
    }

    /// Builds the FTS5 MATCH expression. Every token is double-quoted (with
    /// internal quotes doubled), which neutralizes ALL FTS5 operators —
    /// `AND`, `OR`, `*`, `(`, `^`, column filters — so arbitrary input can
    /// never break or subvert the query. Fuzzy adds the prefix star OUTSIDE
    /// the quotes, the only place FTS5 honors it.
    func ftsMatchExpression() -> String? {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }

        switch mode {
        case .exact:
            let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(phrase)\""
        case .fuzzy:
            return
                tokens
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
                .joined(separator: " ")
        case .regex:
            return nil
        }
    }
}

public enum ClipSearchError: Error, Equatable {
    /// The regex mode received an invalid pattern.
    case invalidRegularExpression
}
