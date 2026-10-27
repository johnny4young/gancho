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

    @Test("Only the available case may use the model")
    func onlyAvailableUsesModel() {
        #expect(IntelligenceCapability.available.canUseModel)
        #expect(!IntelligenceCapability.modelUnavailable.canUseModel)
    }
}
