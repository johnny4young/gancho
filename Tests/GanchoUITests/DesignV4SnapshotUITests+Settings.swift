import AppKit
import XCTest

extension DesignV4SnapshotUITests {
    // MARK: Settings › Capture and Retention — the concealed rule, the timeline.

    @MainActor func testSettingsCaptureLight() throws {
        try settingsPane("capture", waitingFor: "capture-concealed-rule-card", appearance: "light")
    }

    @MainActor func testSettingsCaptureDark() throws {
        try settingsPane("capture", waitingFor: "capture-concealed-rule-card", appearance: "dark")
    }

    @MainActor func testSettingsRetentionLight() throws {
        try settingsPane("retention", waitingFor: "retention-timeline", appearance: "light")
    }

    @MainActor func testSettingsRetentionDark() throws {
        try settingsPane("retention", waitingFor: "retention-timeline", appearance: "dark")
    }

    @MainActor func settingsPane(
        _ tab: String, waitingFor identifier: String, appearance: String
    ) throws {
        let app = try launchSettingsWindow(extraArguments: stableArguments(appearance))
        defer { app.terminate() }
        let button = app.windows["Settings"].buttons["settings-tab-\(tab)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
        XCTAssertTrue(
            app.windows["Settings"].descendants(matching: .any)[identifier].firstMatch
                .waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Settings", named: "settings", in: renders),
            named: "settings-\(tab)-\(appearance)")
    }
}
