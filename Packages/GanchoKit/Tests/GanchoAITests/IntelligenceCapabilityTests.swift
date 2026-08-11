import Foundation
import Testing

@testable import GanchoAI

@Suite("Intelligence capability")
struct IntelligenceCapabilityTests {
    @Test("The simulate-Sequoia argument forces the pre-26 answer on macOS")
    func simulateArgumentWins() {
        #if os(macOS)
            #expect(
                IntelligenceCapability.current(
                    arguments: [IntelligenceCapability.simulateSequoiaArgument])
                    == .requiresMacOS26)
        #else
            #expect(
                IntelligenceCapability.current(
                    arguments: [IntelligenceCapability.simulateSequoiaArgument])
                    != .requiresMacOS26)
        #endif
    }

    /// The genuine answer tracks the running OS, so this expectation is split
    /// by availability rather than hard-coding the host the suite runs on.
    @Test("Without the argument, requiresMacOS26 mirrors the running OS")
    func genuineAnswerMirrorsOS() {
        let capability = IntelligenceCapability.current(arguments: [])
        if #available(macOS 26.0, iOS 26.0, *) {
            #expect(capability != .requiresMacOS26)
        } else {
            #expect(capability == .requiresMacOS26)
        }
    }

    @Test("Only the available case may use the model")
    func onlyAvailableUsesModel() {
        #expect(IntelligenceCapability.available.canUseModel)
        #expect(!IntelligenceCapability.requiresMacOS26.canUseModel)
        #expect(!IntelligenceCapability.modelUnavailable.canUseModel)
    }
}
