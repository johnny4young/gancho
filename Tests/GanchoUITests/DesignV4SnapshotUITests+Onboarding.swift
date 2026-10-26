import XCTest

/// The Mac first run, one baseline per step: the promise, the permission
/// (not granted), the three shortcuts and the live first copy.
extension DesignV4SnapshotUITests {
    @MainActor func testOnboardingStepsLight() throws {
        for step in 0..<4 { try onboarding(step: step, appearance: "light") }
    }

    @MainActor func testOnboardingStepsDark() throws {
        for step in 0..<4 { try onboarding(step: step, appearance: "dark") }
    }

    @MainActor private func onboarding(step: Int, appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-peek-link", "-force-capture-active",
            "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
            "-isolate-ui-test-system-clipboard",
            "-ui-test-onboarding-step", "\(step)", "-ui-test-accessibility-trusted", "NO",
            // Recorded shortcuts live in the standard defaults; the argument domain pins
            // ⇧⌘V and leaves the other two unset, whatever this Mac recorded.
            "-KeyboardShortcuts_toggle-panel", #""{\"carbonKeyCode\":9,\"carbonModifiers\":768}""#,
            "-KeyboardShortcuts_paste-from-stack", "none",
            "-KeyboardShortcuts_toggle-private-mode", "none",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-ui-test-snapshot-dir", renders.path
        ]
        app.launch()
        defer { app.terminate() }
        // Every capture shows the key window, so the traffic lights never vary.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-page-dots"].firstMatch
                .waitForExistence(timeout: 8))
        if step == 3 {
            XCTAssertTrue(
                app.descendants(matching: .any)["clip-row"].firstMatch
                    .waitForExistence(timeout: 5))
        }
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Welcome to Gancho", named: "onboarding", in: renders),
            named: "onboarding-step\(step + 1)-\(appearance)")
    }
}
