#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import GanchoDesign

    @Suite("Hex color previews")
    @MainActor
    struct ColorHexTests {
        @Test("Eight-digit color previews preserve their alpha channel")
        func alphaChannel() throws {
            let color = try #require(Color(hexString: "#00808080"))
            let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
            #expect(abs(rgb.greenComponent - 128.0 / 255) < 0.01)
            #expect(abs(rgb.alphaComponent - 128.0 / 255) < 0.01)
            let transparent = try #require(Color(hexString: "#00808000"))
            #expect(NSColor(transparent).alphaComponent == 0)
        }

        @Test("Short and six-digit colors stay opaque", arguments: ["#080", "#008080"])
        func opaqueFormats(value: String) throws {
            let color = try #require(Color(hexString: value))
            #expect(NSColor(color).alphaComponent == 1)
        }

        @Test(
            "Malformed colors are rejected", arguments: ["#12", "#12345G", "123456", "#123456789"])
        func malformed(value: String) {
            #expect(Color(hexString: value) == nil)
        }
    }
#endif
