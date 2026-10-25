import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor @Suite("Actual Mac adapter outcome mapping")
struct AppAdapterOutcomeTests {
    @Test(arguments: [ClipSearchError.invalidRegularExpression, .readFailed])
    func theActualExtensionPreservesEveryTerminalFailure(_ failure: ClipSearchError) async {
        let store = InjectedPanelStore(failure: failure)
        let source = AppModel(fullStore: store)
        let query = ClipSearchQuery(text: "synthetic", mode: .regex, metadataOnly: true)
        let outcome = await source.searchOutcome(query, limit: 17)
        guard case .failure(let actual) = outcome else {
            Issue.record("App adapter converted failure to success")
            return
        }
        #expect(actual == failure)
        #expect(await store.requests == [InjectedPanelStore.Request(query: query, limit: 17)])
        #expect(source.milestones == 1)
    }
    @Test func cancellationRemainsExplicitWithoutADurableStore() async {
        let source = AppModel(fullStore: nil)
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await source.searchOutcome(ClipSearchQuery(text: "synthetic"), limit: 17)
        }
        let outcome = await request.value
        guard case .cancelled = outcome else {
            Issue.record("Cancelled app read was not reported as cancelled")
            return
        }
        #expect(source.milestones == 0)
    }
}
