import Foundation

/// Pure multi-selection state for the macOS history panel.
///
/// The cursor remains a single row so preview and keyboard focus stay stable,
/// while `selectedIDs` can represent a contiguous Shift selection or a
/// discontiguous Command-click selection. Keeping the anchor as an item id
/// makes a refresh/filter reconciliation safe when row indices move.
public struct PanelSelectionState: Equatable, Sendable {
    public var cursorIndex: Int
    public var anchorID: UUID?
    public var selectedIDs: Set<UUID>

    public init(
        cursorIndex: Int = 0,
        anchorID: UUID? = nil,
        selectedIDs: Set<UUID> = []
    ) {
        self.cursorIndex = cursorIndex
        self.anchorID = anchorID
        self.selectedIDs = selectedIDs
    }
}

public enum PanelSelectionAction: Equatable, Sendable {
    /// Plain click/arrow: collapse to one row and start a new range anchor.
    case replace(index: Int)
    /// Command-click: toggle one row without disturbing the other selections.
    case toggle(index: Int)
    /// Keyboard movement; Shift extends/contracts from the stable anchor.
    case move(delta: Int, extending: Bool)
    /// Drop ids no longer visible and clamp the cursor after a data change.
    case reconcile
}

public enum PanelSelection {
    public static func reduce(
        _ action: PanelSelectionAction,
        state: PanelSelectionState,
        rowIDs: [UUID]
    ) -> PanelSelectionState {
        guard !rowIDs.isEmpty else { return PanelSelectionState() }

        let currentIndex = min(max(state.cursorIndex, 0), rowIDs.count - 1)
        let visibleIDs = Set(rowIDs)
        var normalized = state
        normalized.cursorIndex = currentIndex
        normalized.selectedIDs.formIntersection(visibleIDs)
        if normalized.selectedIDs.isEmpty {
            normalized.selectedIDs = [rowIDs[currentIndex]]
        }
        if normalized.anchorID.map({ !visibleIDs.contains($0) }) ?? true {
            normalized.anchorID = rowIDs[currentIndex]
        }

        switch action {
        case .replace(let requestedIndex):
            let index = min(max(requestedIndex, 0), rowIDs.count - 1)
            let id = rowIDs[index]
            return PanelSelectionState(cursorIndex: index, anchorID: id, selectedIDs: [id])

        case .toggle(let requestedIndex):
            let index = min(max(requestedIndex, 0), rowIDs.count - 1)
            let id = rowIDs[index]
            var selected = normalized.selectedIDs
            if selected.contains(id), selected.count > 1 {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
            return PanelSelectionState(cursorIndex: index, anchorID: id, selectedIDs: selected)

        case .move(let delta, let extending):
            let index = min(max(currentIndex + delta, 0), rowIDs.count - 1)
            guard extending else {
                let id = rowIDs[index]
                return PanelSelectionState(cursorIndex: index, anchorID: id, selectedIDs: [id])
            }

            let anchorID = normalized.anchorID ?? rowIDs[currentIndex]
            let anchorIndex = rowIDs.firstIndex(of: anchorID) ?? currentIndex
            let bounds = min(anchorIndex, index)...max(anchorIndex, index)
            return PanelSelectionState(
                cursorIndex: index,
                anchorID: anchorID,
                selectedIDs: Set(bounds.map { rowIDs[$0] }))

        case .reconcile:
            return normalized
        }
    }
}
