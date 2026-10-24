import SwiftUI

/// WCAG 2.x contrast math on resolved colors, so tokens prove they are legible
/// in the appearance they render in instead of trusting a fixed hex.
public enum Contrast {
    /// Normal text needs 4.5:1 against its background (WCAG 1.4.3).
    public static let text = 4.5
    /// Large text and non-text graphics need 3:1 (WCAG 1.4.3, 1.4.11).
    public static let largeText = 3.0

    public enum Grade: Sendable, Equatable {
        case aa, aaLarge, belowAA
    }

    public static func grade(_ ratio: Double) -> Grade {
        ratio >= text ? .aa : ratio >= largeText ? .aaLarge : .belowAA
    }

    /// One decimal, truncated, so a ratio never reads past a threshold it misses.
    public static func label(_ ratio: Double) -> String {
        String(format: "%.1f : 1", (ratio * 10).rounded(.down) / 10)
    }

    public static func luminance(_ color: Color.Resolved) -> Double {
        let value =
            0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
        return min(1, max(0, value))
    }

    public static func ratio(_ first: Color.Resolved, _ second: Color.Resolved) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Moves `color` toward black (on a light background) or white (on a dark
    /// one) in linear light, keeping its hue, until it reaches `minimum`.
    public static func adjusted(
        _ color: Color.Resolved, against background: Color.Resolved, minimum: Double = text
    ) -> Color.Resolved {
        guard ratio(color, background) < minimum else { return color }
        let darken = luminance(background) > 0.18
        var candidate = color
        for step in 1...50 {
            let amount = Float(step) / 50
            candidate =
                darken
                ? scaled(color, by: 1 - amount)
                : mixedTowardWhite(color, by: amount)
            if ratio(candidate, background) >= minimum { break }
        }
        return candidate
    }

    /// `top` drawn over an opaque `bottom`, blended in display space as the
    /// compositor does.
    public static func composited(
        _ top: Color.Resolved, over bottom: Color.Resolved
    )
        -> Color.Resolved
    {
        let alpha = top.opacity
        func mix(_ upper: Float, _ lower: Float) -> Float { upper * alpha + lower * (1 - alpha) }
        return Color.Resolved(
            colorSpace: .sRGB, red: mix(top.red, bottom.red), green: mix(top.green, bottom.green),
            blue: mix(top.blue, bottom.blue))
    }

    /// The hover/pressed step of a fill: HSL lightness moves `fraction` of the
    /// way toward black (`lighter == false`) or white, in display space, so
    /// the hue survives and any accent gets the same rule.
    public static func stepped(
        _ color: Color.Resolved, by fraction: Double, lighter: Bool
    )
        -> Color.Resolved
    {
        let (hue, saturation, lightness) = hsl(color)
        let target = lighter ? lightness + (1 - lightness) * fraction : lightness * (1 - fraction)
        let (red, green, blue) = rgb(hue: hue, saturation: saturation, lightness: target)
        return Color.Resolved(
            colorSpace: .sRGB, red: Float(red), green: Float(green), blue: Float(blue),
            opacity: color.opacity)
    }

    private static func scaled(_ color: Color.Resolved, by factor: Float) -> Color.Resolved {
        Color.Resolved(
            colorSpace: .sRGBLinear, red: color.linearRed * factor,
            green: color.linearGreen * factor, blue: color.linearBlue * factor,
            opacity: color.opacity)
    }

    private static func mixedTowardWhite(
        _ color: Color.Resolved, by amount: Float
    )
        -> Color.Resolved
    {
        Color.Resolved(
            colorSpace: .sRGBLinear, red: color.linearRed + (1 - color.linearRed) * amount,
            green: color.linearGreen + (1 - color.linearGreen) * amount,
            blue: color.linearBlue + (1 - color.linearBlue) * amount, opacity: color.opacity)
    }

    private static func hsl(_ color: Color.Resolved) -> (Double, Double, Double) {
        let red = Double(color.red)
        let green = Double(color.green)
        let blue = Double(color.blue)
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high != low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue /= 6
        return (hue, saturation, lightness)
    }

    private static func rgb(
        hue: Double, saturation: Double, lightness: Double
    )
        -> (Double, Double, Double)
    {
        guard saturation > 0 else { return (lightness, lightness, lightness) }
        let q =
            lightness < 0.5
            ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ offset: Double) -> Double {
            var t = hue + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (channel(1 / 3), channel(0), channel(-1 / 3))
    }
}
