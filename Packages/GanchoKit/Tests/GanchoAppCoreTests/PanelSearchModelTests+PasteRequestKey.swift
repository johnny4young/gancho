import Foundation
import Testing

@testable import GanchoAppCore

extension PanelSearchModelTests {
    @Test func pasteRequestKeysCoalesceOnlyIdenticalEffectiveIntents() {
        let interaction = UUID()
        let enter = PanelSearchModel.PasteRequestKey(
            interaction: interaction, plain: false, includingSnippet: true)
        #expect(
            enter
                == PanelSearchModel.PasteRequestKey(
                    interaction: interaction, plain: false, includingSnippet: true))
        #expect(
            enter
                != PanelSearchModel.PasteRequestKey(
                    interaction: interaction, plain: true, includingSnippet: true))
        #expect(
            enter
                != PanelSearchModel.PasteRequestKey(
                    interaction: interaction, plain: false, includingSnippet: false))
        #expect(
            enter
                != PanelSearchModel.PasteRequestKey(
                    interaction: UUID(), plain: false, includingSnippet: true))
    }
}
