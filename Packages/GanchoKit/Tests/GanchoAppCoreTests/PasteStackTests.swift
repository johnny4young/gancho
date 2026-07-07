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

    @Test("duplicates are allowed — paste the same clip twice")
    func duplicatesAllowed() {
        var stack = PasteStack()
        let a = clip("a")
        stack.push(a)
        stack.push(a)
        #expect(stack.count == 2)
    }

    @Test("remove drops a specific item, leaving order intact")
    func removeByID() {
        let a = clip("a")
        let b = clip("b")
        let c = clip("c")
        var stack = PasteStack(items: [a, b, c])
        stack.remove(id: b.id)
        #expect(stack.items.map(\.id) == [a.id, c.id])
    }

    @Test("move reorders the queue")
    func reorder() {
        let a = clip("a")
        let b = clip("b")
        let c = clip("c")
        var stack = PasteStack(items: [a, b, c])
        // Move the last item to the front.
        stack.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(stack.items.map(\.id) == [c.id, a.id, b.id])
    }

    @Test("clear empties the queue")
    func clearAll() {
        var stack = PasteStack(items: [clip("a"), clip("b")])
        stack.clear()
        #expect(stack.isEmpty)
    }
}
