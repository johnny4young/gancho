import GanchoKit
import SwiftUI

/// A clip's leading tile. Neutral with a line glyph, except where the content
/// is the picture: a colour is its swatch, an image its thumbnail, and a
/// protected clip with a lifetime is the ring that counts it down. Rows, cards
/// and the menu-bar menu share it.
public struct ClipTile: View {
    let item: ClipItem
    let size: CGFloat
    /// The caller hides every preview (Private Mode, screen sharing).
    let hidden: Bool
    let thumbnail: Image?
    let countdown: Countdown?

    public init(
        item: ClipItem, size: CGFloat, previewsHidden: Bool, thumbnail: Image? = nil,
        sensitiveLifetime: TimeInterval? = nil
    ) {
        self.item = item
        self.size = size
        self.hidden = previewsHidden
        self.thumbnail = thumbnail
        self.countdown = Countdown(item: item, lifetime: sensitiveLifetime)
    }

    /// The glyph a kind shows on the neutral tile: outlines only.
    nonisolated public static func symbolName(for kind: ClipContentKind) -> String {
        switch kind {
        case .secret: "lock"
        case .email: "at"
        default: kind.symbolName
        }
    }

    public var body: some View {
        let masked = hidden || ClipSafePresentation.requiresMasking(item)
        let shape = RoundedRectangle(cornerRadius: size * 8 / 34, style: .continuous)
        Group {
            if item.kind == .image, !masked, let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay(
                        shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
            } else if item.kind == .color, !masked, let value = ColorValue.parse(item.preview) {
                shape.fill(Color(Color.Resolved(value)))
                    .overlay(
                        shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
            } else if !hidden, let countdown {
                TimeRing(countdown, lineWidth: max(1.5, size / 17)) { glyph("lock", scale: 0.34) }
            } else {
                shape.fill(GanchoTokens.Palette.controlFill)
                    .overlay { glyph(Self.symbolName(for: item.kind), scale: 0.41) }
            }
        }
        .frame(width: size, height: size)
    }

    private func glyph(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .regular))
            .foregroundStyle(GanchoTokens.Palette.ink2)
    }
}
