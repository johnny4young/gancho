import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor
@Suite("Panel selection model")
struct PanelSelectionModelTests {
    private let rows = (0..<6).map { ClipItem(preview: "item \($0)") }

    @Test("Visible selection stays ordered and follows the cursor")
    func visibleSelectionFollowsCursor() {
        let model = PanelSelectionModel()

        model.select(0, toggling: false, in: rows)
        model.move(by: 2, extending: true, in: rows)
        model.select(5, toggling: true, in: rows)

        #expect(model.selectedIndex == 5)
        #expect(model.selectedItem(in: rows)?.id == rows[5].id)
        #expect(
            model.selectedItems(in: rows).map(\.id) == [
                rows[0].id, rows[1].id, rows[2].id, rows[5].id
            ])
        #expect(model.selectionCount(in: rows) == 4)
    }

    @Test("Opening follows the newest unpinned clip until the user moves")
    func opensOnNewestClip() {
        let model = PanelSelectionModel()
        let pinned = ClipItem(preview: "pinned", contentHash: "pinned", isPinned: true)
        var list = [pinned] + rows
        model.select(4, toggling: false, in: list)
        model.followNewest(skippingPinned: true, in: list)
        #expect(model.selectedItem(in: list)?.id == rows[0].id)

        let fresh = ClipItem(preview: "fresh", contentHash: "fresh")
        list = [pinned, fresh] + rows
        model.reconcile(in: list)
        #expect(model.selectedItem(in: list)?.id == fresh.id, "a capture while open stays newest")

        model.move(by: 1, extending: false, in: list)
        let later = [pinned, ClipItem(preview: "later", contentHash: "later"), fresh] + rows
        model.reconcile(in: later)
        #expect(model.selectedItem(in: later)?.id == rows[0].id, "moving ends the follow")
    }

    @Test("A search opens on its first result, pinned or not")
    func searchOpensOnFirstResult() {
        let model = PanelSelectionModel()
        let pinned = ClipItem(preview: "pinned", contentHash: "pinned", isPinned: true)
        model.followNewest(skippingPinned: false, in: [pinned] + rows)
        #expect(model.selectedItem(in: [pinned] + rows)?.id == pinned.id)
    }

    @Test("Toggling off the cursor moves default actions to a selected clip")
    func toggledCursorMovesToSelectedClip() {
        let model = PanelSelectionModel()

        model.select(0, toggling: false, in: rows)
        model.select(3, toggling: true, in: rows)
        model.select(0, toggling: true, in: rows)

        #expect(model.selectedIndex == 3)
        #expect(model.selectedItem(in: rows)?.id == rows[3].id)
        #expect(model.selectedItems(in: rows).map(\.id) == [rows[3].id])
        #expect(model.isSelected(rows[3].id))
        #expect(!model.isSelected(rows[0].id))
    }

    @Test("Reconciliation drops hidden selections without exposing stale rows")
    func reconciliationUsesVisibleRowsOnly() {
        let model = PanelSelectionModel()
        model.select(1, toggling: false, in: rows)
        model.move(by: 3, extending: true, in: rows)

        let visible = [rows[0], rows[4], rows[5]]
        model.reconcile(in: visible)

        #expect(model.selectedIndex == 1)
        #expect(model.selectedItem(in: visible)?.id == rows[4].id)
        #expect(model.selectedItems(in: visible).map(\.id) == [rows[4].id])
    }

    @Test("Clear reconciles a stale cursor before collapsing the batch")
    func clearReconcilesBeforeCollapsingSelection() {
        let model = PanelSelectionModel()
        model.select(1, toggling: false, in: rows)
        model.move(by: 3, extending: true, in: rows)

        let visible = [rows[0], rows[1], rows[4], rows[5]]
        model.clear(in: visible)

        #expect(model.selectedIndex == 2)
        #expect(model.selectedItem(in: visible)?.id == rows[4].id)
        #expect(model.selectedItems(in: visible).map(\.id) == [rows[4].id])
    }
}
