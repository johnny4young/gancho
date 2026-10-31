import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Paste stack — queue and run cursor")
struct PasteStackTests {
    private func clip(_ tag: String) -> ClipItem {
        ClipItem(preview: tag, contentHash: tag)
    }

    @Test("push appends and takeNext pastes front to back, ending the run on the last")
    func fifoOrder() {
        var stack = PasteStack()
        let a = clip("a")
        let b = clip("b")
        stack.push(a)
        stack.push(b)
        #expect(stack.count == 2)
        #expect(stack.takeNext()?.id == a.id)
        #expect(stack.takeNext()?.id == b.id)
        #expect(stack.takeNext() == nil)
        #expect(stack.isEmpty)
    }

    @Test("a run keeps pasted entries and counts its position")
    func runKeepsPastedEntries() {
        var stack = PasteStack()
        let clips = (1...5).map { clip("\($0)") }
        stack.push(contentsOf: clips)

        stack.takeNext()
        stack.takeNext()

        #expect(stack.count == 5)
        #expect(stack.cursor == 2)
        #expect(stack.remaining == 3)
        #expect(stack.next?.clip.id == clips[2].id)
        #expect(stack.isRunActive)
    }

    @Test("skip, back and reset move the cursor without pasting")
    func skipBackReset() {
        var stack = PasteStack()
        let clips = (1...3).map { clip("\($0)") }
        stack.push(contentsOf: clips)

        stack.back()
        #expect(stack.cursor == 0, "back at the start stays put")
        stack.skip()
        #expect(stack.next?.clip.id == clips[1].id)
        stack.back()
        #expect(stack.next?.clip.id == clips[0].id)
        stack.takeNext()
        stack.takeNext()
        stack.reset()
        #expect(stack.next?.clip.id == clips[0].id)
        #expect(stack.count == 3)
        stack.skip()
        stack.skip()
        stack.skip()
        #expect(stack.isEmpty, "skipping the last entry ends the run")
    }

    @Test("ending a run drops pasted entries and keeps the waiting ones")
    func endRunKeepsWaiting() {
        var stack = PasteStack()
        let clips = (1...4).map { clip("\($0)") }
        stack.push(contentsOf: clips)
        stack.takeNext()

        stack.endRun()

        #expect(stack.items.map(\.id) == clips.dropFirst().map(\.id))
        #expect(stack.cursor == 0)
        #expect(!stack.isRunActive)
    }

    @Test("removing a pasted entry keeps the cursor on the same next entry")
    func removeBeforeCursor() {
        var stack = PasteStack()
        let clips = (1...3).map { clip("\($0)") }
        stack.push(contentsOf: clips)
        stack.takeNext()

        stack.remove(entryID: stack.entries[0].id)

        #expect(stack.next?.clip.id == clips[1].id)
        #expect(stack.cursor == 0)
    }

    @Test("only waiting entries move, never in front of the cursor")
    func moveRespectsCursor() {
        var stack = PasteStack()
        let clips = (1...4).map { clip("\($0)") }
        stack.push(contentsOf: clips)
        stack.takeNext()

        stack.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(stack.items.map(\.id) == [clips[0], clips[3], clips[1], clips[2]].map(\.id))
        stack.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(stack.items.first?.id == clips[0].id, "a pasted entry stays put")
    }

    @Test("batch push preserves the visible input order")
    func batchOrder() {
        var stack = PasteStack()
        let clips = [clip("first"), clip("second"), clip("third")]

        stack.push(contentsOf: clips)

        #expect(stack.items.map(\.id) == clips.map(\.id))
        #expect(stack.entries.map(\.id) == [0, 1, 2])
    }

    @Test("duplicates are allowed and get distinct entry ids")
    func duplicatesAllowed() {
        var stack = PasteStack()
        let a = clip("a")
        stack.push(a)
        stack.push(a)
        #expect(stack.count == 2)
        // Same clip, but two distinct entry identities.
        #expect(stack.entries[0].id != stack.entries[1].id)
        #expect(stack.entries.allSatisfy { $0.clip.id == a.id })
    }

    @Test("removing one duplicate entry leaves the other (the entry-id fix)")
    func removeOneDuplicate() {
        var stack = PasteStack()
        let a = clip("a")
        stack.push(a)
        stack.push(a)
        stack.remove(entryID: stack.entries[0].id)
        #expect(stack.count == 1)
        #expect(stack.items.first?.id == a.id)
    }

    @Test("remove drops a specific entry, leaving order intact")
    func removeByEntryID() {
        var stack = PasteStack()
        let a = clip("a")
        let b = clip("b")
        let c = clip("c")
        for item in [a, b, c] { stack.push(item) }
        stack.remove(entryID: stack.entries[1].id)
        #expect(stack.items.map(\.id) == [a.id, c.id])
    }

    @Test("move reorders the queue")
    func reorder() {
        var stack = PasteStack()
        let a = clip("a")
        let b = clip("b")
        let c = clip("c")
        for item in [a, b, c] { stack.push(item) }
        // Move the last item to the front.
        stack.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(stack.items.map(\.id) == [c.id, a.id, b.id])
    }

    @Test("move keeps SwiftUI's offset contract: the destination is read before the move")
    func reorderDownwardAndMultiple() {
        var stack = PasteStack()
        let a = clip("a")
        let b = clip("b")
        let c = clip("c")
        let last = clip("d")
        for item in [a, b, c, last] { stack.push(item) }
        // First item to the end: `toOffset: count` means "after the last one".
        stack.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(stack.items.map(\.id) == [b.id, c.id, last.id, a.id])
        // Two non-adjacent items in front of the one at offset 1, in order.
        stack.move(fromOffsets: IndexSet([0, 2]), toOffset: 1)
        #expect(stack.items.map(\.id) == [b.id, last.id, c.id, a.id])
        // Out-of-range and empty sources are no-ops.
        stack.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        stack.move(fromOffsets: IndexSet(), toOffset: 0)
        #expect(stack.items.map(\.id) == [b.id, last.id, c.id, a.id])
    }

    @Test("clear empties the queue but never reuses entry ids")
    func clearAll() {
        var stack = PasteStack()
        stack.push(clip("a"))
        stack.push(clip("b"))
        let usedIDs = Set(stack.entries.map(\.id))
        stack.clear()
        #expect(stack.isEmpty)
        stack.push(clip("c"))
        #expect(usedIDs.contains(stack.entries[0].id) == false, "a cleared id must not be reused")
    }
}
