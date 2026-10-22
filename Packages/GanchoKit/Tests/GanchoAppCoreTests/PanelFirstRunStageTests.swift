import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("First-run stage — three keys until the first paste")
struct PanelFirstRunStageTests {
    @Test("Shown only for a genuinely empty history before any paste-back")
    func visibility() {
        #expect(
            PanelFirstRunStage.isShown(historyEmpty: true, narrowed: false, hasPastedBack: false))
        #expect(
            !PanelFirstRunStage.isShown(historyEmpty: true, narrowed: false, hasPastedBack: true))
        #expect(
            !PanelFirstRunStage.isShown(historyEmpty: true, narrowed: true, hasPastedBack: false))
        #expect(
            !PanelFirstRunStage.isShown(historyEmpty: false, narrowed: false, hasPastedBack: false))
    }

    @Test("Shortcuts split into modifier caps and one key cap")
    func keycaps() {
        #expect(PanelFirstRunStage.keycaps(for: "⇧⌘V") == ["⇧", "⌘", "V"])
        #expect(PanelFirstRunStage.keycaps(for: "⌥Space") == ["⌥", "Space"])
        #expect(PanelFirstRunStage.keycaps(for: "F5") == ["F5"])
        #expect(PanelFirstRunStage.keycaps(for: "").isEmpty)
    }

    @Test("Paste-back methods stamp the first paste; a drag or a copy does not")
    func pasteBackMethods() {
        #expect(
            SuccessfulReuseMethod.allCases.filter(\.isPasteBack) == [
                .paste, .transform, .snippet, .smartPaste
            ])
    }
}
