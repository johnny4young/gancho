import ClipboardCore
import Testing

@testable import GanchoAppCore

@Suite("Intelligence summary — Settings' row subtitle")
struct IntelligenceSummaryTests {
    @Test("Splits the headline features into on and off, in order")
    func split() {
        var preferences = IntelligencePreferences()
        #expect(IntelligenceSummary(preferences).off.isEmpty)
        preferences.smartPaste = false
        preferences.semanticSearch = false
        let summary = IntelligenceSummary(preferences)
        #expect(summary.on == [.titles, .screenshots])
        #expect(summary.off == [.meaning, .smartPaste])
    }
}
