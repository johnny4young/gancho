import Foundation
import Testing

@testable import GanchoAppCore

/// Pure keyboard-navigation reducer for the macOS history panel. These pin the
/// movement rules (list ↔ rails, wrap-around, chip toggling, focus hand-off,
/// prefetch trigger) that were untestable while they lived as `PanelView`
/// methods.
@Suite("Panel keyboard navigation")
struct PanelNavigationTests {
    private let boardA = UUID()
    private let boardB = UUID()

    private func context(rowCount: Int = 5, hasSelection: Bool = true) -> PanelNavigationContext {
        PanelNavigationContext(
            rowCount: rowCount, boardIDs: [boardA, boardB], hasSelection: hasSelection)
    }

    // MARK: - List movement

    @Test func downArrowAdvancesSelectionAndRequestsPrefetch() {
        let result = PanelNavigation.reduce(
            .down, state: PanelNavigationState(selectedIndex: 0), context: context())
        #expect(result.state.selectedIndex == 1)
        #expect(result.handled)
        #expect(result.loadMoreAt == 1)  // arrowing down prefetches ahead of the cursor
    }

    @Test func downArrowWrapsAtTheEnd() {
        let result = PanelNavigation.reduce(
            .down, state: PanelNavigationState(selectedIndex: 4), context: context(rowCount: 5))
        #expect(result.state.selectedIndex == 0)
    }

    @Test func upArrowMovesUpWithoutPrefetch() {
        let result = PanelNavigation.reduce(
            .up, state: PanelNavigationState(selectedIndex: 2), context: context())
        #expect(result.state.selectedIndex == 1)
        #expect(result.loadMoreAt == nil)  // only downward motion prefetches
    }

    @Test func arrowsAreAlwaysHandledEvenWithNoRows() {
        // Returning .ignored would let the arrow steal focus from the search field.
        let result = PanelNavigation.reduce(
            .down, state: PanelNavigationState(selectedIndex: 0),
            context: context(rowCount: 0, hasSelection: false))
        #expect(result.handled)
        #expect(result.state.selectedIndex == 0)
        #expect(result.loadMoreAt == nil)
    }

    // MARK: - Entering / leaving the rails

    @Test func upAtRowZeroEntersTheFilterRailThenTheBoardRail() {
        let intoFilters = PanelNavigation.reduce(
            .up, state: PanelNavigationState(selectedIndex: 0, kindFilter: .code),
            context: context())
        // The filter rail focuses the currently-active pill.
        #expect(
            intoFilters.state.railFocus == .filters(ClipKindFilter.allCases.firstIndex(of: .code)!))

        let intoBoards = PanelNavigation.reduce(
            .up, state: intoFilters.state, context: context())
        #expect(intoBoards.state.railFocus == .boards(0))  // no board selected → "All clips"
    }

    @Test func upIntoBoardsHighlightsTheSelectedBoard() {
        let state = PanelNavigationState(railFocus: .filters(0), selectedBoardID: boardB)
        let result = PanelNavigation.reduce(.up, state: state, context: context())
        #expect(result.state.railFocus == .boards(2))  // boardB is slot 2 (1-based, All is 0)
    }

    @Test func downFromFilterRailReturnsToTheListTop() {
        let state = PanelNavigationState(railFocus: .filters(3), selectedIndex: 4)
        let result = PanelNavigation.reduce(.down, state: state, context: context())
        #expect(result.state.railFocus == nil)
        #expect(result.state.selectedIndex == 0)
    }

    @Test func upAtTheTopBoardRailIsANoOp() {
        let state = PanelNavigationState(railFocus: .boards(0))
        let result = PanelNavigation.reduce(.up, state: state, context: context())
        #expect(result.state.railFocus == .boards(0))
        #expect(result.handled)
    }

    // MARK: - Horizontal rail movement + focus hand-off

    @Test func leftAndRightMoveWithinAFilterRailAndClamp() {
        let mid = PanelNavigation.reduce(
            .left, state: PanelNavigationState(railFocus: .filters(2)), context: context())
        #expect(mid.state.railFocus == .filters(1))

        let clampedLow = PanelNavigation.reduce(
            .left, state: PanelNavigationState(railFocus: .filters(0)), context: context())
        #expect(clampedLow.state.railFocus == .filters(0))

        let last = ClipKindFilter.allCases.count - 1
        let clampedHigh = PanelNavigation.reduce(
            .right, state: PanelNavigationState(railFocus: .filters(last)), context: context())
        #expect(clampedHigh.state.railFocus == .filters(last))
    }

    @Test func rightInBoardRailClampsAtTheBoardCount() {
        // The board rail is All(0) + 2 boards → max slot is boardIDs.count == 2.
        let result = PanelNavigation.reduce(
            .right, state: PanelNavigationState(railFocus: .boards(2)), context: context())
        #expect(result.state.railFocus == .boards(2))
    }

    @Test func rightInTheListHandsFocusToThePeekWhenAClipIsSelected() {
        let withSelection = PanelNavigation.reduce(
            .right, state: PanelNavigationState(), context: context(hasSelection: true))
        #expect(withSelection.focusPeek)
        #expect(withSelection.handled)

        let withoutSelection = PanelNavigation.reduce(
            .right, state: PanelNavigationState(), context: context(hasSelection: false))
        #expect(!withoutSelection.focusPeek)
        #expect(!withoutSelection.handled)  // nothing to hand off to → let the key propagate
    }

    @Test func leftInTheListIsIgnored() {
        // ← in the list is the search-field cursor, so the reducer must not eat it.
        let result = PanelNavigation.reduce(
            .left, state: PanelNavigationState(), context: context())
        #expect(!result.handled)
    }

    // MARK: - Toggling chips

    @Test func toggleFilterChipSelectsThenDeselects() {
        let filterIndex = ClipKindFilter.allCases.firstIndex(of: .links)!
        let on = PanelNavigation.reduce(
            .toggle,
            state: PanelNavigationState(railFocus: .filters(filterIndex), selectedIndex: 3),
            context: context())
        #expect(on.state.kindFilter == .links)
        #expect(on.state.selectedIndex == 0)  // a new filter resets the cursor

        let off = PanelNavigation.reduce(
            .toggle,
            state: PanelNavigationState(railFocus: .filters(filterIndex), kindFilter: .links),
            context: context())
        #expect(off.state.kindFilter == .all)  // toggling the active pill clears it
    }

    @Test func toggleBoardChipSelectsAndAllClipsClears() {
        let pickB = PanelNavigation.reduce(
            .toggle, state: PanelNavigationState(railFocus: .boards(2)), context: context())
        #expect(pickB.state.selectedBoardID == boardB)

        let clear = PanelNavigation.reduce(
            .toggle, state: PanelNavigationState(railFocus: .boards(0), selectedBoardID: boardB),
            context: context())
        #expect(clear.state.selectedBoardID == nil)  // slot 0 = "All clips"
    }

    @Test func toggleOutsideARailIsNotHandled() {
        let result = PanelNavigation.reduce(
            .toggle, state: PanelNavigationState(), context: context())
        #expect(!result.handled)  // Space in the list falls through to the search field
    }
}
