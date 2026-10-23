import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class AlternativesSource: PanelSearchSource, MeaningSearchSource {
    var isDurable = true
    var byMode: [ClipSearchQuery.Mode: [ClipItem]] = [:]
    var outsideBoard: [ClipItem] = []
    var related: [ClipItem] = []
    var pending: Set<UUID> = []
    var gate: SearchGate?
    private(set) var queries: [ClipSearchQuery] = []

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        queries.append(query)
        if let gate {
            self.gate = nil
            await gate.hold()
        }
        return query.boardID == nil && !outsideBoard.isEmpty
            ? outsideBoard : byMode[query.mode] ?? []
    }
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        MeaningSearchResponse(
            items: related, coverage: SemanticIndexCoverage(eligible: 1, indexed: 1))
    }
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] { [] }
    func items(offset: Int, limit: Int) async -> [ClipItem] { [] }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
    func isDeletionPending(_ id: UUID) -> Bool { pending.contains(id) }
}

@MainActor
@Suite("No results — the other modes, counted", .timeLimit(.minutes(1)))
struct PanelSearchAlternativesTests {
    private func clips(_ n: Int) -> [ClipItem] {
        (0..<n).map { ClipItem(preview: "invoice \($0)") }
    }

    @Test func countsEveryOtherModeInThePanelsOrder() async {
        let source = AlternativesSource()
        source.byMode = [.fuzzy: clips(3), .regex: []]
        source.related = clips(2)
        let model = PanelSearchModel(source: source)
        model.query = "invoice q3 pdf"
        model.searchMode = .exact

        let results = await model.probeAlternatives(meaningAvailable: true)
        #expect(results.map(\.alternative) == [.mode(.fuzzy), .mode(.regex), .mode(.meaning)])
        #expect(results.map(\.total) == [3, 0, 2])
        #expect(results[0].preview.count == 3)
        #expect(PanelAlternativeResult.best(of: results)?.alternative == .mode(.fuzzy))
    }

    @Test func meaningIsSkippedWithoutItsIndexAndBoardsAddAllBoards() async {
        let source = AlternativesSource()
        source.outsideBoard = clips(12)
        let model = PanelSearchModel(source: source)
        model.query = "invoice"
        model.selectedBoardID = UUID()

        let results = await model.probeAlternatives(meaningAvailable: false)
        #expect(results.map(\.alternative) == [.mode(.exact), .mode(.regex), .allBoards])
        #expect(results.last?.total == 12)
        #expect(source.queries.last?.boardID == nil)
        #expect(source.queries.last?.mode == .fuzzy, "All boards keeps the current mode")
    }

    @Test func pendingDeletesAreNotCounted() async {
        let source = AlternativesSource()
        let rows = clips(2)
        source.byMode = [.exact: rows]
        source.pending = [rows[0].id]
        let model = PanelSearchModel(source: source)
        model.query = "invoice"
        let results = await model.probeAlternatives(meaningAvailable: false)
        #expect(results.first { $0.alternative == .mode(.exact) }?.total == 1)
    }

    @Test func bestIsTheMostResultsWithTiesInAFixedOrder() {
        func result(_ alternative: PanelSearchAlternative, _ count: Int) -> PanelAlternativeResult {
            PanelAlternativeResult(alternative: alternative, total: count, preview: [])
        }
        #expect(
            PanelAlternativeResult.best(of: [result(.mode(.regex), 5), result(.mode(.fuzzy), 2)])?
                .alternative == .mode(.regex))
        #expect(
            PanelAlternativeResult.best(of: [
                result(.mode(.regex), 2), result(.allBoards, 2), result(.mode(.meaning), 2)
            ])?.alternative == .mode(.meaning))
        #expect(PanelAlternativeResult.best(of: [result(.mode(.fuzzy), 0)]) == nil)
        #expect(PanelAlternativeResult.best(of: []) == nil)
    }

    @Test func aCancelledProbeReturnsNothing() async {
        let source = AlternativesSource()
        source.byMode = [.exact: clips(1)]
        let gate = SearchGate()
        source.gate = gate
        let model = PanelSearchModel(source: source)
        model.query = "invoice"
        let probe = Task { await model.probeAlternatives(meaningAvailable: false) }
        #expect(await gate.waitUntilEntered())
        probe.cancel()
        await gate.release()
        #expect(await probe.value.isEmpty)
    }

    @Test func applyingAnAlternativeSwitchesModeOrLeavesTheBoard() {
        let model = PanelSearchModel(source: AlternativesSource())
        model.selectedBoardID = UUID()
        model.apply(PanelSearchAlternative.mode(.regex))
        #expect(model.searchMode == .regex)
        model.apply(PanelSearchAlternative.allBoards)
        #expect(model.selectedBoardID == nil)
    }

    @Test func anEmptyQueryHasNoAlternatives() async {
        let model = PanelSearchModel(source: AlternativesSource())
        model.query = "   "
        #expect(await model.probeAlternatives(meaningAvailable: true).isEmpty)
    }
}
