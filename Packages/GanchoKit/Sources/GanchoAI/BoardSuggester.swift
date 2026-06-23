import Foundation

/// The board a clip most likely belongs to, plus how strongly the neighborhood
/// agreed (the share of nearby clips already filed there).
public struct BoardVote: Sendable, Equatable {
    public let boardID: UUID
    /// 0…1 — the fraction of the clip's semantic neighbors that share this board.
    public let confidence: Double

    public init(boardID: UUID, confidence: Double) {
        self.boardID = boardID
        self.confidence = confidence
    }
}

/// Suggests which existing board a clip belongs to by a semantic k-nearest-
/// neighbors vote: embed the clip, find its closest clips, and pick the board
/// most of them are already filed in. Pure and deterministic so the policy is
/// unit-tested once — the embedding + neighbor retrieval (the I/O) is the app
/// layer's job, and only the resulting board memberships are passed in here.
///
/// Why neighbors instead of classifying board NAMES: this learns from how the
/// user has actually filed similar clips, works without Apple Intelligence, and
/// stays silent (returns nil) for a brand-new board with no members yet — it
/// never invents a home from a name alone.
public enum BoardSuggester {
    /// - Parameters:
    ///   - neighborBoardIDs: for each semantic neighbor (any order), the set of
    ///     boards it belongs to.
    ///   - candidates: the boards eligible to be suggested — typically the user
    ///     boards the clip is NOT already in (the caller excludes system boards
    ///     like Favorites and the clip's current boards).
    ///   - minVotes: the winning board must be shared by at least this many
    ///     neighbors (guards against a single coincidental match).
    ///   - minConfidence: the winner's share of ALL neighbors must reach this
    ///     (guards against a scattered neighborhood with no real consensus).
    /// - Returns: the best candidate board and its confidence, or nil when no
    ///   candidate clears both bars. Ties break on the smallest UUID so the
    ///   result is deterministic.
    public static func suggest(
        neighborBoardIDs: [Set<UUID>],
        candidates: Set<UUID>,
        minVotes: Int = 2,
        minConfidence: Double = 0.25
    ) -> BoardVote? {
        guard !neighborBoardIDs.isEmpty, !candidates.isEmpty else { return nil }

        var votes: [UUID: Int] = [:]
        for boards in neighborBoardIDs {
            for board in boards where candidates.contains(board) {
                votes[board, default: 0] += 1
            }
        }
        guard let topCount = votes.values.max() else { return nil }
        // Deterministic tie-break: lowest UUID among the boards with the top count.
        guard
            let winner = votes.filter({ $0.value == topCount }).keys
                .sorted(by: { $0.uuidString < $1.uuidString }).first
        else { return nil }

        let confidence = Double(topCount) / Double(neighborBoardIDs.count)
        guard topCount >= minVotes, confidence >= minConfidence else { return nil }
        return BoardVote(boardID: winner, confidence: confidence)
    }
}
