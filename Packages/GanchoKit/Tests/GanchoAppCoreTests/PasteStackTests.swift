import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Paste stack — FIFO queue")
struct PasteStackTests {
    private func clip(_ tag: String) -> ClipItem {
        ClipItem(preview: tag, contentHash: tag)
    }

    @Test("push appends and popFirst returns front-to-back")
    func fifoOrder() {
        var stack = PasteStack()
        let a = clip("a")
        let b = clip("b")
        stack.push(a)
        stack.push(b)
        #expect(stack.count == 2)
        #expect(stack.popFirst()?.id == a.id)
        #expect(stack.popFirst()?.id == b.id)
        #expect(stack.popFirst() == nil)
        #expect(stack.isEmpty)
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
