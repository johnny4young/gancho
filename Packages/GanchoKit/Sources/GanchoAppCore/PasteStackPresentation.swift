import Foundation
import GanchoKit

/// What the peek shows for a paste stack: each entry's state, the run position
/// and the dock's verbs with the keys that exist.
public struct PasteStackPresentation: Equatable, Sendable {
    public enum RowState: Equatable, Sendable {
        case pasted, next, waiting
    }

    public struct Row: Identifiable, Equatable, Sendable {
        /// The entry id: duplicates of one clip stay distinct rows.
        public let id: Int
        /// The 1-based place in the run.
        public let number: Int
        public let clip: ClipItem
        public let state: RowState
        /// A pasted row stays put; nothing moves in front of the next one.
        public let canMoveUp: Bool
        public let canMoveDown: Bool
    }

    public enum Verb: String, Equatable, Sendable {
        case pasteNext, skip, back, reset, end
    }

    public struct DockVerb: Equatable, Sendable {
        public let verb: Verb
        /// The key drawn beside the verb; nil draws none.
        public let key: String?
        public let isEnabled: Bool
    }

    public let rows: [Row]
    public let cursor: Int
    public let isRunActive: Bool

    public init(stack: PasteStack) {
        let entries = stack.entries
        cursor = stack.cursor
        isRunActive = stack.isRunActive
        rows = entries.enumerated().map { index, entry in
            let state: RowState =
                index < stack.cursor ? .pasted : index == stack.cursor ? .next : .waiting
            return Row(
                id: entry.id, number: index + 1, clip: entry.clip, state: state,
                canMoveUp: index > stack.cursor,
                canMoveDown: index >= stack.cursor && index < entries.count - 1)
        }
    }

    public var count: Int { rows.count }

    /// The entry the next paste takes, counting from 1, as in "2/4".
    public var current: Int { min(cursor + 1, count) }

    /// Return and esc are the panel's own keys; Skip and Back show a recorded
    /// global shortcut, and Reset has none.
    public func dock(skipKey: String?, backKey: String?) -> [DockVerb] {
        let hasNext = cursor < count
        return [
            DockVerb(verb: .pasteNext, key: "↩", isEnabled: hasNext),
            DockVerb(verb: .skip, key: Self.recorded(skipKey), isEnabled: hasNext),
            DockVerb(verb: .back, key: Self.recorded(backKey), isEnabled: cursor > 0),
            DockVerb(verb: .reset, key: nil, isEnabled: cursor > 0),
            DockVerb(verb: .end, key: "esc", isEnabled: true)
        ]
    }

    /// The offsets `PasteStack.move` takes to shift one row by one place; nil
    /// when the row cannot go that way.
    public func move(_ id: Int, up: Bool) -> (source: IndexSet, destination: Int)? {
        guard let index = rows.firstIndex(where: { $0.id == id }),
            up ? rows[index].canMoveUp : rows[index].canMoveDown
        else { return nil }
        return (IndexSet(integer: index), up ? index - 1 : index + 2)
    }

    private static func recorded(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return key
    }
}
