import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("PanelAmbientTint — legibility vetoes the wash")
struct PanelAmbientTintTests {
    @Test("Off by default, on only when enabled with no accessibility veto")
    func policy() {
        #expect(
            PanelAmbientTint.isShown(
                enabled: true, reduceTransparency: false, increasedContrast: false))
        #expect(
            !PanelAmbientTint.isShown(
                enabled: false, reduceTransparency: false, increasedContrast: false))
        #expect(
            !PanelAmbientTint.isShown(
                enabled: true, reduceTransparency: true, increasedContrast: false))
        #expect(
            !PanelAmbientTint.isShown(
                enabled: true, reduceTransparency: false, increasedContrast: true))
    }

    @Test("An image lends its colour only while its preview is visible")
    func accentVetoes() {
        #expect(
            PanelAmbientTint.usesAccent(kind: .image, isSensitive: false, previewsHidden: false))
        #expect(
            !PanelAmbientTint.usesAccent(kind: .image, isSensitive: true, previewsHidden: false))
        #expect(
            !PanelAmbientTint.usesAccent(kind: .image, isSensitive: false, previewsHidden: true))
        #expect(!PanelAmbientTint.usesAccent(kind: .url, isSensitive: false, previewsHidden: false))
    }

    @Test("The wash peaks at 10 % in light and 7 % in dark")
    func strength() {
        #expect(PanelAmbientTint.opacity(dark: false) == 0.10)
        #expect(PanelAmbientTint.opacity(dark: true) == 0.07)
    }

    @Test("Masked clips and Private Mode get no wash")
    func maskVeto() {
        #expect(PanelAmbientTint.washes(masked: false, privateMode: false))
        #expect(!PanelAmbientTint.washes(masked: true, privateMode: false))
        #expect(!PanelAmbientTint.washes(masked: false, privateMode: true))
    }
}
