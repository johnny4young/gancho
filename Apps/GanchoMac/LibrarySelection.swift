import Foundation
import GanchoKit

/// What the Library sidebar can have selected. Boards browse clips; a snippet
/// opens the editor.
enum LibrarySelection: Hashable {
    case allClips
    case pinned
    case board(UUID)
    case snippet(UUID)
    case savedFilter(UUID)
}

/// Drives the new-board / rename-board name prompt.
enum LibraryBoardSheet: Identifiable {
    case new
    case rename(Pinboard)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let board): board.id.uuidString
        }
    }
}
