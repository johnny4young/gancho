import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Readable accent text")
struct ContrastingForegroundTests {
    @Test(
        "Opaque accent fills retain normal-text contrast in both appearances",
        arguments: [false, true])
    func readableAccents(dark: Bool) {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        let samples: [Color] = [
            Color(.sRGB, red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255),
            Color(.sRGB, red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
            .blue, .purple, .yellow, .orange, .red, .gray, .black, .white
        ]
        for background in samples {
            let foreground = ContrastingForeground(on: background).resolve(in: environment)
                .resolve(in: environment)
            let background = background.resolve(in: environment)
            let first = luminance(foreground)
            let second = luminance(background)
            #expect((max(first, second) + 0.05) / (min(first, second) + 0.05) >= 4.5)
        }
    }

    private func luminance(_ color: Color.Resolved) -> Float {
        0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
    }
}
