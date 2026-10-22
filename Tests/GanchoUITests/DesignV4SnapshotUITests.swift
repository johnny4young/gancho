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

    // MARK: Panel — dock states, chips, selection wash and the opaque surface.

    @MainActor func testPanelLinkPeekLight() throws {
        try panel(appearance: "light")
    }

    @MainActor func testPanelLinkPeekDark() throws {
        try panel(appearance: "dark")
    }

    /// The 11 pt chips at the two other Text size steps (9.9 and 12.65 pt).
    @MainActor func testPanelLinkPeekSmallText() throws {
        try panel(appearance: "light", textSize: "small")
    }

    @MainActor func testPanelLinkPeekLargeText() throws {
        try panel(appearance: "light", textSize: "large")
    }

    @MainActor private func panel(appearance: String, textSize: String = "standard") throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-peek-link", "-force-free-tier",
            "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-panel-text-size", textSize,
            "-ui-test-snapshot-dir", renders.path, "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "example.com")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-dock"].firstMatch.waitForExistence(timeout: 5))
        // Let the selection and peek animations settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: textSize == "standard"
                ? "panel-link-peek-\(appearance)" : "panel-link-peek-\(textSize)-text")
    }

    // MARK: Settings › Privacy and Privacy Center — neutral buttons, dark ink hero.

    @MainActor func testSettingsPrivacyLight() throws {
        let app = try launchSettingsWindow(extraArguments: stableArguments("light"))
        defer { app.terminate() }
        let privacy = app.windows["Settings"].buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        privacy.click()
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Settings", named: "settings", in: renders),
            named: "settings-privacy-light")
    }

    @MainActor func testPrivacyCenterLight() throws {
        try privacyCenter(appearance: "light")
    }

    @MainActor func testPrivacyCenterDark() throws {
        try privacyCenter(appearance: "dark")
    }

    @MainActor private func privacyCenter(appearance: String) throws {
        let token = UUID().uuidString
        let app = try launchSettingsWindow(
            extraArguments: stableArguments(appearance) + ["-command-nonce", token])
        defer { app.terminate() }
        GanchoUITestCommands.post("privacyCenter", token: token)
        XCTAssertTrue(app.windows["Privacy Center"].firstMatch.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Privacy Center", named: "privacy-center", in: renders),
            named: "privacy-center-\(appearance)")
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
