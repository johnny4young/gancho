import CoreGraphics
import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Panel display preferences")
struct PanelDisplayPreferencesTests {
    @Test("Text size resolves unknown or missing values to Standard")
    func textSizeResolution() {
        #expect(PanelTextSize.resolved(nil) == .standard)
        #expect(PanelTextSize.resolved("future-value") == .standard)
        #expect(PanelTextSize.resolved("small") == .small)
        #expect(PanelTextSize.resolved("large") == .large)
    }

    @Test("Text size preserves semantic Dynamic Type ordering")
    func semanticTextScale() {
        #expect(PanelTextSize.small.dynamicTypeSize == .medium)
        #expect(PanelTextSize.standard.dynamicTypeSize == .large)
        #expect(PanelTextSize.large.dynamicTypeSize == .xLarge)
    }

    @Test("Panel presets grow monotonically from Compact to Large")
    func panelPresetOrdering() {
        let compact = PanelSizePreset.compact.contentSize
        let standard = PanelSizePreset.standard.contentSize
        let large = PanelSizePreset.large.contentSize

        #expect(compact.width < standard.width)
        #expect(standard.width < large.width)
        #expect(compact.height < standard.height)
        #expect(standard.height < large.height)
        #expect(compact == CGSize(width: 760, height: 480))
    }
}
