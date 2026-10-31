import Foundation
import GanchoKit

/// The paste queue as a pure value: load several clips, then paste them in
/// order. `push` appends; `takeNext` pastes at the cursor and keeps the pasted
/// entry, so a run shows what already went in ("3 of 5"). Duplicates are
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
    /// How many entries at the front were already pasted in this run.
    public private(set) var cursor = 0
    /// Monotonic per-session entry id source. Never reset (not even on `clear`)
    /// so an id is never reused within a session.
    private var nextID: Int

    public init(entries: [Entry] = []) {
        self.entries = entries
        self.nextID = (entries.map(\.id).max() ?? -1) + 1
    }

    /// A run ends after this long without a stack action.
    public static let idleLimit: TimeInterval = 120

    /// The queued clips in order — what the paste-back path consumes.
    public var items: [ClipItem] { entries.map(\.clip) }
    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }
    /// The entry the next paste takes, nil once every entry went in.
    public var next: Entry? { entries.indices.contains(cursor) ? entries[cursor] : nil }
    /// Entries still waiting to be pasted.
    public var remaining: Int { entries.count - cursor }
    /// A run is active once something was pasted and something is left.
    public var isRunActive: Bool { cursor > 0 && remaining > 0 }

    public mutating func push(_ clip: ClipItem) {
        entries.append(Entry(id: nextID, clip: clip))
        nextID += 1
    }

    /// Appends a visible-order selection as one queue operation. The queue
    /// remains FIFO and duplicate clips still receive distinct entry ids.
    public mutating func push(contentsOf clips: [ClipItem]) {
        for clip in clips { push(clip) }
    }

    /// Returns the clip at the cursor and moves past it. The last one ends
    /// the run, which empties the stack.
    @discardableResult
    public mutating func takeNext() -> ClipItem? {
        guard let next else { return nil }
        cursor += 1
        if remaining == 0 { clear() }
        return next.clip
    }

    /// Moves past the next entry without pasting it; skipping the last one
    /// ends the run like pasting it would.
    public mutating func skip() {
        guard next != nil else { return }
        cursor += 1
        if remaining == 0 { clear() }
    }

    /// Steps back so the next paste repeats the previous entry.
    public mutating func back() {
        cursor = max(0, cursor - 1)
    }

    /// Starts the run again from the first entry.
    public mutating func reset() {
        cursor = 0
    }

    /// Ends the run: pasted entries leave, waiting ones stay for the next run.
    public mutating func endRun() {
        entries.removeFirst(cursor)
        cursor = 0
    }

    public mutating func remove(entryID: Int) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries.remove(at: index)
        if index < cursor { cursor -= 1 }
    }

    /// Same contract as SwiftUI's `move(fromOffsets:toOffset:)` — `destination`
    /// is an offset into the list BEFORE the move — implemented here so this
    /// engine module never links SwiftUI (the macOS 27 SDK moved that helper
    /// into SwiftUICore, which package test products may not link).
    /// Pasted entries stay where they are: only waiting ones move, and never
    /// in front of the cursor.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let source = IndexSet(source.filter { $0 >= cursor })
        let destination = max(destination, cursor)
        let moving = source.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        guard !moving.isEmpty else { return }
        var kept = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = min(destination - source.filter { $0 < destination }.count, kept.count)
        kept.insert(contentsOf: moving, at: max(insertion, 0))
        entries = kept
    }

    public mutating func clear() {
        entries.removeAll()
        cursor = 0
    }
}
