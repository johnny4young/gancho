import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class SuspendedMeaningSource: MeaningSearchSource {
    var requests: [String: CheckedContinuation<MeaningSearchResponse, any Error>] = [:]
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        try await withCheckedThrowingContinuation { requests[query.text] = $0 }
    }
    func finish(_ query: String, items: [ClipItem] = [], incomplete: Bool = false) {
        requests.removeValue(forKey: query)?.resume(
            returning: MeaningSearchResponse(
                items: items,
                coverage: SemanticIndexCoverage(eligible: 2, indexed: incomplete ? 1 : 2)))
    }
}

@Suite("Meaning search request ownership") @MainActor
struct MeaningSearchStateTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        throw MeaningSearchError.unavailable
    }
    @Test func emptyAndRegexNeverRequestEmbeddings() {
        let state = MeaningSearchState()
        let source = SuspendedMeaningSource()
        for query in [ClipSearchQuery(text: "  "), ClipSearchQuery(text: "pattern", mode: .regex)] {
            state.start(query: query, source: source) { $0 }
            #expect(state.status == .idle)
            #expect(source.requests.isEmpty)
        }
    }
    @Test func oldResponseCannotReplaceNewQuery() async throws {
        let state = MeaningSearchState()
        let source = SuspendedMeaningSource()
        var applied: [UUID] = []
        state.start(query: ClipSearchQuery(text: "old"), source: source) {
            applied += $0.map(\.id)
            return $0
        }
        try await waitUntil { source.requests["old"] != nil }
        let item = ClipItem(preview: "Synthetic")
        state.start(query: ClipSearchQuery(text: "new"), source: source) {
            applied += $0.map(\.id)
            return $0
        }
        try await waitUntil { source.requests["new"] != nil }
        source.finish("new", items: [item], incomplete: true)
        try await waitUntil { state.status == .incomplete }
        source.finish("old", items: [ClipItem(preview: "Stale")])
        for _ in 0..<20 { await Task.yield() }
        #expect(applied == [item.id])
        #expect(state.relatedIDs == [item.id])
    }
    @Test(arguments: [false, true])
    func selectionOrClosureCancelsLateApplication(invalidate: Bool) async throws {
        let state = MeaningSearchState()
        let source = SuspendedMeaningSource()
        var applied = false
        state.start(query: ClipSearchQuery(text: "query"), source: source) {
            applied = true
            return $0
        }
        try await waitUntil { source.requests["query"] != nil }
        if invalidate { state.invalidate() } else { state.cancelPending() }
        source.finish("query", items: [ClipItem(preview: "Late")])
        for _ in 0..<20 { await Task.yield() }
        #expect(!applied)
        #expect(state.relatedIDs.isEmpty)
        #expect(state.status == .idle)
    }
    @Test func unavailableCapabilityDoesNotAffectConventionalOwner() {
        let state = MeaningSearchState()
        state.start(query: ClipSearchQuery(text: "query"), source: nil) { $0 }
        #expect(state.status == .unavailable)
        #expect(state.relatedIDs.isEmpty)
    }
}
