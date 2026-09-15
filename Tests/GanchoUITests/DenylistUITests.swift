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
    /// A built-in exclusion that ships installed on every Mac.
    private let builtInBundleID = "com.apple.Passwords"

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
        // A failed assertion does not stop the test, and a click on a button
        // that never came into view must not run: stop here instead.
        guard remove.revealByScrolling(in: captureForm(in: app)) else {
            XCTFail("the seeded row's remove button must be reachable in the Capture form")
            return
        }
        remove.click()
        XCTAssertTrue(
            row.waitForNonexistence(timeout: 3),
            "the removed app must leave the list immediately")
    }

    /// The manual add path: Add app → By bundle identifier… reveals the field,
    /// which validates as you type (Add stays disabled and the reason shows
    /// under it until the text has a bundle identifier's shape). Needs real
    /// keyboard focus, which a menu-bar agent's window doesn't always get under
    /// the runner — the shared typing helper skips rather than typing into
    /// whatever else has the keyboard.
    @MainActor
    func testAddDenylistEntryByTyping() throws {
        let app = try launchIntoCaptureSettings()
        defer { app.terminate() }

        let form = captureForm(in: app)
        let addMenu = app.descendants(matching: .any)["denylist-add-menu"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3), "the Add app menu must be exposed")
        app.activate()
        try SynthesizedInput.requireForeground(app)
        guard addMenu.revealByScrolling(in: form) else {
            XCTFail("the Add app menu must be reachable in the Capture form")
            return
        }
        addMenu.click()
        let byIdentifier = app.menuItems["By bundle identifier…"].firstMatch
        XCTAssertTrue(
            byIdentifier.waitForExistence(timeout: 3), "the menu must list the typed path")
        byIdentifier.click()

        let field = app.textFields["denylist-add-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the manual-entry field must appear")
        let add = app.buttons["denylist-add-button"].firstMatch
        let error = app.staticTexts["denylist-add-error"].firstMatch

        // A bare word is refused live: Add stays off and the reason is shown.
        try typeTextReliably("safari", into: field, in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 2), "an implausible id must explain itself")
        XCTAssertFalse(add.isEnabled, "Add must stay disabled for an implausible id")

        // The helper select-all-replaces, so this is the corrected entry.
        try typeTextReliably(typedBundleID, into: field, in: app)
        XCTAssertTrue(error.waitForNonexistence(timeout: 2), "a plausible id clears the error")
        XCTAssertTrue(add.isEnabled)
        add.click()

        let row = app.staticTexts[denylistRowIdentifier(for: typedBundleID)].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the added app must appear in the list")
        XCTAssertTrue(
            field.waitForNonexistence(timeout: 2), "adding folds the field back into the menu")

        // Cleanup doubles as the remove assertion for this path.
        let remove = app.buttons[denylistRemoveIdentifier(for: typedBundleID)].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        guard remove.revealByScrolling(in: form) else {
            XCTFail("the new row's remove button must be reachable in the Capture form")
            return
        }
        remove.click()
        XCTAssertTrue(row.waitForNonexistence(timeout: 3))
    }

    /// Adding a built-in app (the seed takes the same model call as every Add
    /// path) keeps one control: its switch under Built-in exclusions, never a
    /// removable user row whose removal would switch the protection off.
    /// Switching it off and restoring the defaults drive that same switch.
    @MainActor
    func testAddingABuiltInAppKeepsOneSwitch() throws {
        let app = try launchIntoCaptureSettings(
            extraArguments: ["-seed-denylist-entry", builtInBundleID])
        defer { app.terminate() }

        let form = captureForm(in: app)
        let addMenu = app.descendants(matching: .any)["denylist-add-menu"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3), "the Capture form must load")
        XCTAssertFalse(
            app.buttons[denylistRemoveIdentifier(for: builtInBundleID)].firstMatch.exists,
            "a built-in app must not also appear as a removable user entry")

        app.activate()
        try SynthesizedInput.requireForeground(app)
        let builtIns = app.descendants(matching: .any)["denylist-built-in"].firstMatch
        guard builtIns.waitForExistence(timeout: 3), builtIns.revealByScrolling(in: form) else {
            XCTFail("the Built-in exclusions row must be reachable in the Capture form")
            return
        }
        builtIns.click()

        let toggle = app.descendants(matching: .any)[
            denylistToggleIdentifier(for: builtInBundleID)
        ].firstMatch
        guard toggle.waitForExistence(timeout: 3), toggle.revealByScrolling(in: form) else {
            XCTFail("the built-in app's switch must be reachable")
            return
        }
        XCTAssertTrue(isOn(toggle), "adding a built-in app keeps its protection switched on")

        toggle.click()
        XCTAssertTrue(
            waitForSwitch(toggle, on: false, timeout: 3), "the switch turns the protection off")

        let restore = app.buttons["denylist-restore-defaults"].firstMatch
        guard restore.waitForExistence(timeout: 3), restore.revealByScrolling(in: form) else {
            XCTFail("a switched-off built-in must offer Restore default exclusions")
            return
        }
        restore.click()
        XCTAssertTrue(restore.waitForNonexistence(timeout: 3))
        guard toggle.revealByScrolling(in: form) else {
            XCTFail("the built-in app's switch must stay reachable after restoring")
            return
        }
        XCTAssertTrue(
            waitForSwitch(toggle, on: true, timeout: 3),
            "restoring the defaults switches the protection back on")
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

    /// The grouped Capture form, located through the Add app menu it must
    /// contain so no other scroll view in the window can match.
    @MainActor
    private func captureForm(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews.containing(.any, identifier: "denylist-add-menu").firstMatch
    }

    private func denylistRowIdentifier(for bundleID: String) -> String {
        "denylist-row-\(denylistIdentifierSlug(bundleID))"
    }

    private func denylistRemoveIdentifier(for bundleID: String) -> String {
        "denylist-remove-\(denylistIdentifierSlug(bundleID))"
    }

    private func denylistToggleIdentifier(for bundleID: String) -> String {
        "denylist-toggle-\(denylistIdentifierSlug(bundleID))"
    }

    /// A macOS switch reports its state as a number; tolerate a string too.
    @MainActor
    private func isOn(_ element: XCUIElement) -> Bool {
        if let number = element.value as? NSNumber { return number.boolValue }
        return (element.value as? String) == "1"
    }

    @MainActor
    private func waitForSwitch(_ element: XCUIElement, on: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOn(element) == on { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return isOn(element) == on
    }

    private func denylistIdentifierSlug(_ bundleID: String) -> String {
        bundleID.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }
}
