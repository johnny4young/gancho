import GanchoKit
import SwiftUI

extension Color {
    /// `#RGB` / `#RRGGBB` / `#RRGGBBAA` parser for colour clips and swatches;
    /// `nil` for non-hex input.
    public init?(hexString: String) {
        guard hexString.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
            let value = ColorValue.parse(hexString)
        else { return nil }
        self.init(Color.Resolved(value))
    }
}

extension Color.Resolved {
    /// The sRGB colour a colour clip names.
    public init(_ value: ColorValue) {
        let unit = value.unit
        self.init(
            colorSpace: .sRGB, red: Float(unit.red), green: Float(unit.green),
            blue: Float(unit.blue), opacity: Float(unit.alpha))
    }
}
