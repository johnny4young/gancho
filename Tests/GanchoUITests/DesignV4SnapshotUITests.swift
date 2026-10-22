import AppKit
import XCTest

/// Image baselines for the surfaces the design v4 phases change. Each test
/// pins the store, tier, language, appearance and capture state so the only
/// moving part is the UI under test.
final class DesignV4SnapshotUITests: XCTestCase {
    override func setUpWithError() throws {
        try DesignSnapshot.skipUnlessEnabled()
        continueAfterFailure = true
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
        let window = app.windows["Settings"].firstMatch
        let capture = window.buttons["settings-tab-capture"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.click()
        XCTAssertTrue(capture.isSelected)
        try DesignSnapshot.save(
            DesignSnapshot.image(of: window, crop: CGRect(x: 0, y: 0, width: 210, height: 330)),
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
        let window = app.windows["Intelligence"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        try DesignSnapshot.save(
            DesignSnapshot.image(of: window), named: "intelligence-\(appearance)")
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
            "-appearance", appearance
        ]
        app.launch()
        defer { app.terminate() }
        let next = app.buttons["onboarding-continue"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        let window = app.windows.containing(.button, identifier: "onboarding-continue").firstMatch
        try DesignSnapshot.save(
            DesignSnapshot.image(of: window), named: "onboarding-step1-\(appearance)")
    }

    // MARK: Status menu — Open panel shows the recorded panel shortcut.

    @MainActor func testStatusMenuWithRecordedShortcut() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-force-ephemeral-store", "-start-capture-paused", "-AppleLanguages", "(en)",
            "-appearance", "light",
            "-KeyboardShortcuts_toggle-panel",
            #""{\"carbonKeyCode\":9,\"carbonModifiers\":2304}""#
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5), statusItem.isHittable else {
            throw XCTSkip("status item not hittable on this display/Space")
        }
        statusItem.click()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        try DesignSnapshot.save(DesignSnapshot.image(of: menu), named: "status-menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: Wrapped — the exported card carries the brand mark.

    @MainActor func testWrappedCard() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-wrapped-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
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
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: output.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let image = try XCTUnwrap(NSImage(contentsOf: output), "Wrapped PNG was not written")
        try DesignSnapshot.save(image, named: "wrapped-card")
    }

    private func stableArguments(_ appearance: String) -> [String] {
        [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", appearance,
            // Full keyboard access, so the focus ring the fix moves is drawn.
            "-AppleKeyboardUIMode", "2",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)"
        ]
    }
}
