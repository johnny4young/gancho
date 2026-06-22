import SwiftUI

extension Color {
    /// `#RGB` / `#RRGGBB` / `#RRGGBBAA` parser for colour clips and swatches;
    /// `nil` for non-hex input.
    public init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
            let value = UInt64(hex, radix: 16)
        else { return nil }
        let shift: UInt64 = hex.count == 8 ? 8 : 0
        self.init(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255)
    }
}
