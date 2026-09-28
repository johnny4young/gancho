import Testing

@testable import GanchoDesign

@Suite("Row hover while the list scrolls")
struct ClipCardHoverTests {
    @Test("A still pointer keeps its hover only while the list is idle")
    func idleFollowsPointer() {
        #expect(ClipCard.hoverState(pointerInside: true, listIsScrolling: false))
        #expect(!ClipCard.hoverState(pointerInside: false, listIsScrolling: false))
    }

    @Test("Scrolling clears the hover, and settling does not restore it")
    func scrollingClears() {
        #expect(!ClipCard.hoverState(pointerInside: true, listIsScrolling: true))
        // The row reads its own cleared state once the list settles; only the
        // next pointer move can light it again.
        #expect(!ClipCard.hoverState(pointerInside: false, listIsScrolling: false))
    }
}
