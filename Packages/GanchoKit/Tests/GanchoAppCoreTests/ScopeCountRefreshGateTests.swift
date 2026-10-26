import Testing

@testable import GanchoAppCore

@Suite("Sidebar counts — recount on reloads, not on keystrokes")
struct ScopeCountRefreshGateTests {
    @Test("An empty query always recounts")
    func emptyRecounts() {
        var gate = ScopeCountRefreshGate()
        let first = gate.shouldRecount(query: "")
        let again = gate.shouldRecount(query: "")
        #expect(first && again)
    }

    @Test("Typing skips; a reload of the same search recounts")
    func reloadDuringASearchRecounts() {
        var gate = ScopeCountRefreshGate()
        let decisions = ["g", "gr", "gr", "gre"].map { gate.shouldRecount(query: $0) }
        #expect(decisions == [false, false, true, false], "the repeat is a clip landing mid-search")
    }
}
