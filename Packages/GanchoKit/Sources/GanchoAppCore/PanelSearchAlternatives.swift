import Foundation
import GanchoKit

/// Another way to run a query that found nothing.
public enum PanelSearchAlternative: Hashable, Sendable {
    case mode(PanelSearchMode)
    /// The same query outside the selected board.
    case allBoards

    /// The mode it searches in: its own, or the current one outside the board.
    public func mode(in current: PanelSearchMode) -> PanelSearchMode {
        switch self {
        case .mode(let mode): mode
        case .allBoards: current
        }
    }
}

/// What one alternative would show: its count and the first rows.
public struct PanelAlternativeResult: Sendable, Equatable {
    public let alternative: PanelSearchAlternative
    public let total: Int
    public let preview: [ClipItem]

    public init(alternative: PanelSearchAlternative, total: Int, preview: [ClipItem]) {
        self.alternative = alternative
        self.total = total
        self.preview = preview
    }

    /// Ties go to the gentler change of intent.
    static let tieOrder: [PanelSearchAlternative] = [
        .mode(.fuzzy), .mode(.exact), .mode(.meaning), .allBoards, .mode(.regex)
    ]

    /// The most results wins; nil when every alternative found nothing.
    public static func best(of results: [Self]) -> Self? {
        results.filter { $0.total > 0 }.min { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            let rank = { (result: Self) in tieOrder.firstIndex(of: result.alternative) ?? .max }
            return rank(lhs) < rank(rhs)
        }
    }
}

/// What the list says while nothing matches, and which alternative ↓ takes.
public enum PanelNoMatches {
    public enum Caption: Equatable, Sendable {
        /// A filter alone emptied the list: there is no query to quote back.
        case filter
        case query(String)
        case scoped(query: String, scope: String)
    }

    public static func caption(query: String, scopeName: String?) -> Caption {
        if query.isEmpty { return .filter }
        if let scopeName { return .scoped(query: query, scope: scopeName) }
        return .query(query)
    }

    /// The one washed row: the alternative ↓ applies, nil when none found anything.
    public static func washed(in results: [PanelAlternativeResult]) -> PanelSearchAlternative? {
        PanelAlternativeResult.best(of: results)?.alternative
    }

    /// "Try another word" only when no key and no button leads anywhere.
    public static func suggestsAnotherWord(
        hasActiveFilter: Bool, results: [PanelAlternativeResult]
    ) -> Bool {
        !hasActiveFilter && washed(in: results) == nil
    }
}

extension PanelSearchModel {
    /// Runs the current query once per other mode, and outside the board when
    /// one is selected, in the panel's order. Meaning is asked only when its
    /// index can answer. Returns nothing once cancelled, so a stale probe never lands.
    public func probeAlternatives(
        meaningAvailable: Bool, limit: Int = 100
    ) async -> [PanelAlternativeResult] {
        guard searchFailure == nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        var candidates: [PanelSearchAlternative] = PanelSearchMode.allCases
            .filter { $0 != searchMode && ($0 != .meaning || meaningAvailable) }
            .map(PanelSearchAlternative.mode)
        if selectedBoardID != nil { candidates.append(.allBoards) }
        var results: [PanelAlternativeResult] = []
        for alternative in candidates {
            let found = await items(for: alternative, limit: limit)
            guard !Task.isCancelled, searchFailure == nil else { return [] }
            guard let found else { continue }
            let items = found.filter { !source.isDeletionPending($0.id) }
            results.append(
                PanelAlternativeResult(
                    alternative: alternative, total: items.count, preview: Array(items.prefix(3))))
        }
        return results
    }

    /// Switches to an alternative: its mode, or every board.
    public func apply(_ alternative: PanelSearchAlternative) {
        switch alternative {
        case .mode(let mode): searchMode = mode
        case .allBoards: selectedBoardID = nil
        }
    }

    private func items(for alternative: PanelSearchAlternative, limit: Int) async -> [ClipItem]? {
        var rule = savedRule(named: "")
        if alternative == .allBoards { rule.boardID = nil }
        let mode = alternative.mode(in: searchMode)
        guard mode == .meaning else {
            rule.searchMode = mode.conventional
            switch await source.searchOutcome(rule.query, limit: limit) {
            case .success(let items): return items
            case .failure, .cancelled: return nil
            }
        }
        rule.searchMode = .fuzzy
        let meaning = source as? any MeaningSearchSource
        return try? await meaning?.relatedItems(for: rule.query).items
    }
}
