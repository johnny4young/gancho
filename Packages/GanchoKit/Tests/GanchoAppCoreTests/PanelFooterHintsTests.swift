import Testing

@testable import GanchoAppCore

@Suite("Panel footer — key hints follow the panel's state")
struct PanelFooterHintsTests {
    private func state(
        actionPanel: Bool = false, stack: Bool = false, historyEmpty: Bool = false,
        narrowed: Bool = false, listIsEmpty: Bool = false
    ) -> PanelFooterState {
        .resolve(
            actionPanelIsOpen: actionPanel, stackIsOpen: stack, historyEmpty: historyEmpty,
            narrowed: narrowed, listIsEmpty: listIsEmpty)
    }

    @Test("The action panel wins, then the stack, then an empty history, then no matches")
    func resolution() {
        #expect(state(actionPanel: true, stack: true) == .actionPanel)
        #expect(state(stack: true, historyEmpty: true) == .stack)
        #expect(state(historyEmpty: true, listIsEmpty: true) == .empty)
        #expect(state(historyEmpty: true, narrowed: true, listIsEmpty: true) == .noMatches)
        #expect(state(narrowed: true, listIsEmpty: true) == .noMatches)
        #expect(state(narrowed: true) == .list)
        // Rows still loading, or a search in flight, are not "no matches".
        #expect(state(listIsEmpty: true) == .list)
    }

    @Test("Each state shows its own keys")
    func hintsPerState() {
        #expect(PanelFooterHint.hints(for: .list) == [.navigate, .pasteNth, .keys])
        #expect(PanelFooterHint.pasteNth.rawValue == "paste-nth")
        #expect(PanelFooterHint.hints(for: .actionPanel) == [.pick, .run, .close])
        #expect(PanelFooterHint.hints(for: .stack) == [.addToStack, .navigate, .keys])
        #expect(PanelFooterHint.hints(for: .noMatches) == [.navigate, .keys])
        #expect(PanelFooterHint.hints(for: .empty) == [.settings, .keys])
    }

    @Test("Nothing to pick drops navigate and paste nth from an empty history")
    func emptyHasNothingToPick() {
        let hints = PanelFooterHint.hints(for: .empty, privateModeOff: true)
        #expect(hints == [.privateModeOff, .settings, .keys])
        #expect(!PanelFooterHint.hints(for: .noMatches).contains(.pasteNth))
    }

    @Test("The alternative, eyedropper and Private Mode hints lead where they apply")
    func conditionalHints() {
        #expect(
            PanelFooterHint.hints(for: .noMatches, hasAlternative: true, privateModeOff: true)
                == [.alternative, .privateModeOff, .navigate, .keys])
        #expect(
            PanelFooterHint.hints(for: .list, offersEyedropper: true, privateModeOff: true)
                == [.eyedropper, .privateModeOff, .navigate, .pasteNth, .keys])
        #expect(
            PanelFooterHint.hints(for: .stack, offersEyedropper: true, privateModeOff: true)
                == [.privateModeOff, .addToStack, .navigate, .keys])
        #expect(
            PanelFooterHint.hints(
                for: .actionPanel, hasAlternative: true, offersEyedropper: true,
                privateModeOff: true) == [.pick, .run, .close])
    }
}
