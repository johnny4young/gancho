import SwiftUI

/// Cards at their own heights in equal columns: each goes to the shortest
/// column so far, so reading order follows the source order.
public struct MasonryLayout: Layout {
    public struct Placement: Equatable, Sendable {
        public let column: Int
        public let y: CGFloat
    }

    let minColumnWidth: CGFloat
    let spacing: CGFloat

    public init(minColumnWidth: CGFloat = 210, spacing: CGFloat = 16) {
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
    }

    /// As many columns of at least `minColumnWidth` as fit, never fewer than one.
    public static func columnCount(
        width: CGFloat, minColumnWidth: CGFloat, spacing: CGFloat
    ) -> Int {
        max(1, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    public static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// Where each card goes and how tall the wall ends up. A tie picks the
    /// leading column.
    public static func place(
        heights: [CGFloat], columns: Int, spacing: CGFloat
    ) -> (placements: [Placement], height: CGFloat) {
        var bottoms = [CGFloat](repeating: 0, count: max(1, columns))
        let placements = heights.map { height in
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let placement = Placement(column: column, y: bottoms[column])
            bottoms[column] += height + spacing
            return placement
        }
        return (placements, max(0, (bottoms.max() ?? 0) - spacing))
    }

    private struct Arrangement {
        let columnWidth: CGFloat
        let heights: [CGFloat]
        let placements: [Placement]
        let height: CGFloat
    }

    private func arrangement(_ subviews: Subviews, width: CGFloat) -> Arrangement {
        let columns = Self.columnCount(
            width: width, minColumnWidth: minColumnWidth, spacing: spacing)
        let columnWidth = Self.columnWidth(width: width, columns: columns, spacing: spacing)
        let heights = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        let placed = Self.place(heights: heights, columns: columns, spacing: spacing)
        return Arrangement(
            columnWidth: columnWidth, heights: heights, placements: placed.placements,
            height: placed.height)
    }

    public func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? minColumnWidth
        return CGSize(width: width, height: arrangement(subviews, width: width).height)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let layout = arrangement(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let placement = layout.placements[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(placement.column) * (layout.columnWidth + spacing),
                    y: bounds.minY + placement.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: layout.columnWidth, height: layout.heights[index]))
        }
    }
}

/// A row that shares its width by weight, above each child's own ideal width
/// so a small share still fits its caption.
public struct WeightedRowLayout: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat = 3) {
        self.spacing = spacing
    }

    /// Every child gets its minimum plus a weighted share of what is left;
    /// when the minimums alone overflow, they shrink in proportion.
    public static func widths(
        weights: [Double], minimums: [CGFloat], available: CGFloat, spacing: CGFloat
    ) -> [CGFloat] {
        let room = max(0, available - spacing * CGFloat(max(0, weights.count - 1)))
        let floor = minimums.reduce(0, +)
        guard floor < room else {
            return minimums.map { floor > 0 ? room * $0 / floor : 0 }
        }
        let total = weights.reduce(0, +)
        return zip(weights, minimums).map { weight, minimum in
            minimum + (total > 0 ? (room - floor) * CGFloat(weight / total) : 0)
        }
    }

    public func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width =
            proposal.width
            ?? ideal.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, ideal.count - 1))
        return CGSize(width: width, height: ideal.map(\.height).max() ?? 0)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let widths = Self.widths(
            weights: subviews.map { $0[LayoutWeight.self] },
            minimums: subviews.map { $0.sizeThatFits(.unspecified).width },
            available: bounds.width, spacing: spacing)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

private struct LayoutWeight: LayoutValueKey {
    static let defaultValue: Double = 1
}

extension View {
    /// This child's share of a `WeightedRowLayout`.
    public func layoutWeight(_ weight: Double) -> some View {
        layoutValue(key: LayoutWeight.self, value: weight)
    }
}
