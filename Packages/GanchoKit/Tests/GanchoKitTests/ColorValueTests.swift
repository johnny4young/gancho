import Foundation
import Testing

@testable import GanchoKit

@Suite("Color value — one parser and the formats the peek shows")
struct ColorValueTests {
    @Test("#008080 reads as the board's formats, with a precise Swift line")
    func teal() throws {
        let teal = try #require(ColorValue.parse("#008080"))
        #expect(teal.hex == "#008080")
        #expect(teal.rgb == "rgb(0, 128, 128)")
        #expect(teal.hsl == "hsl(180, 100%, 25%)")
        #expect(teal.swift == "Color(red: 0, green: 0.502, blue: 0.502)")
    }

    @Test("Every accepted spelling lands on the same colour")
    func spellings() {
        let orange = ColorValue(red: 255, green: 102, blue: 51)
        #expect(ColorValue.parse("#F63") == orange)
        #expect(ColorValue.parse("#ff6633") == orange)
        #expect(ColorValue.parse(" rgb(255, 102, 51) ") == orange)
        #expect(ColorValue.parse("hsl(15, 100%, 60%)") == orange)
    }

    @Test("8-digit hex is #RRGGBBAA, the order the swatch draws")
    func eightDigitHexIsCSSOrder() throws {
        let half = try #require(ColorValue.parse("#00808080"))
        #expect(half == ColorValue(red: 0, green: 128, blue: 128, alpha: 128))
        #expect(half.hex == "#00808080")
        #expect(half.rgb == "rgba(0, 128, 128, 0.502)")
        #expect(half.hsl == "hsla(180, 100%, 25%, 0.502)")
        #expect(half.swift == "Color(red: 0, green: 0.502, blue: 0.502, opacity: 0.502)")
    }

    @Test("rgba and hsla carry their alpha; out-of-range values are not colours")
    func alphaAndRanges() {
        #expect(ColorValue.parse("rgba(0, 0, 0, 0.5)")?.alpha == 128)
        #expect(ColorValue.parse("hsla(0, 0%, 0%, 1)")?.alpha == 255)
        #expect(ColorValue.parse("rgb(256, 0, 0)") == nil)
        #expect(ColorValue.parse("rgba(0, 0, 0, 2)") == nil)
        #expect(ColorValue.parse("hsl(0, 120%, 50%)") == nil)
        #expect(ColorValue.parse("#12345") == nil)
        #expect(ColorValue.parse("teal") == nil)
        #expect(ColorValue.parse("hsl(nan, 50%, 50%)") == nil, "a non-finite hue must not trap")
        #expect(ColorValue.parse("hsl(inf, 50%, 50%)") == nil)
        #expect(ColorValue.parse("hsla(-inf, 0%, 0%, 1)") == nil)
    }

    @Test("rgb() percentages scale to 0–255, alpha may be a percentage, channels may be decimal")
    func cssPercentagesAndDecimals() {
        #expect(ColorValue.parse("rgb(100%, 50%, 0%)") == ColorValue(red: 255, green: 128, blue: 0))
        #expect(ColorValue.parse("rgba(0, 128, 128, 50%)")?.alpha == 128)
        #expect(ColorValue.parse("hsla(180, 100%, 25%, 100%)")?.alpha == 255)
        #expect(ColorValue.parse("rgb(12.4, 0, 254.6)") == ColorValue(red: 12, green: 0, blue: 255))
        #expect(ColorValue.parse("rgb(101%, 0%, 0%)") == nil)
        #expect(ColorValue.parse("rgba(0, 0, 0, 150%)") == nil)
        #expect(ColorValue.parse("rgb(nan, 0, 0)") == nil)
    }

    @Test("Whole channels drop their decimals in the Swift line")
    func swiftTrimsZeros() {
        #expect(
            ColorValue(red: 255, green: 0, blue: 255).swift == "Color(red: 1, green: 0, blue: 1)")
    }
}
