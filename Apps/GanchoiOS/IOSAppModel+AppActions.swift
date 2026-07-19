import GanchoKit

/// Small user-triggered actions kept outside the iOS composition root. They
/// use only the model's capability handles and observable state.
extension IOSAppModel {
    func requestTelemetryConsentAfterFirstValue() {
        guard telemetryConsent == .notAsked else { return }
        isTelemetryConsentPromptPresented = true
    }

    func completeOnboarding() {
        recordActivationMilestone(.onboardingCompleted)
    }

    /// The Privacy Center waits for its isolated UI fixture when present, then
    /// reads the same durable first-party facet production uses.
    func privateActivityReceipt() async -> PrivateActivityReceipt {
        await uiTestPrivateActivityReceiptSeedTask?.value
        return (try? await full?.privateActivityReceipt(now: .now)) ?? .empty()
    }

    func clearPrivateActivityReceipt() async {
        try? await full?.clearPrivateActivityReceipt()
    }

    func forceSync() async {
        // Start = "run a sync cycle now" on the boundary; the CloudKit
        // adapter gives it real semantics during on-device verification.
        await syncController.forceSync()
        await refreshHints()
    }

    /// Pull the latest from iCloud (and push pending) when the app comes
    /// forward, so another device's recent clips appear without a pull-to-
    /// refresh. The engine is push-driven on its own; this is the latency
    /// belt-and-braces for foregrounding (and pushes iOS coalesced while the
    /// app was suspended). The status observer refreshes the list on settle.
    func syncNow() {
        syncController.syncNow()
    }
}
