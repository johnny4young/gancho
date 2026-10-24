import GanchoKit
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

    @Test(
        "Status hues become readable ink on their washes",
        arguments: [0xFF9F0A, 0xFF3B30, 0x34C759, 0x007AFF])
    func readableInkOnWashes(hex: Int) {
        for scheme in Self.appearances {
            let environment = environment(scheme)
            let ink = ReadableInk(
                base: Color(
                    .sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                    green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
            ).resolve(in: environment)
            let surfaces = scheme == .dark ? [0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xE6E6E8]
            for surface in surfaces {
                #expect(Contrast.ratio(ink, resolved(surface, environment)) >= Contrast.text)
            }
        }
    }

    @MainActor
    @Test(
        "Kind and status pills stay AA on their own tinted wash",
        arguments: [0.1, 0.12, TypeBadge.washOpacity, 0.15, 0.16])
    func readableInkOnTintedWash(wash: Double) {
        let hues =
            ClipContentKind.allCases.map(GanchoTokens.Palette.kindTint(for:))
            + [
                GanchoTokens.Palette.success, GanchoTokens.Palette.warning,
                GanchoTokens.Palette.danger, GanchoTokens.Palette.indigo
            ]
        for scheme in Self.appearances {
            let environment = environment(scheme)
            let surfaces = scheme == .dark ? [0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xECECEC, 0xE6E6E8]
            for hue in hues {
                let base = hue.resolve(in: environment)
                let ink = ReadableInk(base: hue, onWash: wash).resolve(in: environment)
                var fill = base
                fill.opacity = base.opacity * Float(wash)
                for surface in surfaces {
                    let backdrop = Contrast.composited(fill, over: resolved(surface, environment))
                    #expect(
                        Contrast.ratio(ink, backdrop) >= Contrast.text,
                        "\(base) at \(wash) on \(String(surface, radix: 16)) \(scheme)")
                }
            }
        }
    }

    @Test("The colour hero's ratios: #008080 on white and on the dark panel")
    func colourHeroRatios() throws {
        let teal = Color.Resolved(try #require(ColorValue.parse("#008080")))
        let white = Color.Resolved(try #require(ColorValue.parse("#FFFFFF")))
        let dark = Color.Resolved(try #require(ColorValue.parse("#1C1C1E")))
        let black = Color.Resolved(try #require(ColorValue.parse("#000000")))
        #expect(abs(Contrast.ratio(teal, white) - 4.77) < 0.01)
        #expect(abs(Contrast.ratio(teal, dark) - 3.56) < 0.01)
        #expect(abs(Contrast.ratio(black, white) - 21) < 0.001)
        #expect(Contrast.label(Contrast.ratio(teal, white)) == "4.7 : 1")
        #expect(Contrast.label(Contrast.ratio(teal, dark)) == "3.5 : 1")
    }

    @Test("Grades: AA from 4.5, AA Large from 3, below AA under that; labels never round up")
    func grades() {
        #expect(Contrast.grade(4.5) == .aa)
        #expect(Contrast.grade(4.499) == .aaLarge)
        #expect(Contrast.grade(3) == .aaLarge)
        #expect(Contrast.grade(2.99) == .belowAA)
        #expect(Contrast.label(4.49) == "4.4 : 1")
        #expect(Contrast.label(2.999) == "2.9 : 1")
    }

    @Test("The swatch and the formats read 8-digit hex the same way")
    func hexParity() throws {
        let environment = environment(.light)
        let swatch = try #require(Color(hexString: "#00808080")).resolve(in: environment)
        let formats = Color.Resolved(try #require(ColorValue.parse("#00808080")))
        #expect(abs(swatch.red - formats.red) < 0.001)
        #expect(abs(swatch.green - formats.green) < 0.001)
        #expect(abs(swatch.blue - formats.blue) < 0.001)
        #expect(abs(swatch.opacity - formats.opacity) < 0.001)
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

    @Test("A translucent fill composites over its backdrop")
    func compositing() {
        let environment = environment(.light)
        var white = resolved(0xFFFFFF, environment)
        white.opacity = 0.5
        let mixed = Contrast.composited(white, over: resolved(0x000000, environment))
        #expect(abs(mixed.red - 0.5) < 0.001 && mixed.opacity == 1)
    }

    @Test("Accent text re-adjusted on its hover tint over a dark card reaches AA")
    func inkOnHoverTint() {
        let environment = environment(.dark)
        let card = resolved(0x2C2C2E, environment)
        let blue = resolved(0x0A84FF, environment)
        var tint = blue
        tint.opacity = 0.22
        let backdrop = Contrast.composited(tint, over: card)
        let ink = Contrast.adjusted(blue, against: card)
        #expect(Contrast.ratio(ink, backdrop) < Contrast.text)
        #expect(
            Contrast.ratio(Contrast.adjusted(ink, against: backdrop), backdrop) >= Contrast.text)
    }
}
