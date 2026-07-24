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

        let normalized = normalizedState(state, rowIDs: rowIDs)
        let currentIndex = normalized.cursorIndex

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
                guard
                    let selectedIndex = nearestSelectedIndex(
                        to: index, selectedIDs: selected, rowIDs: rowIDs)
                else { return normalized }
                let selectedID = rowIDs[selectedIndex]
                return PanelSelectionState(
                    cursorIndex: selectedIndex,
                    anchorID: selectedID,
                    selectedIDs: selected)
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

    /// Removes hidden identifiers and restores the cursor/anchor invariant
    /// before any action-specific transition runs.
    private static func normalizedState(
        _ state: PanelSelectionState,
        rowIDs: [UUID]
    ) -> PanelSelectionState {
        let clampedIndex = min(max(state.cursorIndex, 0), rowIDs.count - 1)
        var normalized = state
        normalized.cursorIndex = clampedIndex
        normalized.selectedIDs.formIntersection(Set(rowIDs))
        if normalized.selectedIDs.isEmpty {
            normalized.selectedIDs = [rowIDs[clampedIndex]]
        }
        if !normalized.selectedIDs.contains(rowIDs[normalized.cursorIndex]),
            let selectedIndex = nearestSelectedIndex(
                to: normalized.cursorIndex,
                selectedIDs: normalized.selectedIDs,
                rowIDs: rowIDs)
        {
            normalized.cursorIndex = selectedIndex
        }
        if normalized.anchorID.map({ !normalized.selectedIDs.contains($0) }) ?? true {
            normalized.anchorID = rowIDs[normalized.cursorIndex]
        }
        return normalized
    }

    /// Keeps keyboard, preview, and default actions anchored to an item that is
    /// actually selected. Prefer the closest selected row and the earlier row
    /// on a tie so reconciliation is deterministic.
    private static func nearestSelectedIndex(
        to index: Int,
        selectedIDs: Set<UUID>,
        rowIDs: [UUID]
    ) -> Int? {
        var nearestIndex: Int?
        var nearestDistance = Int.max
        for candidateIndex in rowIDs.indices
        where selectedIDs.contains(rowIDs[candidateIndex]) {
            let distance = abs(candidateIndex - index)
            if distance < nearestDistance {
                nearestIndex = candidateIndex
                nearestDistance = distance
                if distance == 0 { break }
            }
        }
        return nearestIndex
    }
}
