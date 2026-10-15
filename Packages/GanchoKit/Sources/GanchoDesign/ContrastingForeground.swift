import SwiftUI

/// A readable foreground on an opaque fill, resolved in the same appearance
/// as the background. Fixed white text is illegible on bright accent colors.
public struct ContrastingForeground: ShapeStyle {
    let background: Color

    public init(on background: Color) { self.background = background }

    public func resolve(in environment: EnvironmentValues) -> Color {
        let color = background.resolve(in: environment)
        let luminance = max(
            0,
            min(
                1,
                0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue))
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }
}
