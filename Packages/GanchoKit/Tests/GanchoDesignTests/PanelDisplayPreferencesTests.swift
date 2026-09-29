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

    @Test("Text size is a scale around the standard styles")
    func textScaleOrdering() {
        #expect(PanelTextSize.small.scale < 1)
        #expect(PanelTextSize.standard.scale == 1)
        #expect(PanelTextSize.large.scale > 1)
    }

    @Test("Panel text styles mirror the macOS system sizes and keep their hierarchy")
    func textStyleBases() {
        #expect(PanelTextStyle.body.baseSize == 13)
        #expect(PanelTextStyle.headline.baseSize == PanelTextStyle.body.baseSize)
        #expect(PanelTextStyle.headline.defaultWeight == .semibold)
        #expect(PanelTextStyle.body.defaultWeight == .regular)
        #expect(PanelTextStyle.caption.baseSize < PanelTextStyle.callout.baseSize)
        #expect(PanelTextStyle.callout.baseSize < PanelTextStyle.body.baseSize)
        #expect(PanelTextStyle.body.baseSize < PanelTextStyle.title3.baseSize)
        #expect(PanelTextStyle.title3.baseSize < PanelTextStyle.title2.baseSize)
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
