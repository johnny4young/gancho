import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Panel multi-selection")
struct PanelSelectionTests {
    private let rows = (0..<6).map { _ in UUID() }

    @Test func plainSelectionCollapsesToOneRow() {
        let state = PanelSelectionState(
            cursorIndex: 3, anchorID: rows[1], selectedIDs: [rows[1], rows[2], rows[3]])

        let result = PanelSelection.reduce(.replace(index: 4), state: state, rowIDs: rows)

        #expect(result.cursorIndex == 4)
        #expect(result.anchorID == rows[4])
        #expect(result.selectedIDs == [rows[4]])
    }

    @Test func shiftMovementExtendsAndContractsAContiguousRange() {
        let start = PanelSelection.reduce(
            .replace(index: 1), state: PanelSelectionState(), rowIDs: rows)
        let extended = PanelSelection.reduce(
            .move(delta: 3, extending: true), state: start, rowIDs: rows)

        #expect(extended.cursorIndex == 4)
        #expect(extended.anchorID == rows[1])
        #expect(extended.selectedIDs == Set(rows[1...4]))

        let contracted = PanelSelection.reduce(
            .move(delta: -2, extending: true), state: extended, rowIDs: rows)
        #expect(contracted.cursorIndex == 2)
        #expect(contracted.selectedIDs == Set(rows[1...2]))
    }

    @Test func shiftMovementClampsWithoutWrapping() {
        let start = PanelSelection.reduce(
            .replace(index: 4), state: PanelSelectionState(), rowIDs: rows)
        let result = PanelSelection.reduce(
            .move(delta: 20, extending: true), state: start, rowIDs: rows)

        #expect(result.cursorIndex == rows.count - 1)
        #expect(result.selectedIDs == Set(rows[4...5]))
    }

    @Test func commandToggleBuildsADiscontiguousSelection() {
        let start = PanelSelection.reduce(
            .replace(index: 0), state: PanelSelectionState(), rowIDs: rows)
        let added = PanelSelection.reduce(.toggle(index: 3), state: start, rowIDs: rows)
        let removed = PanelSelection.reduce(.toggle(index: 0), state: added, rowIDs: rows)

        #expect(added.selectedIDs == [rows[0], rows[3]])
        #expect(removed.selectedIDs == [rows[3]])
        #expect(removed.cursorIndex == 0)
    }

    @Test func commandToggleNeverLeavesAnInvisibleCursorOnlyState() {
        let start = PanelSelection.reduce(
            .replace(index: 2), state: PanelSelectionState(), rowIDs: rows)
        let result = PanelSelection.reduce(.toggle(index: 2), state: start, rowIDs: rows)

        #expect(result.selectedIDs == [rows[2]])
    }

    @Test func reconcileDropsHiddenRowsAndRepairsAnchorAndCursor() {
        let state = PanelSelectionState(
            cursorIndex: 5, anchorID: rows[5], selectedIDs: [rows[2], rows[5]])
        let visible = [rows[0], rows[1], rows[2]]

        let result = PanelSelection.reduce(.reconcile, state: state, rowIDs: visible)

        #expect(result.cursorIndex == 2)
        #expect(result.anchorID == rows[2])
        #expect(result.selectedIDs == [rows[2]])
    }
}
