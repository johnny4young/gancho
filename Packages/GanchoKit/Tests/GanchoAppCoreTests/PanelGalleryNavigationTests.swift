import Foundation
import Testing

@testable import GanchoAppCore

/// The same reducer with a gallery context: ↑↓ move by a row of cards, ←→
/// step within a row, and the list's rail entry and wrap-around still hold.
@Suite("Panel keyboard navigation — gallery columns")
struct PanelGalleryNavigationTests {
    private func gallery(rowCount: Int = 8, columns: Int = 3) -> PanelNavigationContext {
        PanelNavigationContext(
            rowCount: rowCount, boardIDs: [], hasSelection: true, columns: columns)
    }

    private func reduce(
        _ key: PanelNavigationKey, from index: Int, rowCount: Int = 8
    )
        -> PanelNavigationResult
    {
        PanelNavigation.reduce(
            key, state: PanelNavigationState(selectedIndex: index),
            context: gallery(rowCount: rowCount))
    }

    @Test func downMovesOneRowOfCardsAndPrefetches() {
        let result = reduce(.down, from: 1)
        #expect(result.state.selectedIndex == 4)
        #expect(result.loadMoreAt == 4)
    }

    @Test func downFromAPartialLastRowStopsOnTheLastCardThenWraps() {
        #expect(reduce(.down, from: 6).state.selectedIndex == 7)
        #expect(reduce(.down, from: 7).state.selectedIndex == 0)
    }

    @Test func upMovesOneRowThenTheFirstCardThenTheRails() {
        #expect(reduce(.up, from: 4).state.selectedIndex == 1)
        #expect(reduce(.up, from: 1).state.selectedIndex == 0)
        #expect(reduce(.up, from: 0).state.railFocus == .filters(0))
    }

    @Test func rightStepsWithinTheRowAndHandsOffToThePeekAtItsEnd() {
        let stepped = reduce(.right, from: 0)
        #expect(stepped.state.selectedIndex == 1)
        #expect(!stepped.focusPeek)
        let handoff = reduce(.right, from: 2)
        #expect(handoff.state.selectedIndex == 2)
        #expect(handoff.focusPeek)
    }

    @Test func rightOnTheLastCardOfAPartialRowOpensThePeek() {
        let result = reduce(.right, from: 7)
        #expect(result.state.selectedIndex == 7)
        #expect(result.focusPeek)
    }

    @Test func leftStepsWithinTheRowAndFallsThroughAtItsStart() {
        #expect(reduce(.left, from: 1).state.selectedIndex == 0)
        let atStart = reduce(.left, from: 3)
        #expect(atStart.state.selectedIndex == 3)
        #expect(!atStart.handled)
    }

    @Test func singleColumnKeepsTheListRules() {
        let list = PanelNavigationContext(rowCount: 5, boardIDs: [], hasSelection: true)
        let down = PanelNavigation.reduce(
            .down, state: PanelNavigationState(selectedIndex: 4), context: list)
        #expect(down.state.selectedIndex == 0)
        let right = PanelNavigation.reduce(
            .right, state: PanelNavigationState(selectedIndex: 2), context: list)
        #expect(right.focusPeek)
    }
}
