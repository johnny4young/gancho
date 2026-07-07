import Foundation
import GanchoKit

/// The paste queue as a pure value: load several clips, then paste them in
/// order. FIFO — `push` appends, `popFirst` takes the front. Duplicates are
/// allowed on purpose (pasting the same clip twice in a row is a real use), so
/// each enqueue is a distinct `Entry` with its own stable `id`: a clip's own
/// `ClipItem.id` can appear twice, which would collide as a SwiftUI list
/// identity and make "remove just this one" impossible. remove/move operate on
/// the entry id, never the clip id.
///
/// Lives here (not in the app target) so its ordering is unit-tested headless;
/// `AppModel` owns one and routes the paste-back side effect. The queue is a
/// session working set: it never persists and never syncs.
public struct PasteStack: Equatable, Sendable {
    /// One queued clip with an identity independent of the clip itself, so
    /// duplicates stay individually addressable and SwiftUI-stable.
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: Int
        public let clip: ClipItem
    }

    public private(set) var entries: [Entry]
    /// Monotonic per-session entry id source. Never reset (not even on `clear`)
    /// so an id is never reused within a session.
    private var nextID: Int

    public init(entries: [Entry] = []) {
        self.entries = entries
        self.nextID = (entries.map(\.id).max() ?? -1) + 1
    }

    /// The queued clips in order — what the paste-back path consumes.
    public var items: [ClipItem] { entries.map(\.clip) }
    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    public mutating func push(_ clip: ClipItem) {
        entries.append(Entry(id: nextID, clip: clip))
        nextID += 1
    }

    /// Removes and returns the front clip (the next to paste), or nil when empty.
    @discardableResult
    public mutating func popFirst() -> ClipItem? {
        entries.isEmpty ? nil : entries.removeFirst().clip
    }

    public mutating func remove(entryID: Int) {
        entries.removeAll { $0.id == entryID }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    public mutating func clear() {
        entries.removeAll()
    }
}
