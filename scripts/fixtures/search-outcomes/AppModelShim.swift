import Foundation
import GanchoAppCore
import GanchoKit

/// Only the fields used by the real AppModel+PanelSearchSource.swift file.
/// The production composition root is deliberately absent from this target.
@MainActor final class AppModel {
    enum Milestone { case firstSearch }
    struct ReuseController { func isDeletionPending(_ id: UUID) -> Bool { false } }
    let fullStore: InjectedPanelStore?
    let store: any ClipboardStore = InMemoryClipboardStore()
    let reuseController = ReuseController()
    private(set) var milestones = 0
    init(fullStore: InjectedPanelStore?) { self.fullStore = fullStore }
    func recordActivationMilestone(_ milestone: Milestone) { milestones += 1 }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
}

actor InjectedPanelStore: ClipSearching {
    struct Request: Sendable, Equatable {
        let query: ClipSearchQuery
        let limit: Int
    }
    let failure: ClipSearchError?
    private(set) var requests: [Request] = []
    init(shouldFail: Bool) { failure = shouldFail ? .invalidRegularExpression : nil }
    init(failure: ClipSearchError) { self.failure = failure }
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        requests.append(Request(query: query, limit: limit))
        if let failure { throw failure }
        return []
    }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func items(inBoard board: UUID, offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func recentSourceApps(limit: Int) async throws -> [ClipSourceApp] { [] }
    func semanticSearch(
        queryVector: [Float], topK: Int, snippetsOnly: Bool
    ) async throws -> [ClipItem] { [] }
    func items(matching rule: SmartCollectionRule, limit: Int) async throws -> [ClipItem] { [] }
}
