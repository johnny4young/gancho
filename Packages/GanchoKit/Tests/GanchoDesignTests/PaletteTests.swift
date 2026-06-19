import Testing

@testable import GanchoDesign

/// The accent-source decision is the testable core of "accent follows the OS
/// Theme color, brand green under Multicolor". macOS writes `AppleAccentColor`
/// to the global domain only when the user picks a specific accent; under
/// "Multicolor" (the default) the key is absent.
@Suite("Palette accent source")
struct PaletteTests {
    @Test("Multicolor (no AppleAccentColor key) falls back to the brand green")
    func multicolorFallsBackToBrand() {
        #expect(GanchoTokens.Palette.accentSource(appleAccentColorKeyPresent: false) == .brand)
    }

    @Test("A specific chosen accent is followed from the system")
    func chosenAccentFollowsSystem() {
        #expect(GanchoTokens.Palette.accentSource(appleAccentColorKeyPresent: true) == .system)
    }
}
