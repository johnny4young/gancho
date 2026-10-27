import Foundation
import Testing

@testable import GanchoAI

@Suite("Intelligence capability")
struct IntelligenceCapabilityTests {
    @Test("The simulate argument forces the unavailable answer")
    func simulateArgumentWins() {
        #expect(
            IntelligenceCapability.current(
                arguments: [IntelligenceCapability.simulateModelUnavailableArgument])
                == .modelUnavailable)
    }

    @Test("Without the argument, the answer follows the on-device model")
    func genuineAnswerFollowsModel() {
        let expected: IntelligenceCapability =
            SmartPasteService.isAvailable ? .available : .modelUnavailable
        #expect(IntelligenceCapability.current(arguments: []) == expected)
    }

    @Test("Only the available case may use the model")
    func onlyAvailableUsesModel() {
        #expect(IntelligenceCapability.available.canUseModel)
        #expect(!IntelligenceCapability.modelUnavailable.canUseModel)
    }
}
