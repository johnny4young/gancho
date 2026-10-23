import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class TokenSource: PanelSearchSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var searchResults: [ClipItem] = []
    var lastSearchQuery: ClipSearchQuery?
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        lastSearchQuery = query
        return Array(searchResults.prefix(limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
    func isDeletionPending(_ id: UUID) -> Bool { false }
}

@MainActor
@Suite("Panel search model — filter tokens and modes")
struct PanelSearchTokenTests {
    private func items(_ n: Int) -> [ClipItem] {
        (0..<n).map { ClipItem(preview: "item \($0)") }
    }

    private static let parser = SearchTokenParser(candidates: { key in
        switch key {
        case .app: [SearchTokenCandidate(title: "Xcode", value: "com.apple.dt.Xcode")]
        case .device: [SearchTokenCandidate(title: "MacBook Pro", value: "MacBook Pro")]
        default: []
        }
    })

    @Test func aFinishedTokenWordBecomesItsFilterAndLeavesTheText() {
        let model = PanelSearchModel(source: TokenSource())
        model.query = "app:xcode greet"
        model.commitTokens(with: Self.parser)
        #expect(model.selectedSourceAppBundleID == "com.apple.dt.Xcode")
        #expect(model.query == "greet")

        model.query = "greet type:code"
        model.commitTokens(with: Self.parser)
        #expect(model.kindFilter == .all, "the word being typed is never cut off")
        model.query = "greet type:code "
        model.commitTokens(with: Self.parser)
        #expect(model.kindFilter == .code)
        #expect(model.query == "greet ")

        model.query = "tag:work #tag "
        model.commitTokens(with: Self.parser)
        #expect(model.query == "tag:work #tag ", "unknown keys stay text")
    }

    @Test func tabSpellsAKeyThenAppliesTheBestValue() {
        let model = PanelSearchModel(source: TokenSource())
        model.query = "greet dev"
        #expect(model.complete(with: Self.parser))
        #expect(model.query == "greet device:")
        model.query = "greet device:mac"
        #expect(model.complete(with: Self.parser))
        #expect(model.deviceName == "MacBook Pro")
        #expect(model.query == "greet")
        model.query = "greet"
        #expect(!model.complete(with: Self.parser), "nothing to complete lets Tab fall through")
    }

    @Test func removingAChipClearsItsFilter() {
        let model = PanelSearchModel(source: TokenSource())
        model.apply(.device("MacBook Pro"))
        model.apply(.before(Date(timeIntervalSince1970: 0)))
        model.apply(.type(.links))
        #expect(model.hasActiveFilter)
        model.removeFilter(.device)
        model.removeFilter(.before)
        model.removeFilter(.type)
        #expect(!model.hasActiveFilter)
    }

    @Test func deviceAndDateRunTheFilteredSearchAndSaveWithTheFilter() async {
        let source = TokenSource()
        source.recent = items(3)
        source.searchResults = [source.recent[1]]
        let model = PanelSearchModel(source: source)
        let cutoff = Date(timeIntervalSince1970: 1_000)
        model.apply(.device("MacBook Pro"))
        model.apply(.before(cutoff))
        #expect(!model.isGroupedView)
        await model.refresh()
        #expect(source.lastSearchQuery?.deviceName == "MacBook Pro")
        #expect(source.lastSearchQuery?.createdBefore == cutoff)
        #expect(model.results.map(\.id) == [source.recent[1].id])
        let rule = model.savedRule(named: "Mac")
        #expect(rule.deviceName == "MacBook Pro")
        #expect(rule.createdBefore == cutoff)
    }

    @Test func clearFiltersAlsoClearsTokenFilters() {
        let model = PanelSearchModel(source: TokenSource())
        model.apply(.device("MacBook Pro"))
        model.apply(.before(Date(timeIntervalSince1970: 0)))
        model.apply(.type(.code))
        model.apply(.app(bundleID: "com.apple.dt.Xcode"))
        model.selectedBoardID = UUID()
        model.pinnedOnly = true
        model.clearFilters()
        #expect(!model.hasActiveFilter)
        #expect(model.deviceName == nil && model.createdBefore == nil)
    }

    @Test func losingMeaningFallsBackToFuzzy() {
        let model = PanelSearchModel(source: TokenSource())
        model.searchMode = .meaning
        model.meaningAvailabilityChanged(true)
        #expect(model.searchMode == .meaning)
        model.meaningAvailabilityChanged(false)
        #expect(model.searchMode == .fuzzy)
        model.searchMode = .regex
        model.meaningAvailabilityChanged(false)
        #expect(model.searchMode == .regex, "other modes are left alone")
    }
}
