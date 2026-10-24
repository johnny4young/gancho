import Foundation
import GRDB
import Testing

@testable import GanchoAppCore
@testable import GanchoKit

@MainActor @Suite("Actual iOS history adapter", .serialized)
struct HistorySourceIntegrationTests {
    @Test func realInvalidPatternAndReadFailureStayDistinctFromEmpty() async throws {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = temporary.appendingPathComponent("gancho-search-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        precondition(root.deletingLastPathComponent() == temporary)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root.appendingPathComponent("store"))
        let source = HistoryStoreSource(store: store, full: store)
        let invalid = await source.searchOutcome(
            ClipSearchQuery(text: "[", mode: .regex), limit: 50)
        guard case .failure(let failure) = invalid else {
            Issue.record("Invalid pattern became successful empty results")
            return
        }
        #expect(failure == .invalidRegularExpression)
        let history = HistoryListViewModel(source: source)
        history.query = "synthetic"
        await history.search()
        #expect(history.searchFailure == nil && history.captures.isEmpty)
        try store.writer.close()
        await history.search()
        #expect(history.searchFailure == .readFailed && history.captures.isEmpty)
        #expect(!history.isSearching)
    }
}
