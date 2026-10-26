import SwiftUI

/// A source app as a letter tile. iOS can't read another app's icon, so the
/// initial of its name stands in, on a colour its name always picks: Safari
/// on the Mac and on the iPad share one.
public struct SourceAppTile: View {
    private let bundleID: String
    private let size: CGFloat

    public init(bundleID: String, size: CGFloat = 14) {
        self.bundleID = bundleID
        self.size = size
    }

    public var body: some View {
        let fill = Self.colorOption(forBundleID: bundleID).color
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fill)
            .overlay {
                Text(verbatim: Self.letter(forBundleID: bundleID))
                    .font(.system(size: size * 0.64, weight: .bold, design: .rounded))
                    .foregroundStyle(ContrastingForeground(on: fill))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The first letter or digit of the app's name, uppercased.
    nonisolated static func letter(forBundleID bundleID: String) -> String {
        let name = SourceApp.fallbackName(forBundleID: bundleID)
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "•" }
        return first.uppercased()
    }

    /// FNV-1a over the name's bytes: `hashValue` changes on every launch.
    nonisolated static func colorOption(forBundleID bundleID: String) -> BoardIdentityColor {
        var hash: UInt32 = 2_166_136_261
        for byte in SourceApp.fallbackName(forBundleID: bundleID).utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        let options = BoardIdentityColor.allCases
        return options[Int(hash % UInt32(options.count))]
    }
}
