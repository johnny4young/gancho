import XCTest

/// Settings → Capture: the editable never-capture app list. Drives the real
/// Settings window through the in-process `gancho://settings` launch hook and
/// runs under `make test-ui`. Element exposure is asserted — a missing window,
/// row, or field is a regression — and only synthesized keyboard input skips,
/// because a runner cannot always grant a menu-bar agent the keyboard safely.
///
/// The deterministic path seeds one user entry through the app's own
/// `-seed-denylist-entry` launch hook (same call as the Add button) and then
/// exercises the ROW + REMOVE round-trip with element clicks alone. Typing the
/// bundle id through the real field is covered by the second test.
final class DenylistUITests: XCTestCase {
    /// Sorts before the built-in com.* suggestions, so the seeded row is the
    /// first in the section.
    private let seededBundleID = "app.gancho.uitests.seeded"
    private let typedBundleID = "app.gancho.uitests.typed"

    /// Deterministic acceptance: the seeded entry renders as a row and its
    /// remove button deletes it live (AppModel → SourceAppDenylist →
    /// persistence + the `denylistRevision` refresh).
    @MainActor
    func testSeededEntryShowsAndRemoveDeletesIt() throws {
        let app = try launchIntoCaptureSettings(
            extraArguments: ["-seed-denylist-entry", seededBundleID])
        defer { app.terminate() }

        let row = app.staticTexts[denylistRowIdentifier(for: seededBundleID)].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "the seeded denylist entry must render as a Settings row")

        let remove = app.buttons[denylistRemoveIdentifier(for: seededBundleID)].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        // Wheel events land on the window under the pointer, so the app must be
        // verifiably frontmost before the form is scrolled.
        app.activate()
        try SynthesizedInput.requireForeground(app)
        XCTAssertTrue(
            remove.revealByScrolling(in: captureForm(in: app)),
            "the seeded row's remove button must be reachable in the Capture form")
        remove.click()
        XCTAssertTrue(
            row.waitForNonexistence(timeout: 3),
            "the removed app must leave the list immediately")
    }

    /// The manual add path (bundle-id field + Add). Needs real keyboard focus,
    /// which a menu-bar agent's window doesn't always get under the runner —
    /// the shared typing helper skips rather than typing into whatever else has
    /// the keyboard.
    @MainActor
    func testAddDenylistEntryByTyping() throws {
        let app = try launchIntoCaptureSettings()
        defer { app.terminate() }

        let field = app.textFields["denylist-add-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the manual-entry field must be exposed")
        let form = captureForm(in: app)
        app.activate()
        try SynthesizedInput.requireForeground(app)
        XCTAssertTrue(
            field.revealByScrolling(in: form),
            "the manual-entry field must be reachable in the Capture form")
        try typeTextReliably(typedBundleID, into: field, in: app)
        app.buttons["denylist-add-button"].firstMatch.click()

        let row = app.staticTexts[denylistRowIdentifier(for: typedBundleID)].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the added app must appear in the list")

        // Cleanup doubles as the remove assertion for this path. The new row
        // sorts to the top of the section, away from wherever the form was
        // scrolled to reach the field, so bring it back into view first.
        let remove = app.buttons[denylistRemoveIdentifier(for: typedBundleID)].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        XCTAssertTrue(
            remove.revealByScrolling(in: form),
            "the new row's remove button must be reachable in the Capture form")
        remove.click()
        XCTAssertTrue(row.waitForNonexistence(timeout: 3))
    }

    /// Launches into Settings via the shared launcher and switches to the
    /// Capture tab. Isolated defaults (the denylist persists there), no durable
    /// store, and a paused monitor so nothing on the developer's clipboard is
    /// ingested; the throwaway suite is removed again when the test ends.
    @MainActor
    private func launchIntoCaptureSettings(
        extraArguments: [String] = []
    ) throws -> XCUIApplication {
        let defaultsSuite = "com.johnny4young.gancho.uitests.denylist.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: defaultsSuite) }
        let app = try launchSettingsWindow(
            extraArguments: [
                "-force-ephemeral-store", "-force-free-tier", "-start-capture-paused",
                "-ui-test-defaults-suite", defaultsSuite
            ] + extraArguments)
        let captureTab = app.buttons["settings-tab-capture"].firstMatch
        guard captureTab.waitForExistence(timeout: 3) else {
            XCTFail("Capture tab not exposed to the UI runner")
            app.terminate()
            throw CocoaError(.fileNoSuchFile)
        }
        captureTab.click()
        return app
    }

    /// The grouped Capture form, located through the field it must contain so
    /// the horizontal tab bar (also a scroll view) can never match.
    @MainActor
    private func captureForm(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews.containing(.textField, identifier: "denylist-add-field").firstMatch
    }

    private func denylistRowIdentifier(for bundleID: String) -> String {
        "denylist-row-\(denylistIdentifierSlug(bundleID))"
    }

    private func denylistRemoveIdentifier(for bundleID: String) -> String {
        "denylist-remove-\(denylistIdentifierSlug(bundleID))"
    }

    private func denylistIdentifierSlug(_ bundleID: String) -> String {
        bundleID.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }
}
