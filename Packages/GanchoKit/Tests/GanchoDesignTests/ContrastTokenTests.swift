import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Contrast tokens — every text-on-fill pair reaches AA")
struct ContrastTokenTests {
    static let appearances: [ColorScheme] = [.light, .dark]

    private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return environment
    }

    private func resolved(_ hex: Int, _ environment: EnvironmentValues) -> Color.Resolved {
        Color(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        ).resolve(in: environment)
    }

    @Test("Brand ink stays AA on the green fill at rest, hover and pressed", arguments: appearances)
    func brandInkOnEveryFillState(scheme: ColorScheme) {
        let environment = environment(scheme)
        let fill = GanchoTokens.ColorPair.brand.resolved(scheme)
        let ink = GanchoTokens.ColorPair.ink.resolved(scheme)
        let lighter = scheme == .dark
        for fraction in [0, ButtonStates.hoverStep, ButtonStates.pressedStep] {
            let state = Contrast.stepped(fill, by: fraction, lighter: lighter)
            #expect(Contrast.ratio(ink, state) >= Contrast.text, "step \(fraction)")
        }
    }

    @Test("Green fills, also stepped, take the brand ink instead of black", arguments: appearances)
    func greenFillUsesBrandInk(scheme: ColorScheme) {
        let brand = GanchoTokens.ColorPair.brand.resolved(scheme)
        for fraction in [0, ButtonStates.hoverStep, ButtonStates.pressedStep] {
            let fill = Contrast.stepped(brand, by: fraction, lighter: scheme == .dark)
            let ink = ContrastingForeground.ink(on: fill, scheme: scheme)
            #expect(ink == GanchoTokens.ColorPair.ink.resolved(scheme), "step \(fraction)")
        }
    }

    @Test("Brand text green reads on white, the grey card and its tint")
    func brandTextOnLightSurfaces() {
        let environment = environment(.light)
        let text = GanchoTokens.ColorPair.text.resolved(.light)
        for surface in [0xFFFFFF, 0xF5F5F7, 0xF2F2F3] {
            #expect(Contrast.ratio(text, resolved(surface, environment)) >= Contrast.text)
        }
        let tint = GanchoTokens.ColorPair.tint.resolved(.light)
        #expect(Contrast.ratio(text, tint) >= Contrast.text)
    }

    @Test("Brand text and tint read in dark")
    func brandTextOnDarkSurfaces() {
        let environment = environment(.dark)
        let text = GanchoTokens.ColorPair.text.resolved(.dark)
        for surface in [0x1C1C1E, 0x2C2C2E] {
            #expect(Contrast.ratio(text, resolved(surface, environment)) >= Contrast.text)
        }
        #expect(
            Contrast.ratio(text, GanchoTokens.ColorPair.tint.resolved(.dark)) >= Contrast.text)
    }

    @MainActor @Test("Danger reads as text on its surfaces", arguments: appearances)
    func dangerText(scheme: ColorScheme) {
        let environment = environment(scheme)
        let danger = GanchoTokens.Palette.danger.resolve(in: environment)
        let surfaces = scheme == .dark ? [0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xF5F5F7]
        for surface in surfaces {
            #expect(Contrast.ratio(danger, resolved(surface, environment)) >= Contrast.text)
        }
    }

    @Test(
        "Any system accent is darkened or lightened until it reads as text",
        arguments: [0x007AFF, 0xFF9500, 0xFFCC00, 0xAF52DE, 0xFF2D55, 0x8E8E93, 0x34C759])
    func adjustedAccentsReachAA(hex: Int) {
        for scheme in Self.appearances {
            let environment = environment(scheme)
            let surface = resolved(scheme == .dark ? 0x2C2C2E : 0xF2F2F3, environment)
            let ink = Contrast.adjusted(resolved(hex, environment), against: surface)
            #expect(Contrast.ratio(ink, surface) >= Contrast.text, "\(scheme)")
        }
    }

    @Test("A colour that already passes is left untouched")
    func passingColourIsUnchanged() {
        let environment = environment(.light)
        let black = resolved(0x000000, environment)
        #expect(Contrast.adjusted(black, against: resolved(0xFFFFFF, environment)) == black)
    }

    @Test("Non-green fills keep black or white ink", arguments: [0x007AFF, 0xFFCC00, 0x1D1D1F])
    func otherFillsUseBlackOrWhite(hex: Int) {
        let fill = resolved(hex, environment(.light))
        let ink = ContrastingForeground.ink(on: fill, scheme: .light)
        #expect(ink != GanchoTokens.ColorPair.ink.resolved(.light))
        #expect(Contrast.ratio(ink, fill) >= Contrast.text)
    }

    @Test("Stepping keeps the hue and moves lightness the requested way")
    func steppingDirection() {
        let environment = environment(.light)
        let brand = resolved(0x34C759, environment)
        let darker = Contrast.stepped(brand, by: 0.16, lighter: false)
        let lighter = Contrast.stepped(brand, by: 0.16, lighter: true)
        #expect(Contrast.luminance(darker) < Contrast.luminance(brand))
        #expect(Contrast.luminance(lighter) > Contrast.luminance(brand))
        #expect(darker.green > darker.red && darker.green > darker.blue)
    }
}
