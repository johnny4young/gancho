import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Uses the exact app extension with the minimal AppModel shim, never the
/// real composition root or OS services. This test also compiles at baseline.
@MainActor @Suite("App adapter failure regression")
struct SearchFailureRegressionTests {
    @Test func failedAppStoreReadMustNotBecomeCurrentEmptyResults() async {
        let store = InjectedPanelStore(shouldFail: true)
        let source = AppModel(fullStore: store)
        let panel = PanelSearchModel(source: source)
        panel.query = "["
        panel.mode = .regex
        await panel.refresh()
        #expect(!panel.hasCurrentResults, "A failed read was presented as completed empty search")
        #expect(panel.results.isEmpty && panel.selectedItem == nil)
        #expect(
            await store.requests == [
                InjectedPanelStore.Request(
                    query: ClipSearchQuery(text: "[", mode: .regex), limit: 100)
            ])
        #expect(source.milestones == 1)
    }
    @Test func successfulAppStoreEmptyReadRemainsCurrent() async {
        let source = AppModel(fullStore: InjectedPanelStore(shouldFail: false))
        let panel = PanelSearchModel(source: source)
        panel.query = "synthetic"
        await panel.refresh()
        #expect(panel.hasCurrentResults && panel.results.isEmpty)
        #expect(source.milestones == 1)
    }
}
