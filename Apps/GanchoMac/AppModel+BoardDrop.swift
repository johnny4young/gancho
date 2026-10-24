import Foundation
import GanchoAppCore
import GanchoDesign
import GanchoKit

/// A clip dragged inside the app and dropped on a board (a panel rail chip or a
/// Library sidebar row).
extension AppModel {
    /// Files the clip and confirms with a toast; true only when it was added.
    func drop(clipID: UUID, onBoard board: Pinboard) async -> Bool {
        let item = try? await store.item(id: clipID)
        let isMember: Bool =
            if let item { await boardMembership(for: item).contains(board.id) } else { false }
        switch BoardDrop.decide(
            item: item, isMember: isMember, isPendingDeletion: pendingDeletionIDs.contains(clipID))
        {
        case .ignore:
            return false
        case .alreadyMember:
            toasts.show(GanchoToast(message: "Already in \(board.displayName)"))
            return false
        case .add:
            guard let item, await setBoardMembership([item], board: board, member: true) else {
                return false
            }
            showAddedToast([item], board: board)
            return true
        }
    }
}
