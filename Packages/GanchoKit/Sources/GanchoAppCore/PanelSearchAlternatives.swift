import Foundation
import GanchoKit

/// Another way to run a query that found nothing.
public enum PanelSearchAlternative: Hashable, Sendable {
    case mode(PanelSearchMode)
    /// The same query outside the selected board.
    case allBoards
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

extension PanelSearchModel {
    /// Runs the current query once per other mode, and outside the board when
    /// one is selected, in the panel's order. Meaning is asked only when its
    /// index can answer. Returns nothing once cancelled, so a stale probe never lands.
    public func probeAlternatives(
        meaningAvailable: Bool, limit: Int = 100
    ) async -> [PanelAlternativeResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var candidates: [PanelSearchAlternative] = PanelSearchMode.allCases
            .filter { $0 != searchMode && ($0 != .meaning || meaningAvailable) }
            .map(PanelSearchAlternative.mode)
        if selectedBoardID != nil { candidates.append(.allBoards) }
        var results: [PanelAlternativeResult] = []
        for alternative in candidates {
            let items = await items(for: alternative, limit: limit)
                .filter { !source.isDeletionPending($0.id) }
            guard !Task.isCancelled else { return [] }
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

    private func items(for alternative: PanelSearchAlternative, limit: Int) async -> [ClipItem] {
        var rule = savedRule(named: "")
        let mode: PanelSearchMode
        switch alternative {
        case .mode(let alternativeMode): mode = alternativeMode
        case .allBoards:
            rule.boardID = nil
            mode = searchMode
        }
        guard mode == .meaning else {
            rule.searchMode = mode.conventional
            return await source.search(rule.query, limit: limit)
        }
        rule.searchMode = .fuzzy
        let meaning = source as? any MeaningSearchSource
        return (try? await meaning?.relatedItems(for: rule.query).items) ?? []
    }
}
