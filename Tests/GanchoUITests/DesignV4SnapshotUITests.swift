import AppKit
import XCTest

/// Image baselines for the surfaces the design v4 phases change. Each test
/// pins the store, tier, language, appearance and capture state so the only
/// moving part is the UI under test. Windows are rendered by the app itself
/// (`-ui-test-snapshot-dir`), so a capture never contains another app's window.
final class DesignV4SnapshotUITests: XCTestCase {
    private var renders: URL!

    override func setUpWithError() throws {
        try DesignSnapshot.skipUnlessEnabled()
        continueAfterFailure = true
        renders = try DesignSnapshot.makeRenderDirectory()
    }

    override func tearDownWithError() throws {
        if let renders { try? FileManager.default.removeItem(at: renders) }
    }

    // MARK: Settings sidebar — the focus ring follows the clicked row.

    @MainActor func testSettingsSidebarAfterSelectingCaptureLight() throws {
        try settingsSidebar(appearance: "light")
    }

    @MainActor func testSettingsSidebarAfterSelectingCaptureDark() throws {
        try settingsSidebar(appearance: "dark")
    }

    @MainActor private func settingsSidebar(appearance: String) throws {
        let app = try launchSettingsWindow(extraArguments: stableArguments(appearance))
        defer { app.terminate() }
        let capture = app.windows["Settings"].buttons["settings-tab-capture"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.click()
        XCTAssertTrue(capture.isSelected)
        let window = try DesignSnapshot.renderWindow(
            titled: "Settings", named: "settings-\(appearance)", in: renders)
        try DesignSnapshot.save(
            DesignSnapshot.crop(window, to: CGRect(x: 0, y: 0, width: 210, height: 330)),
            named: "settings-sidebar-\(appearance)")
    }

    // MARK: Intelligence — five pipeline stages and every row icon.

    @MainActor func testIntelligenceWindowLight() throws {
        try intelligence(appearance: "light")
    }

    @MainActor func testIntelligenceWindowDark() throws {
        try intelligence(appearance: "dark")
    }

    @MainActor private func intelligence(appearance: String) throws {
        let app = try launchSettingsWindow(
            extraArguments: stableArguments(appearance) + ["-simulate-sequoia-capabilities"])
        defer { app.terminate() }
        app.buttons["settings-tab-capture"].firstMatch.click()
        let open = app.buttons["open-intelligence"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.click()
        XCTAssertTrue(app.windows["Intelligence"].firstMatch.waitForExistence(timeout: 5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Intelligence", named: "intelligence", in: renders),
            named: "intelligence-\(appearance)")
    }

    // MARK: Onboarding — the brand mark heads the first step.

    @MainActor func testOnboardingFirstStepLight() throws {
        try onboardingFirstStep(appearance: "light")
    }

    @MainActor func testOnboardingFirstStepDark() throws {
        try onboardingFirstStep(appearance: "dark")
    }

    @MainActor private func onboardingFirstStep(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-ui-test-snapshot-dir", renders.path
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["onboarding-continue"].firstMatch.waitForExistence(timeout: 8))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Welcome to Gancho", named: "onboarding", in: renders),
            named: "onboarding-step1-\(appearance)")
    }

    // The status menu is not captured: it is drawn by the system with vibrancy
    // over whatever sits behind it. MenuBarShortcutUITests checks its shortcut.

    // MARK: Wrapped — the exported card carries the brand mark.

    @MainActor func testWrappedCard() throws {
        let output = renders.appendingPathComponent("wrapped.png")
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-start-capture-paused", "-has-seen-welcome", "YES",
            "-AppleLanguages", "(en)", "-appearance", "light",
            "-command-nonce", token, "-ui-test-wrapped-output", output.path,
            // Pin the paste-back counter the card reads from standard defaults.
            "-first-pasteback-at", "2026-01-01", "-pasteback-count", "3"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 8)
        GanchoUITestCommands.post("wrapped", token: token)
        let image = try XCTUnwrap(
            DesignSnapshot.waitForImage(at: output), "Wrapped PNG was not written")
        try DesignSnapshot.save(image, named: "wrapped-card")
    }

    /// Keyboard UI mode 2 is full keyboard access, so focus rings are drawn.
    private func stableArguments(
        _ appearance: String, keyboardUIMode: String = "2"
    )
        -> [String]
    {
        [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", appearance,
            "-AppleKeyboardUIMode", keyboardUIMode,
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)",
            "-ui-test-snapshot-dir", renders.path
        ]
    }
}
