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

    @Test("The wash stays faint in both appearances")
    func strength() {
        #expect(PanelAmbientTint.opacity(dark: false) < PanelAmbientTint.opacity(dark: true))
        #expect(PanelAmbientTint.opacity(dark: true) <= 0.25)
    }
}
