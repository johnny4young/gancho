import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Onboarding flow — four steps, footer actions and the secret lifetime copy")
struct OnboardingFlowTests {
    @Test("The steps run promise → permission → shortcuts → first copy, with no wrap")
    func order() {
        #expect(OnboardingStep.allCases == [.promise, .permission, .shortcuts, .firstCopy])
        #expect(OnboardingStep.promise.previous == nil)
        #expect(OnboardingStep.firstCopy.next == nil)
        #expect(OnboardingStep.permission.next == .shortcuts)
    }

    @Test("Only the permission step's skip moves on; the others close")
    func leadingAction() {
        let advancing = OnboardingStep.allCases.filter { $0.leadingAction == .advance }
        #expect(advancing == [.permission])
    }

    @Test("Without Accessibility the permission step opens System Settings")
    func primaryAction() {
        #expect(
            OnboardingStep.permission.primaryAction(accessibilityGranted: false)
                == .openAccessibilitySettings)
        #expect(OnboardingStep.permission.primaryAction(accessibilityGranted: true) == .advance)
        #expect(OnboardingStep.promise.primaryAction(accessibilityGranted: false) == .advance)
        #expect(OnboardingStep.firstCopy.primaryAction(accessibilityGranted: false) == .openPanel)
    }

    @Test("The promise follows the configured secret lifetime", arguments: [300.0, 600.0, 1800.0])
    func lifetimeFollowsThePolicy(seconds: Double) {
        let english = OnboardingCopy.secretLifetime(seconds, locale: Locale(identifier: "en_US"))
        #expect(english == "\(Int(seconds) / 60) minutes")
        let spanish = OnboardingCopy.secretLifetime(seconds, locale: Locale(identifier: "es_CO"))
        #expect(spanish == "\(Int(seconds) / 60) minutos")
    }

    @Test("An hour reads as an hour, and a sub-minute lifetime never reads as zero")
    func lifetimeEdges() {
        let english = Locale(identifier: "en_US")
        #expect(OnboardingCopy.secretLifetime(3600, locale: english) == "1 hour")
        #expect(OnboardingCopy.secretLifetime(0, locale: english) == "1 minute")
    }
}
