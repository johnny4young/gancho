import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum ReadProblem: Error { case storage }
@MainActor private final class SeamReply {
    private var reply: CheckedContinuation<[ClipItem], Error>?
    private var started: CheckedContinuation<Void, Never>?
    func read() async throws -> [ClipItem] {
        try await withCheckedThrowingContinuation {
            reply = $0
            started?.resume()
            started = nil
        }
    }
    func wait() async {
        if reply != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: Result<[ClipItem], Error>) {
        reply?.resume(with: result)
        reply = nil
    }
}

@MainActor private final class SeamSource: PanelSearchSource {
    let isDurable = true
    var calls = 0
    var snippetCalls = 0
    var snippetOperation: () async -> ClipItem? = { nil }
    var operation: (ClipSearchQuery) async throws -> [ClipItem] = { _ in [] }
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] { [] }
    func items(offset: Int, limit: Int) async -> [ClipItem] { [] }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? {
        snippetCalls += 1
        return await snippetOperation()
    }
    func isDeletionPending(_ id: UUID) -> Bool { false }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        (try? await operation(query)) ?? []
    }
    func searchOutcome(_ query: ClipSearchQuery, limit: Int) async -> ClipListSearchOutcome {
        calls += 1
        return await .read { try await operation(query) }
    }
}

/// Injected sources keep app services outside these state and delivery tests.
@MainActor @Suite("Typed clip-list outcomes", .serialized, .timeLimit(.minutes(1)))
struct ClipListSearchOutcomeTests {
    private func model(
        _ source: SeamSource, mode: ClipSearchQuery.Mode = .fuzzy
    ) -> PanelSearchModel {
        let model = PanelSearchModel(source: source)
        model.query = "synthetic"
        model.mode = mode
        return model
    }
    @Test func fuzzyTimeoutIsTerminal() async {
        let source = SeamSource()
        source.operation = { _ in throw ClipSearchError.timedOut }
        let panel = model(source)
        await panel.refresh()
        #expect(panel.searchFailure == .timedOut && !panel.hasCurrentResults)
        #expect(source.calls == 1 && source.snippetCalls == 0)
        #expect(panel.results.isEmpty && panel.selectedItem == nil)
    }
    @Test func regexTimeoutUsesSameTypedPath() async {
        let source = SeamSource()
        source.operation = { _ in throw ClipSearchError.timedOut }
        let panel = model(source, mode: .regex)
        await panel.refresh()
        #expect(panel.searchFailure == .timedOut && !panel.hasCurrentResults)
        #expect(source.calls == 1)
    }
    @Test func invalidPatternIsDistinct() async {
        let source = SeamSource()
        source.operation = { _ in throw ClipSearchError.invalidRegularExpression }
        let panel = model(source, mode: .regex)
        await panel.refresh()
        #expect(panel.searchFailure == .invalidRegularExpression)
        #expect(!panel.hasCurrentResults)
    }
    @Test func failedReadCannotPublishEmptySuccess() async {
        let source = SeamSource()
        source.operation = { _ in throw ReadProblem.storage }
        let panel = model(source)
        await panel.refresh()
        #expect(panel.searchFailure == .readFailed && !panel.hasCurrentResults)
    }
    @Test func realEmptySuccessAndRecovery() async {
        let source = SeamSource()
        let panel = model(source)
        source.operation = { _ in throw ReadProblem.storage }
        await panel.refresh()
        #expect(panel.searchFailure == .readFailed)
        source.operation = { _ in [] }
        await panel.refresh()
        #expect(panel.searchFailure == nil && panel.hasCurrentResults && panel.results.isEmpty)
        let item = ClipItem(preview: "synthetic recovery")
        source.operation = { _ in [item] }
        await panel.refresh()
        #expect(panel.results.map(\.id) == [item.id] && panel.hasCurrentResults)
    }
    @Test func explicitProviderCancellation() async {
        let source = SeamSource()
        source.operation = { _ in throw CancellationError() }
        let panel = model(source)
        await panel.refresh()
        #expect(panel.searchFailure == .cancelled && !panel.hasCurrentResults)
    }
    @Test func lateOldTimeoutCannotReplaceNewResult() async {
        let source = SeamSource()
        let reply = SeamReply()
        let panel = model(source)
        source.operation = { _ in try await reply.read() }
        let old = Task { await panel.refresh() }
        await reply.wait()
        let item = ClipItem(preview: "synthetic newer result")
        panel.query = "newer"
        source.operation = { _ in [item] }
        await panel.refresh()
        reply.finish(.failure(ClipSearchError.timedOut))
        await old.value
        #expect(panel.searchFailure == nil && panel.results.map(\.id) == [item.id])
    }
    @Test func pasteDoesNotRetryTerminalFailure() async {
        let source = SeamSource()
        source.operation = { _ in throw ClipSearchError.timedOut }
        let panel = model(source)
        let target = await panel.resolvePasteTarget(includingSnippet: true)
        #expect(target == nil && source.calls == 1 && panel.searchFailure == .timedOut)
    }
    @Test func ignoredTaskCancellationCannotPublishSuccess() async {
        let source = SeamSource()
        let reply = SeamReply()
        let panel = model(source)
        source.operation = { _ in try await reply.read() }
        let pending = Task { await panel.refresh() }
        await reply.wait()
        pending.cancel()
        reply.finish(.success([ClipItem(preview: "synthetic cancelled")]))
        await pending.value
        #expect(panel.searchFailure == .cancelled && !panel.hasCurrentResults)
        #expect(panel.results.isEmpty)
    }
    @Test func cancellationDuringSnippetLookupIsTerminal() async {
        let source = SeamSource()
        let reply = SeamReply()
        let panel = model(source)
        source.snippetOperation = { (try? await reply.read())?.first }
        let pending = Task { await panel.refresh() }
        await reply.wait()
        pending.cancel()
        reply.finish(.success([]))
        await pending.value
        #expect(panel.searchFailure == .cancelled && !panel.hasCurrentResults)
    }
    @Test func failedSearchDoesNotProbeAlternatives() async {
        let source = SeamSource()
        source.operation = { _ in throw ReadProblem.storage }
        let panel = model(source)
        await panel.refresh()
        let alternatives = await panel.probeAlternatives(meaningAvailable: false)
        #expect(alternatives.isEmpty && source.calls == 1)
    }
    @Test func failedAlternativeIsNotReportedAsZeroMatches() async {
        let source = SeamSource()
        source.operation = { query in
            if query.mode == .exact { throw ReadProblem.storage }
            return []
        }
        let panel = model(source)
        let alternatives = await panel.probeAlternatives(meaningAvailable: false)
        #expect(!alternatives.contains { $0.alternative == .mode(.exact) })
        #expect(alternatives.contains { $0.alternative == .mode(.regex) && $0.total == 0 })
    }
    @Test func historyFailureAndEmptySuccessStayDistinct() async {
        let source = SeamSource()
        let history = HistoryListViewModel(source: source)
        history.query = "synthetic"
        source.operation = { _ in throw ReadProblem.storage }
        await history.search()
        #expect(history.searchFailure == .readFailed && history.captures.isEmpty)
        #expect(!history.isSearching)
        source.operation = { _ in [] }
        await history.search()
        #expect(history.searchFailure == nil && history.captures.isEmpty && !history.isSearching)
    }
    @Test func changedQueriesArePendingBeforeTheirDebouncedReadStarts() async {
        let source = SeamSource()
        let panel = model(source)
        await panel.refresh()
        #expect(!panel.isSearching && panel.hasCurrentResults)
        panel.query = "synthetic pending query"
        #expect(panel.isSearching && !panel.hasCurrentResults)
        let history = HistoryListViewModel(source: source)
        await history.search()
        history.query = "synthetic pending query"
        #expect(history.isSearching && history.searchFailure == nil)
    }
    @Test func historyPreservesExplicitTimeoutAndCancellation() async {
        let source = SeamSource()
        let history = HistoryListViewModel(source: source)
        history.query = "synthetic"
        source.operation = { _ in throw ClipSearchError.timedOut }
        await history.search()
        #expect(history.searchFailure == .timedOut)
        source.operation = { _ in throw CancellationError() }
        await history.search()
        #expect(history.searchFailure == .cancelled)
    }
    @Test func oldHistoryFailureCannotClearNewerResultOrSpinner() async {
        let source = SeamSource()
        let history = HistoryListViewModel(source: source)
        let oldReply = SeamReply()
        let newReply = SeamReply()
        history.query = "old"
        source.operation = { _ in try await oldReply.read() }
        let old = Task { await history.search() }
        await oldReply.wait()
        history.query = "new"
        source.operation = { _ in try await newReply.read() }
        let newer = Task { await history.search() }
        await newReply.wait()
        #expect(history.isSearching)
        oldReply.finish(.failure(ClipSearchError.timedOut))
        await old.value
        #expect(history.isSearching && history.searchFailure == nil)
        let item = ClipItem(preview: "synthetic current history")
        newReply.finish(.success([item]))
        await newer.value
        #expect(history.captures.map(\.id) == [item.id] && !history.isSearching)
    }
    @Test func cancelledHistoryCannotPublishIgnoredProviderSuccess() async {
        let source = SeamSource()
        let history = HistoryListViewModel(source: source)
        let reply = SeamReply()
        history.query = "synthetic"
        source.operation = { _ in try await reply.read() }
        let pending = Task { await history.search() }
        await reply.wait()
        pending.cancel()
        reply.finish(.success([ClipItem(preview: "synthetic ignored cancellation")]))
        await pending.value
        #expect(history.searchFailure == .cancelled && history.captures.isEmpty)
        #expect(!history.isSearching)
    }
}
