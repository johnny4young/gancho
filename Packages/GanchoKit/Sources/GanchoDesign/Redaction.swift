import SwiftUI

/// Hidden content drawn as bars and hatch: privacy is a shape, not a colour.
public enum Redaction {
    static let headlineWidths: [CGFloat] = [148, 112, 90, 132, 104]
    static let detailWidths: [CGFloat] = [58, 126, 72, 100]

    /// A row's two bar widths. They vary from row to row so a list does not
    /// read as a table, and one seed always gives the same pair.
    public static func widths(seed: Int) -> (headline: CGFloat, detail: CGFloat) {
        let index = Int(seed.magnitude % 20)
        return (
            headlineWidths[index % headlineWidths.count], detailWidths[index % detailWidths.count]
        )
    }

    /// A seed that stays with the clip, so its bars never change while it scrolls.
    public static func seed(for id: UUID) -> Int {
        Int(id.uuid.0) + Int(id.uuid.1)
    }
}

/// One bar standing in for a line of hidden text.
public struct RedactionBar: View {
    public enum Weight: Sendable {
        case title, headline, detail
    }

    let width: CGFloat
    let weight: Weight
    @Environment(\.panelTypeScale) private var scale

    public init(width: CGFloat, weight: Weight = .headline) {
        self.width = width
        self.weight = weight
    }

    public var body: some View {
        let height: CGFloat = weight == .title ? 12 : weight == .headline ? 8 : 6
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(weight == .detail ? GanchoTokens.Palette.hairline : GanchoTokens.Palette.ink3)
            .frame(width: width * scale, height: height * scale)
            .accessibilityHidden(true)
    }
}

/// The stage of a hidden preview: a diagonal hairline hatch, flat under
/// Reduce Transparency. It never animates.
public struct RedactionHatch: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        if reduceTransparency {
            GanchoTokens.Palette.controlFill
        } else {
            Canvas { context, size in
                var lines = Path()
                var x = -size.height
                while x < size.width {
                    lines.move(to: CGPoint(x: x, y: size.height))
                    lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 9
                }
                context.stroke(
                    lines, with: .color(GanchoTokens.Palette.ink.opacity(0.07)), lineWidth: 1)
            }
            .accessibilityHidden(true)
        }
    }
}
