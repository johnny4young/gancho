import Foundation

/// When the keyboard is "up" in the rails above the list: which rail and which
/// chip. ↑ from the first list row enters `.filters`, ↑ again `.boards`; ←→ move
/// within a rail, Space/Enter toggles. `nil` means the keyboard is in the list.
public enum RailFocus: Hashable, Sendable {
    case boards(Int)  // 0 = "All clips", 1…n = boards[i-1]
    case filters(Int)  // index into ClipKindFilter.allCases
}

/// The mutable navigation state the reducer reads and rewrites. It spans the
/// search model (`selectedIndex`/`kindFilter`/`selectedBoardID`) and the panel
/// view (`railFocus`), which is exactly why the movement rules were untestable
/// while they lived as methods on the `View`.
public struct PanelNavigationState: Equatable, Sendable {
    public var railFocus: RailFocus?
    public var selectedIndex: Int
    public var kindFilter: ClipKindFilter
    public var selectedBoardID: UUID?

    public init(
        railFocus: RailFocus? = nil,
        selectedIndex: Int = 0,
        kindFilter: ClipKindFilter = .all,
        selectedBoardID: UUID? = nil
    ) {
        self.railFocus = railFocus
        self.selectedIndex = selectedIndex
        self.kindFilter = kindFilter
        self.selectedBoardID = selectedBoardID
    }
}

/// The read-only surroundings a keypress is resolved against: how many rows the
/// list shows, the board ids in rail order, and whether a clip is selected (→
/// hands focus to the peek).
public struct PanelNavigationContext: Sendable {
    public let rowCount: Int
    public let boardIDs: [UUID]
    public let hasSelection: Bool

    public init(rowCount: Int, boardIDs: [UUID], hasSelection: Bool) {
        self.rowCount = rowCount
        self.boardIDs = boardIDs
        self.hasSelection = hasSelection
    }
}

/// The keys the panel's list/rail navigation reacts to. `toggle` is Space/Enter
/// on a focused rail chip.
public enum PanelNavigationKey: Sendable {
    case up, down, left, right, toggle
}

/// The reducer's output: the next state plus the two effects the shell still has
/// to run (they can't be pure) — moving SwiftUI focus into the peek, and pulling
/// the next page when the cursor nears the end. `handled == false` maps to
/// `KeyPress.Result.ignored` so the key can propagate.
public struct PanelNavigationResult: Equatable, Sendable {
    public var state: PanelNavigationState
    public var handled: Bool
    public var focusPeek: Bool
    public var loadMoreAt: Int?
}

// Keep the keyboard state machine in one reducer so wrap-around, rail, and peek
// focus transitions stay auditable together.
// swiftlint:disable cyclomatic_complexity function_body_length
/// Pure list/rail keyboard navigation for the macOS history panel. Extracted
/// verbatim from `PanelView`'s `move`/`navigate*`/`toggleFocusedRail` methods so
/// the movement rules (wrap-around, rail entry/exit, chip toggling) can be unit
/// tested without a running app.
public enum PanelNavigation {
    public static func reduce(
        _ key: PanelNavigationKey,
        state: PanelNavigationState,
        context: PanelNavigationContext
    ) -> PanelNavigationResult {
        // swiftlint:enable cyclomatic_complexity function_body_length
        var state = state
        var handled = true
        var focusPeek = false
        var loadMoreAt: Int?

        // Always consume arrows so focus never leaves the search field — with no
        // results there is simply nothing to move (Spotlight behavior).
        func move(_ delta: Int) {
            guard context.rowCount > 0 else { return }
            state.selectedIndex =
                (state.selectedIndex + delta + context.rowCount) % context.rowCount
            // Arrowing down toward the end pulls the next page ahead of the cursor.
            if delta > 0 { loadMoreAt = state.selectedIndex }
        }
        let currentFilterIndex = ClipKindFilter.allCases.firstIndex(of: state.kindFilter) ?? 0
        // 0 = "All clips"; otherwise the selected board's slot (1-based).
        let currentBoardIndex: Int = {
            guard let id = state.selectedBoardID else { return 0 }
            return context.boardIDs.firstIndex(of: id).map { $0 + 1 } ?? 0
        }()

        switch key {
        case .up:
            // ↑: out of the list at row 0 into the filters, then up to the boards.
            switch state.railFocus {
            case nil:
                if state.selectedIndex != 0 {
                    move(-1)
                } else {
                    state.railFocus = .filters(currentFilterIndex)
                }
            case .filters:
                state.railFocus = .boards(currentBoardIndex)
            case .boards:
                break  // top of the stack
            }
        case .down:
            // ↓: boards → filters → back into the list.
            switch state.railFocus {
            case nil:
                move(1)
            case .filters:
                state.railFocus = nil
                state.selectedIndex = 0
            case .boards:
                state.railFocus = .filters(currentFilterIndex)
            }
        case .left:
            // ← moves within the focused rail; in the list it is the search cursor.
            switch state.railFocus {
            case .filters(let i): state.railFocus = .filters(max(0, i - 1))
            case .boards(let i): state.railFocus = .boards(max(0, i - 1))
            case nil: handled = false
            }
        case .right:
            // → moves within the focused rail; in the list it hands off to the peek.
            switch state.railFocus {
            case .filters(let i):
                state.railFocus = .filters(min(ClipKindFilter.allCases.count - 1, i + 1))
            case .boards(let i):
                state.railFocus = .boards(min(context.boardIDs.count, i + 1))
            case nil:
                if context.hasSelection { focusPeek = true } else { handled = false }
            }
        case .toggle:
            // Space / Enter on a focused chip: select it, or deselect (back to
            // All) if it is already active. Not in a rail → not handled.
            switch state.railFocus {
            case .filters(let i):
                let filter = ClipKindFilter.allCases[i]
                state.kindFilter = (state.kindFilter == filter) ? .all : filter
                state.selectedIndex = 0
            case .boards(let i):
                if i == 0 {
                    state.selectedBoardID = nil
                } else if context.boardIDs.indices.contains(i - 1) {
                    let boardID = context.boardIDs[i - 1]
                    state.selectedBoardID = (state.selectedBoardID == boardID) ? nil : boardID
                }
            case nil:
                handled = false
            }
        }

        return PanelNavigationResult(
            state: state, handled: handled, focusPeek: focusPeek, loadMoreAt: loadMoreAt)
    }
}
