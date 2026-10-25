import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum SyntheticStorageFailure: Error { case unavailable }
private actor InjectedSearcher: ClipSearching {
    struct Request: Equatable, Sendable {
        let query: ClipSearchQuery
        let limit: Int
    }
    enum Reply: Sendable {
        case items([ClipItem])
        case failure(ClipSearchError)
        case storageFailure
    }
    let reply: Reply
    private(set) var requests: [Request] = []
    init(_ reply: Reply) { self.reply = reply }
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        requests.append(Request(query: query, limit: limit))
        switch reply {
        case .items(let items): return items
        case .failure(let failure): throw failure
        case .storageFailure: throw SyntheticStorageFailure.unavailable
        }
    }
    func semanticSearch(
        queryVector: [Float], topK: Int, snippetsOnly: Bool
    ) async throws -> [ClipItem] { [] }
    func items(matching rule: SmartCollectionRule, limit: Int) async throws -> [ClipItem] { [] }
}

@MainActor @Suite("Throwing store search adapter")
struct ClipListSearchReaderTests {
    @Test(arguments: [ClipSearchError.invalidRegularExpression, .readFailed])
    func explicitFailuresSurviveTheStoreBoundary(_ failure: ClipSearchError) async {
        let store = InjectedSearcher(.failure(failure))
        let outcome = await ClipListSearchOutcome.read(
            from: store, query: ClipSearchQuery(text: "synthetic"), limit: 17)
        guard case .failure(let actual) = outcome else {
            Issue.record("Failure became successful empty results")
            return
        }
        #expect(actual == failure)
    }
    @Test func storageDiagnosticsBecomeContentFreeReadFailure() async {
        let outcome = await ClipListSearchOutcome.read(
            from: InjectedSearcher(.storageFailure), query: ClipSearchQuery(text: "synthetic"),
            limit: 17)
        guard case .failure(let failure) = outcome else {
            Issue.record("Read failure became success")
            return
        }
        #expect(failure == .readFailed)
    }
    @Test func successfulEmptyAndAbsentDurableStoreStaySuccessful() async {
        let stores: [(any ClipSearching)?] = [InjectedSearcher(.items([])), nil]
        for store in stores {
            let outcome = await ClipListSearchOutcome.read(
                from: store, query: ClipSearchQuery(text: "synthetic"), limit: 17)
            guard case .success(let items) = outcome else {
                Issue.record("Successful empty read became an error")
                continue
            }
            #expect(items.isEmpty)
        }
    }
    @Test func theExactQueryAndLimitReachTheInjectedStore() async {
        let item = ClipItem(preview: "synthetic result")
        let store = InjectedSearcher(.items([item]))
        let query = ClipSearchQuery(
            text: "synthetic", mode: .regex, kinds: [.text],
            sourceAppBundleID: "invalid.synthetic.app", boardID: UUID(), includedIDs: [item.id],
            excludesSensitive: true, metadataOnly: true)
        let outcome = await ClipListSearchOutcome.read(from: store, query: query, limit: 17)
        guard case .success(let actual) = outcome else {
            Issue.record("Successful result became an error")
            return
        }
        #expect(actual.map(\.id) == [item.id])
        #expect(await store.requests == [InjectedSearcher.Request(query: query, limit: 17)])
    }
    @Test func alreadyCancelledRequestsDoNotInvokeTheStore() async {
        let store = InjectedSearcher(.items([]))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ClipListSearchOutcome.read(
                from: store, query: ClipSearchQuery(text: "synthetic"), limit: 17)
        }
        let outcome = await task.value
        guard case .cancelled = outcome else {
            Issue.record("Cancelled request was not reported as cancelled")
            return
        }
        #expect(await store.requests.isEmpty)
    }
}
