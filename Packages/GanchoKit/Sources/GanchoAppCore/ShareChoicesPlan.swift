import ClipboardCore
import Foundation
import GanchoKit

/// What a shared clip gets from the share sheet's choices. A typed board is
/// reused when one already has its name, so applying the same choices twice
/// never makes a second board. A protected clip takes no title and no pin,
/// and a clip already in history keeps the title it has.
public struct ShareChoicesPlan: Equatable, Sendable {
    public let boards: [Pinboard]
    /// A board to create and file the clip into; nil when none is new.
    public let newBoardName: String?
    public let title: String?
    public let pins: Bool

    public init(
        _ choices: SharedInbox.ShareChoices, existing: [Pinboard], item: ClipItem, isNew: Bool
    ) {
        let protected = ClipSafePresentation.requiresMasking(item)
        title =
            protected || (!isNew && !item.title.isEmpty) || choices.title == item.title
            ? nil : choices.title
        pins = choices.isPinned && !protected && !item.isPinned
        var targets = existing.filter { choices.boardIDs.contains($0.id) }
        var create: String?
        if let name = choices.newBoardName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        {
            if let match = existing.first(where: {
                !$0.isSystem && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
            }) {
                if !targets.contains(match) { targets.append(match) }
            } else {
                create = name
            }
        }
        boards = targets
        newBoardName = create
    }
}
