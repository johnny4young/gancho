import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Paste stack — what the peek shows")
struct PasteStackPresentationTests {
    private func stack(_ count: Int, pasted: Int = 0) -> PasteStack {
        var stack = PasteStack()
        stack.push(contentsOf: (1...count).map { ClipItem(preview: "\($0)", contentHash: "\($0)") })
        for _ in 0..<pasted { stack.takeNext() }
        return stack
    }

    @Test("rows are pasted before the cursor, next at it and waiting after")
    func rowStates() {
        let shown = PasteStackPresentation(stack: stack(4, pasted: 1))
        #expect(shown.rows.map(\.state) == [.pasted, .next, .waiting, .waiting])
        #expect(shown.rows.map(\.number) == [1, 2, 3, 4])
        #expect(shown.position == "2/4")
        #expect(shown.isRunActive)
    }

    @Test("a stack nobody started shows its first entry as next")
    func beforeTheRun() {
        let shown = PasteStackPresentation(stack: stack(3))
        #expect(shown.rows.map(\.state) == [.next, .waiting, .waiting])
        #expect(shown.position == "1/3")
        #expect(!shown.isRunActive)
    }

    @Test("an empty stack has no rows and nothing to paste")
    func empty() {
        let shown = PasteStackPresentation(stack: PasteStack())
        #expect(shown.rows.isEmpty)
        #expect(shown.position == "0/0")
        #expect(shown.dock(skipKey: nil, backKey: nil).first?.isEnabled == false)
    }

    @Test("duplicates of one clip are distinct rows")
    func duplicates() {
        var stack = PasteStack()
        let clip = ClipItem(preview: "a", contentHash: "a")
        stack.push(clip)
        stack.push(clip)
        let shown = PasteStackPresentation(stack: stack)
        #expect(Set(shown.rows.map(\.id)).count == 2)
    }

    @Test("Skip and Back show only a recorded key; Reset shows none")
    func dockKeys() {
        let shown = PasteStackPresentation(stack: stack(3, pasted: 1))
        let bare = shown.dock(skipKey: nil, backKey: "")
        #expect(bare.map(\.verb) == [.pasteNext, .skip, .back, .reset, .end])
        #expect(bare.map(\.key) == ["↩", nil, nil, nil, "esc"])
        let recorded = shown.dock(skipKey: "⌃⌥S", backKey: "⌃⌥B")
        #expect(recorded.map(\.key) == ["↩", "⌃⌥S", "⌃⌥B", nil, "esc"])
    }

    @Test("Back and Reset wait for the first paste")
    func dockEnabled() {
        let fresh = PasteStackPresentation(stack: stack(2)).dock(skipKey: nil, backKey: nil)
        #expect(fresh.map(\.isEnabled) == [true, true, false, false, true])
        let running = PasteStackPresentation(stack: stack(2, pasted: 1))
            .dock(skipKey: nil, backKey: nil)
        #expect(running.map(\.isEnabled) == [true, true, true, true, true])
    }

    @Test("only rows still to paste move, and never in front of the next one")
    func moves() throws {
        var queue = stack(4, pasted: 1)
        let shown = PasteStackPresentation(stack: queue)
        #expect(shown.rows.map(\.canMoveUp) == [false, false, true, true])
        #expect(shown.rows.map(\.canMoveDown) == [false, true, true, false])
        #expect(shown.move(shown.rows[0].id, up: false) == nil)
        #expect(shown.move(shown.rows[1].id, up: true) == nil)

        let up = try #require(shown.move(shown.rows[3].id, up: true))
        queue.move(fromOffsets: up.source, toOffset: up.destination)
        #expect(queue.entries.map(\.id) == [0, 1, 3, 2])

        let down = try #require(PasteStackPresentation(stack: queue).move(1, up: false))
        queue.move(fromOffsets: down.source, toOffset: down.destination)
        #expect(queue.entries.map(\.id) == [0, 3, 1, 2])
        #expect(queue.cursor == 1)
    }
}
