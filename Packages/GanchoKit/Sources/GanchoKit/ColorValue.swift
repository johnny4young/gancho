import Foundation

/// One sRGB colour read from a colour clip's text, with the formats the peek's
/// colour hero and the Convert color action both show.
///
/// 8-digit hex is CSS order, `#RRGGBBAA`, matching how the swatch draws it.
public struct ColorValue: Sendable, Equatable {
    public let red: Int
    public let green: Int
    public let blue: Int
    /// 0...255, only when the text carries an alpha.
    public let alpha: Int?

    public init(red: Int, green: Int, blue: Int, alpha: Int? = nil) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`/`rgba()` and `hsl()`/`hsla()`.
    public static func parse(_ text: String) -> ColorValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("#") { return parseHex(String(trimmed.dropFirst())) }
        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return nil }
        let function = String(trimmed[..<open])
        let body = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let alpha = parts.count == 4 ? Self.fraction(parts[3]).flatMap(Self.alphaByte) : nil
        guard parts.count == 3 || alpha != nil else { return nil }
        switch function {
        case "rgb", "rgba":
            let channels = parts.prefix(3).compactMap(Self.channel)
            guard channels.count == 3 else { return nil }
            return ColorValue(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
        case "hsl", "hsla":
            // `Double` reads "nan" and "inf"; a non-finite hue would trap in `Int(_:)`.
            guard let hue = Double(parts[0]), hue.isFinite,
                let saturation = Self.percent(parts[1]), let lightness = Self.percent(parts[2]),
                (0...100).contains(saturation), (0...100).contains(lightness)
            else { return nil }
            let (red, green, blue) = hslToRGB(
                hue: hue, saturation: saturation / 100, lightness: lightness / 100)
            return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
        default:
            return nil
        }
    }

    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", red, green, blue)
        return alpha.map { rgb + String(format: "%02X", $0) } ?? rgb
    }

    public var rgb: String {
        guard let alpha else { return "rgb(\(red), \(green), \(blue))" }
        return "rgba(\(red), \(green), \(blue), \(Self.decimal(Double(alpha) / 255)))"
    }

    public var hsl: String {
        let (hue, saturation, lightness) = hslComponents
        guard let alpha else { return "hsl(\(hue), \(saturation)%, \(lightness)%)" }
        return "hsla(\(hue), \(saturation)%, \(lightness)%, \(Self.decimal(Double(alpha) / 255)))"
    }

    /// SwiftUI's sRGB initializer, three decimals with trailing zeros dropped.
    public var swift: String {
        let channels = [red, green, blue].map { Self.decimal(Double($0) / 255) }
        let rgb = "red: \(channels[0]), green: \(channels[1]), blue: \(channels[2])"
        guard let alpha else { return "Color(\(rgb))" }
        return "Color(\(rgb), opacity: \(Self.decimal(Double(alpha) / 255)))"
    }

    /// 0...1 per channel, for drawing and contrast maths.
    public struct Unit: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double
    }

    public var unit: Unit {
        Unit(
            red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255,
            alpha: Double(alpha ?? 255) / 255)
    }

    // MARK: - Parsing

    private static func parseHex(_ digits: String) -> ColorValue? {
        var hex = digits
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        let shift: UInt64 = hex.count == 8 ? 8 : 0
        return ColorValue(
            red: Int((value >> (16 + shift)) & 0xFF), green: Int((value >> (8 + shift)) & 0xFF),
            blue: Int((value >> shift) & 0xFF), alpha: hex.count == 8 ? Int(value & 0xFF) : nil)
    }

    /// `128` or `50%` (of 255), as CSS reads an rgb() channel.
    private static func channel(_ text: String) -> Int? {
        if let percent = percentage(text) {
            return (0...100).contains(percent) ? Int((percent * 255 / 100).rounded()) : nil
        }
        guard let value = Double(text), (0...255).contains(value) else { return nil }
        return Int(value.rounded())
    }

    /// `0.5` or `50%`.
    private static func fraction(_ text: String) -> Double? {
        percentage(text).map { $0 / 100 } ?? Double(text)
    }

    private static func percent(_ text: String) -> Double? {
        percentage(text) ?? Double(text)
    }

    private static func percentage(_ text: String) -> Double? {
        text.hasSuffix("%") ? Double(text.dropLast()) : nil
    }

    private static func alphaByte(_ fraction: Double) -> Int? {
        (0...1).contains(fraction) ? Int((fraction * 255).rounded()) : nil
    }

    private static func decimal(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func hslToRGB(
        hue: Double, saturation: Double, lightness: Double
    ) -> (Int, Int, Int) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let hueSector =
            (hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let secondary = chroma * (1 - abs(hueSector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double) =
            switch Int(hueSector) {
            case 0: (chroma, secondary, 0)
            case 1: (secondary, chroma, 0)
            case 2: (0, chroma, secondary)
            case 3: (0, secondary, chroma)
            case 4: (secondary, 0, chroma)
            default: (chroma, 0, secondary)
            }
        let match = lightness - chroma / 2
        return (
            Int(((red + match) * 255).rounded()), Int(((green + match) * 255).rounded()),
            Int(((blue + match) * 255).rounded())
        )
    }

    private var hslComponents: (Int, Int, Int) {
        let (red, green, blue) = (unit.red, unit.green, unit.blue)
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        let lightness = (high + low) / 2
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double =
            switch high {
            case red: ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            case green: (blue - red) / delta + 2
            default: (red - green) / delta + 4
            }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (
            Int(hue.rounded()), Int((saturation * 100).rounded()),
            Int((lightness * 100).rounded())
        )
    }
}
