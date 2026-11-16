import CoreText
import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Bundled typefaces — registration and weights")
struct GanchoFontsTests {
    private static let weightAxis = NSNumber(value: 0x7767_6874)

    private func resolved(_ font: Font) -> CTFont {
        font.resolve(in: EnvironmentValues().fontResolutionContext).ctFont
    }

    private func width(_ font: CTFont) -> Double {
        let characters = Array("Hamburgefonstiv".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        return CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, nil, glyphs.count)
    }

    @Test("Every family registers from the package bundle", arguments: GanchoFonts.Family.allCases)
    func registers(family: GanchoFonts.Family) {
        GanchoFonts.registerIfNeeded()
        GanchoFonts.registerIfNeeded()
        #expect(GanchoFonts.isAvailable(family))
        let name = "\(family.postScriptPrefix)-Regular"
        let font = CTFontCreateWithName(name as CFString, 13, nil)
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }

    @Test(
        "A weight resolves its own instance of the variable faces",
        arguments: [GanchoType.Role.ui, .data],
        [
            (Font.Weight.light, "Light", 300), (.regular, "Regular", 400), (.medium, "Medium", 500),
            (.semibold, "SemiBold", 600), (.bold, "Bold", 700)
        ])
    func weights(role: GanchoType.Role, expected: (Font.Weight, String, Int)) {
        let font = resolved(GanchoType.font(role, size: 13, weight: expected.0))
        let name = "\(role.family.postScriptPrefix)-\(expected.1)"
        #expect(CTFontCopyPostScriptName(font) as String == name)
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        #expect(variation[Self.weightAxis]?.intValue ?? 400 == expected.2)
    }

    @Test("Heavier interface text is drawn wider, so the weight is really applied")
    func weightChangesTheRenderedFace() {
        let widths = [Font.Weight.light, .regular, .medium, .semibold].map {
            width(resolved(GanchoType.font(.ui, size: 13, weight: $0)))
        }
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 < $1 }, "\(widths)")
    }

    @Test("The serif has one weight and never synthesizes another")
    func serifIsRegularOnly() {
        for weight in [Font.Weight.regular, .semibold, .bold] {
            let font = resolved(GanchoType.font(.title, size: 27, weight: weight))
            #expect(CTFontCopyPostScriptName(font) as String == "InstrumentSerif-Regular")
        }
    }

    @Test("Rounded has no bundled face and stays on the system font")
    func roundedStaysSystem() {
        let font = resolved(GanchoType.font(design: .rounded, size: 13, weight: .regular))
        #expect(!(CTFontCopyPostScriptName(font) as String).hasPrefix("Geist"))
    }

    @Test("A text style keeps the role's face when it follows Dynamic Type")
    func relativeSizesKeepTheFace() {
        let font = resolved(
            GanchoType.font(.data, size: 11, weight: .medium, relativeTo: .caption2))
        #expect(CTFontCopyPostScriptName(font) as String == "GeistMono-Medium")
    }
}
