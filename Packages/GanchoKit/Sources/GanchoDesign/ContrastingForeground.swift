import SwiftUI

/// A readable foreground on an opaque fill, resolved in the same appearance
/// as the background. Fixed white text is illegible on bright accent colors;
/// a brand-green fill takes the brand's dark ink instead of plain black.
public struct ContrastingForeground: ShapeStyle {
    let background: Color

    public init(on background: Color) { self.background = background }

    public func resolve(in environment: EnvironmentValues) -> Color {
        let scheme = environment.colorScheme
        return Color(Self.ink(on: background.resolve(in: environment), scheme: scheme))
    }

    /// The ink for an opaque fill: black or white by contrast, or the brand's
    /// dark ink on the brand green (also when stepped for hover or pressed).
    public static func ink(on fill: Color.Resolved, scheme: ColorScheme) -> Color.Resolved {
        let luminance = Contrast.luminance(fill)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        guard blackContrast >= whiteContrast else {
            return Color.Resolved(colorSpace: .sRGB, red: 1, green: 1, blue: 1)
        }
        let brandInk = GanchoTokens.ColorPair.ink.resolved(scheme)
        guard isBrandGreen(fill, scheme), Contrast.ratio(brandInk, fill) >= Contrast.text else {
            return Color.Resolved(colorSpace: .sRGB, red: 0, green: 0, blue: 0)
        }
        return brandInk
    }

    private static func isBrandGreen(_ color: Color.Resolved, _ scheme: ColorScheme) -> Bool {
        let brand = GanchoTokens.ColorPair.brand.resolved(scheme)
        return abs(hueOf(color) - hueOf(brand)) < 0.02 && color.green > color.red
            && color.green > color.blue
    }

    private static func hueOf(_ color: Color.Resolved) -> Double {
        let (red, green, blue) = (Double(color.red), Double(color.green), Double(color.blue))
        let high = max(red, green, blue)
        let delta = high - min(red, green, blue)
        guard delta > 0 else { return 0 }
        switch high {
        case red: return ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        case green: return ((blue - red) / delta + 2) / 6
        default: return ((red - green) / delta + 4) / 6
        }
    }
}
