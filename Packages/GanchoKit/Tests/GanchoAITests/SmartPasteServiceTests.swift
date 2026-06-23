import Testing

@testable import GanchoAI

/// The on-device `transform` itself is device-gated + non-deterministic (like
/// the title annotator), so the suite pins the PURE contract: the action set
/// and the prompt instructions that keep it safe and clean.
@Suite("Smart paste — transform actions")
struct SmartPasteServiceTests {
    @Test("Every action has a distinct label/raw value, a symbol, and real instructions")
    func actionMetadata() {
        let actions = SmartPasteAction.allCases
        #expect(actions.count == 6)
        #expect(Set(actions.map(\.titleKey)).count == actions.count)
        #expect(Set(actions.map(\.rawValue)).count == actions.count)
        for action in actions {
            #expect(!action.titleKey.isEmpty)
            #expect(!action.symbolName.isEmpty)
            #expect(action.instructions.count > 20)
        }
    }

    @Test("Every action's instructions forbid leaking secret material")
    func instructionsGuardSecrets() {
        for action in SmartPasteAction.allCases {
            #expect(action.instructions.localizedCaseInsensitiveContains("secret"))
        }
    }

    @Test("Every action tells the model to output only the result (no chatty preamble)")
    func instructionsOutputOnly() {
        for action in SmartPasteAction.allCases {
            #expect(action.instructions.localizedCaseInsensitiveContains("output only"))
        }
    }

    @Test("Translate instructions name the target language and stay secret-safe")
    func translateInstructions() {
        let instructions = SmartPasteService.translateInstructions(to: "French")
        #expect(instructions.contains("French"))
        #expect(instructions.localizedCaseInsensitiveContains("secret"))
        #expect(instructions.localizedCaseInsensitiveContains("output only"))
    }
}
