import Foundation
import Testing

@testable import GanchoAI

@Suite("Board suggester — semantic k-NN vote")
struct BoardSuggesterTests {
    // Stable board ids (low/high so tie-break order is predictable).
    private let dev = UUID(uuidString: "00000000-0000-4000-A000-000000000001")!
    private let design = UUID(uuidString: "00000000-0000-4000-A000-000000000002")!
    private let recipes = UUID(uuidString: "00000000-0000-4000-A000-000000000003")!

    @Test("Suggests the board most neighbors already share")
    func clearMajority() {
        let neighbors: [Set<UUID>] = [[dev], [dev], [dev], [], []]
        let vote = BoardSuggester.suggest(neighborBoardIDs: neighbors, candidates: [dev, design])
        #expect(vote?.boardID == dev)
        #expect(vote?.confidence == 3.0 / 5.0)
    }

    @Test("Returns nil below the minimum vote count")
    func belowMinVotes() {
        let neighbors: [Set<UUID>] = [[dev], [], [], []]  // 1 vote, minVotes 2
        #expect(BoardSuggester.suggest(neighborBoardIDs: neighbors, candidates: [dev]) == nil)
    }

    @Test("Returns nil when no candidate reaches the confidence floor")
    func belowConfidence() {
        // 2 votes but across 10 neighbors → 0.2 < 0.25 default floor.
        let neighbors: [Set<UUID>] = [[dev], [dev]] + Array(repeating: Set<UUID>(), count: 8)
        #expect(BoardSuggester.suggest(neighborBoardIDs: neighbors, candidates: [dev]) == nil)
    }

    @Test("Only candidate boards are eligible — current/system boards excluded")
    func candidatesOnly() {
        // The clip is already in `dev` (not a candidate); `design` has fewer
        // votes but is the only eligible board.
        let neighbors: [Set<UUID>] = [[dev], [dev], [dev], [design], [design]]
        let vote = BoardSuggester.suggest(neighborBoardIDs: neighbors, candidates: [design])
        #expect(vote?.boardID == design)
        #expect(vote?.confidence == 2.0 / 5.0)
    }

    @Test("A neighbor in multiple boards votes for each")
    func multiMembershipNeighbor() {
        let neighbors: [Set<UUID>] = [[dev, design], [dev, design], [dev]]
        let vote = BoardSuggester.suggest(
            neighborBoardIDs: neighbors, candidates: [dev, design], minConfidence: 0.5)
        // dev: 3, design: 2 → dev wins at 1.0.
        #expect(vote?.boardID == dev)
        #expect(vote?.confidence == 1.0)
    }

    @Test("Ties break deterministically on the lowest UUID")
    func deterministicTie() {
        let neighbors: [Set<UUID>] = [[design], [design], [recipes], [recipes]]
        let vote = BoardSuggester.suggest(
            neighborBoardIDs: neighbors, candidates: [design, recipes])
        #expect(vote?.boardID == design)  // design's UUID < recipes'
    }

    @Test("Empty inputs yield no suggestion")
    func emptyInputs() {
        #expect(BoardSuggester.suggest(neighborBoardIDs: [], candidates: [dev]) == nil)
        #expect(BoardSuggester.suggest(neighborBoardIDs: [[dev]], candidates: []) == nil)
    }
}
