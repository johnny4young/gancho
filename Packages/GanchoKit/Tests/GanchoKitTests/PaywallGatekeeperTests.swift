import Testing

@testable import GanchoKit

@Suite("Paywall gating — value before paywall")
struct PaywallGatekeeperTests {
    @Test("Contextual triggers wait for the first paste-back")
    func contextualWaitsForValue() {
        #expect(
            !PaywallGatekeeper.shouldShow(
                trigger: .freeLimitReached, tier: .free, hasPastedBackOnce: false))
        #expect(
            PaywallGatekeeper.shouldShow(
                trigger: .freeLimitReached, tier: .free, hasPastedBackOnce: true))
        #expect(
            !PaywallGatekeeper.shouldShow(
                trigger: .proFeatureTouched, tier: .free, hasPastedBackOnce: false))
    }

    @Test("Settings Pro is user navigation — always allowed on free")
    func settingsAlwaysAllowed() {
        #expect(
            PaywallGatekeeper.shouldShow(
                trigger: .settingsPro, tier: .free, hasPastedBackOnce: false))
    }

    @Test("Pro users never see a paywall")
    func proNeverSees() {
        for trigger in PaywallGatekeeper.Trigger.allCases {
            #expect(
                !PaywallGatekeeper.shouldShow(
                    trigger: trigger, tier: .pro, hasPastedBackOnce: true))
        }
    }
}
