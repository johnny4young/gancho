import Foundation
import GanchoKit
import Observation

/// Owns the panel cursor and visible batch selection.
///
/// `PanelSelection` remains the pure reducer. This observable collaborator maps
/// its identifier-only state onto the current rows so search never has to own
/// selection mutation or expose reducer storage to SwiftUI.
@MainActor @Observable final class PanelSelectionModel {
    private var state = PanelSelectionState()

    var selectedIndex: Int { state.cursorIndex }

    func selectedItem(in rows: [ClipItem]) -> ClipItem? {
        rows.indices.contains(state.cursorIndex) ? rows[state.cursorIndex] : nil
    }

    func selectedItems(in rows: [ClipItem]) -> [ClipItem] {
        rows.filter { state.selectedIDs.contains($0.id) }
    }

    func selectionCount(in rows: [ClipItem]) -> Int {
        rows.lazy.filter { self.state.selectedIDs.contains($0.id) }.count
    }

    func isSelected(_ id: UUID) -> Bool {
        state.selectedIDs.contains(id)
    }

    func select(_ index: Int, toggling: Bool, in rows: [ClipItem]) {
        apply(toggling ? .toggle(index: index) : .replace(index: index), in: rows)
    }

    func move(by delta: Int, extending: Bool, in rows: [ClipItem]) {
        apply(.move(delta: delta, extending: extending), in: rows)
    }

    func reconcile(in rows: [ClipItem]) {
        apply(.reconcile, in: rows)
    }

    func clear(in rows: [ClipItem]) {
        apply(.replace(index: state.cursorIndex), in: rows)
    }

    private func apply(_ action: PanelSelectionAction, in rows: [ClipItem]) {
        state = PanelSelection.reduce(action, state: state, rowIDs: rows.map(\.id))
    }
}
