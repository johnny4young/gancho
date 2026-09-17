import SwiftUI

/// A wrapping HStack: subviews flow left to right and wrap into as many rows
/// as they need. Chips, tags and hint rows use it wherever a fixed row would
/// truncate a label.
///
/// Every subview is measured AND placed against the row width, in both
/// passes, so the two can never disagree on where a row breaks, and a single
/// subview wider than the row (a long host in a chip) wraps its own text
/// instead of running past the edge.
public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Breaks the subviews into rows for one width. A subview is offered the
    /// full row width, so text inside it wraps before the row ever overflows.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        let rowProposal = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        var rows: [Row] = []
        var row = Row()
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(rowProposal)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += row.items.isEmpty ? size.width : spacing + size.width
            row.items.append((index, size))
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
