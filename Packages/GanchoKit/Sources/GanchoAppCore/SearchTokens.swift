import Foundation
import GanchoKit

/// A filter typed into the search field as `key:value`.
public enum SearchTokenKey: String, CaseIterable, Sendable {
    case app, type, board, device, before

    /// The filter a key sets, matched against the typed text.
    public var spelling: String { rawValue + ":" }
}

/// One candidate value: what the field shows and what the filter stores.
public struct SearchTokenCandidate: Sendable, Equatable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// A typed token resolved to the filter it sets.
public enum SearchTokenFilter: Sendable, Equatable {
    case app(bundleID: String)
    case type(ClipKindFilter)
    case board(UUID)
    case device(String)
    case before(Date)
}

/// What Tab would complete the last word of the field to.
public enum SearchTokenCompletion: Sendable, Equatable {
    /// The last word starts a key: Tab spells it out.
    case key(SearchTokenKey)
    /// The last word is `key:partial`: Tab applies this value as a filter.
    case value(SearchTokenKey, SearchTokenCandidate)
}

/// Turns `app:`, `type:`, `board:`, `device:` and `before:` words into the
/// panel's filter state. Unknown keys and unmatched values stay search text.
public struct SearchTokenParser: Sendable {
    public var candidates: @Sendable (SearchTokenKey) -> [SearchTokenCandidate]
    public var now: Date
    public var calendar: Calendar

    public init(
        candidates: @escaping @Sendable (SearchTokenKey) -> [SearchTokenCandidate],
        now: Date = .now, calendar: Calendar = .current
    ) {
        self.candidates = candidates
        self.now = now
        self.calendar = calendar
    }

    /// The type vocabulary, in the filter rail's order.
    public static let typeCandidates: [SearchTokenCandidate] = ClipKindFilter.allCases
        .filter { $0 != .all }
        .map { SearchTokenCandidate(title: $0.rawValue, value: $0.rawValue) }

    /// The last whitespace-separated word, which is what completion acts on.
    public static func lastWord(of text: String) -> Substring {
        guard let space = text.lastIndex(where: \.isWhitespace) else { return Substring(text) }
        return text[text.index(after: space)...]
    }

    /// Completions for the last word, best first.
    public func completions(for text: String) -> [SearchTokenCompletion] {
        let word = Self.lastWord(of: text).lowercased()
        guard !word.isEmpty else { return [] }
        if let colon = word.firstIndex(of: ":") {
            guard let key = SearchTokenKey(rawValue: String(word[..<colon])) else { return [] }
            let partial = String(word[word.index(after: colon)...])
            return matches(partial, for: key).map { .value(key, $0) }
        }
        return SearchTokenKey.allCases.filter { $0.rawValue.hasPrefix(word) }.map { .key($0) }
    }

    /// The filter a complete `key:value` word sets, or nil when it stays text.
    public func filter(for word: Substring) -> SearchTokenFilter? {
        guard let colon = word.firstIndex(of: ":"),
            let key = SearchTokenKey(rawValue: word[..<colon].lowercased())
        else { return nil }
        let value = String(word[word.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        if key == .before { return date(before: value).map(SearchTokenFilter.before) }
        guard let candidate = matches(value, for: key).first else { return nil }
        return filter(key, candidate)
    }

    /// The filter a chosen completion sets.
    public func filter(
        _ key: SearchTokenKey, _ candidate: SearchTokenCandidate
    )
        -> SearchTokenFilter?
    {
        switch key {
        case .app: .app(bundleID: candidate.value)
        case .type: ClipKindFilter(rawValue: candidate.value).map(SearchTokenFilter.type)
        case .board: UUID(uuidString: candidate.value).map(SearchTokenFilter.board)
        case .device: .device(candidate.value)
        case .before: date(before: candidate.value).map(SearchTokenFilter.before)
        }
    }

    private func matches(_ partial: String, for key: SearchTokenKey) -> [SearchTokenCandidate] {
        let pool =
            switch key {
            case .type: Self.typeCandidates
            case .before:
                ["today", "yesterday", "7d", "30d"].map {
                    SearchTokenCandidate(title: $0, value: $0)
                }
            default: candidates(key)
            }
        let needle = partial.lowercased()
        guard !needle.isEmpty else { return pool }
        let exact = pool.filter { $0.title.lowercased() == needle }
        return exact
            + pool.filter { $0.title.lowercased().hasPrefix(needle) && !exact.contains($0) }
    }

    /// `today`, `yesterday`, `Nd` (N days ago) or an ISO date (`2026-10-01`),
    /// each meaning "created before the start of that day".
    func date(before value: String) -> Date? {
        let lowered = value.lowercased()
        let today = calendar.startOfDay(for: now)
        switch lowered {
        case "today": return today
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }
        if lowered.hasSuffix("d"), let days = Int(lowered.dropLast()), days > 0 {
            return calendar.date(byAdding: .day, value: -days, to: today)
        }
        let parts = lowered.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
            let date = calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
            calendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: parts[0], month: parts[1], day: parts[2])
        else { return nil }
        return date
    }
}

/// The search field's mode control.
public enum PanelSearchMode: String, CaseIterable, Sendable {
    case exact, fuzzy, regex, meaning

    init(_ mode: ClipSearchQuery.Mode) {
        switch mode {
        case .exact: self = .exact
        case .fuzzy: self = .fuzzy
        case .regex: self = .regex
        }
    }

    /// The store mode behind it; Meaning has none.
    public var conventional: ClipSearchQuery.Mode? {
        switch self {
        case .exact: .exact
        case .fuzzy: .fuzzy
        case .regex: .regex
        case .meaning: nil
        }
    }
}
