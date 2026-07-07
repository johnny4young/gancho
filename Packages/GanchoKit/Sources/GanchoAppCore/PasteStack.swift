import Foundation
import GanchoKit

/// The paste queue as a pure value: load several clips, then paste them in
/// order. FIFO — `push` appends, `popFirst` takes the front. Duplicates are
/// allowed on purpose (pasting the same clip twice in a row is a real use).
///
/// Lives here (not in the app target) so its ordering is unit-tested headless;
/// `AppModel` owns one and routes the paste-back side effect. The queue is a
/// session working set: it never persists and never syncs.
public struct PasteStack: Equatable, Sendable {
    public private(set) var items: [ClipItem]

    public init(items: [ClipItem] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public mutating func push(_ item: ClipItem) {
        items.append(item)
    }

    /// Removes and returns the front item (the next to paste), or nil when empty.
    @discardableResult
    public mutating func popFirst() -> ClipItem? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    public mutating func clear() {
        items.removeAll()
    }
}
