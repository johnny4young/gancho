import CoreGraphics
import Testing

@testable import GanchoDesign

@Suite("Masonry — column count, shortest-column placement and weighted rows")
struct MasonryLayoutTests {
    @Test("Columns fit the width at the minimum, never fewer than one")
    func columnCount() {
        let count = { MasonryLayout.columnCount(width: $0, minColumnWidth: 210, spacing: 16) }
        #expect(count(0) == 1)
        #expect(count(209) == 1)
        #expect(count(435) == 1)
        #expect(count(436) == 2)
        #expect(count(888) == 4)
        #expect(count(.infinity) == 1)
        #expect(count(.nan) == 1)
        #expect(MasonryLayout.columnWidth(width: 436, columns: 2, spacing: 16) == 210)
        #expect(MasonryLayout.columnWidth(width: 100, columns: 1, spacing: 16) == 100)
    }

    @Test("Each card lands in the shortest column, ties on the leading one")
    func placesInTheShortestColumn() {
        let placed = MasonryLayout.place(heights: [100, 40, 60, 30, 50], columns: 3, spacing: 10)
        #expect(placed.placements.map(\.column) == [0, 1, 2, 1, 2])
        #expect(placed.placements.map(\.y) == [0, 0, 0, 50, 70])
        #expect(placed.height == 120)
    }

    @Test("One column stacks in order; no cards take no height")
    func degenerateWalls() {
        let stacked = MasonryLayout.place(heights: [20, 30], columns: 1, spacing: 8)
        #expect(stacked.placements == [.init(column: 0, y: 0), .init(column: 0, y: 28)])
        #expect(stacked.height == 58)
        #expect(MasonryLayout.place(heights: [], columns: 3, spacing: 8).height == 0)
        #expect(MasonryLayout.place(heights: [10], columns: 0, spacing: 8).height == 10)
    }

    @Test("A weighted row shares what the minimums leave, and fills the width")
    func weightedWidths() {
        let widths = WeightedRowLayout.widths(
            weights: [3, 1], minimums: [20, 20], available: 144, spacing: 4)
        #expect(widths == [95, 45])
        #expect(widths.reduce(0, +) + 4 == 144)
        let equal = WeightedRowLayout.widths(
            weights: [0, 0], minimums: [10, 30], available: 100, spacing: 0)
        #expect(equal == [10, 30])
    }

    @Test("Minimums that overflow shrink in proportion")
    func weightedWidthsOverflow() {
        let widths = WeightedRowLayout.widths(
            weights: [9, 1], minimums: [60, 20], available: 44, spacing: 4)
        #expect(widths == [30, 10])
        #expect(
            WeightedRowLayout.widths(weights: [], minimums: [], available: 10, spacing: 4).isEmpty)
    }
}
