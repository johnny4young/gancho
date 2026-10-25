import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Menu-bar menu plan — the status item's mini-panel")
struct MenuBarMenuPlanTests {
    private func clips(_ count: Int) -> [ClipItem] {
        (0..<count).map { ClipItem(kind: .text, preview: "clip \($0)", contentHash: "h\($0)") }
    }

    private func recents(_ plan: MenuBarMenuPlan) -> [MenuBarMenuPlan.Recent] {
        plan.entries.compactMap { if case .recent(let recent) = $0 { recent } else { nil } }
    }

    private func commands(_ plan: MenuBarMenuPlan) -> [MenuBarMenuPlan.Command] {
        plan.entries.compactMap { if case .command(let command) = $0 { command } else { nil } }
    }

    @Test("Header, five recents numbered ⌘1–5, then the commands in the board's order")
    func order() {
        let plan = MenuBarMenuPlan(
            recents: clips(MenuBarMenuPlan.recentLimit + 2), stack: [], previewsHidden: false,
            accessDenied: false)
        #expect(plan.entries.prefix(2) == [.header, .recentsLabel])
        #expect(recents(plan).map(\.number) == Array(1...MenuBarMenuPlan.recentLimit))
        #expect(
            commands(plan) == [
                .openPanel, .library, .copyScreenText, .toggleCapture, .togglePrivateMode,
                .ignoreNextCopy, .settings, .privacyCenter, .welcome, .wrapped, .quit
            ])
        #expect(plan.entries.last == .command(.quit))
    }

    @Test("Sensitive clips are masked, and hidden previews mask every row")
    func masking() {
        var items = clips(2)
        items[1].isSensitive = true
        let shown = MenuBarMenuPlan(
            recents: items, stack: [], previewsHidden: false, accessDenied: false)
        #expect(recents(shown).map(\.masked) == [false, true])
        let hidden = MenuBarMenuPlan(
            recents: items, stack: [], previewsHidden: true, accessDenied: false)
        #expect(recents(hidden).map(\.masked) == [true, true])
    }

    @Test("The stack row sits after Library only while something waits")
    func stackRow() {
        let empty = MenuBarMenuPlan(
            recents: clips(1), stack: [], previewsHidden: false, accessDenied: false)
        #expect(!empty.entries.contains { if case .stack = $0 { true } else { false } })

        let waiting = clips(3)
        let plan = MenuBarMenuPlan(
            recents: clips(1), stack: waiting, previewsHidden: true, accessDenied: false)
        let library = plan.entries.firstIndex(of: .command(.library))!
        guard case .stack(let stack) = plan.entries[library + 1] else {
            Issue.record("no stack row after Library")
            return
        }
        #expect(stack.waiting == waiting.count)
        #expect(stack.next == waiting[0])
        #expect(stack.nextMasked)
    }

    @Test("No recents says so; denied access offers Fix under the header")
    func emptyAndDenied() {
        let plan = MenuBarMenuPlan(
            recents: [], stack: [], previewsHidden: false, accessDenied: true)
        #expect(
            Array(plan.entries.prefix(4)) == [
                .header, .command(.fixClipboardAccess), .recentsLabel, .noRecents
            ])
    }
}
