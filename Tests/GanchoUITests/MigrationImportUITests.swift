import Foundation
import XCTest

/// Settings migration smoke over the real app. Synthetic content is gated by
/// the ephemeral-store launch flag, so these flows can never touch a user's
/// history or foreign source files.
final class MigrationImportUITests: XCTestCase {
    @MainActor
    func testOnboardingOffersGuidedMigration() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store",
            "-force-capture-active",
            "-disable-screen-share-auto-pause",
            "-open-welcome-on-launch",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let entry = app.buttons["onboarding-open-migration-importer"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable)
        entry.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["migration-import-sheet"].firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["migration-select-maccy"].firstMatch.exists)
        XCTAssertTrue(app.buttons["migration-select-csv"].firstMatch.exists)
    }

    @MainActor
    func testDryRunPreviewAndCancel() throws {
        let app = try launchImporter(seedArgument: "-seed-migration-preview")
        defer { app.terminate() }

        XCTAssertEqual(value(of: "migration-ready-count", in: app), "3")
        XCTAssertEqual(value(of: "migration-duplicate-count", in: app), "1")
        XCTAssertEqual(value(of: "migration-unsupported-count", in: app), "2")
        XCTAssertEqual(value(of: "migration-protected-count", in: app), "1")

        let attachment = XCTAttachment(screenshot: migrationScreenshot(in: app))
        attachment.name = "macOS guided migration dry-run preview"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["migration-cancel"].firstMatch.click()
        XCTAssertTrue(
            app.buttons["migration-select-maccy"].firstMatch.waitForExistence(timeout: 3),
            "Cancel must discard the in-memory plan and return to source choice")
    }

    @MainActor
    func testApprovedImportShowsFinalSummary() throws {
        let app = try launchImporter(seedArgument: "-seed-migration-preview")
        defer { app.terminate() }

        let confirm = app.buttons["migration-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(
            app.staticTexts["migration-complete-title"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: "migration-imported-count", in: app), "3")
        XCTAssertEqual(value(of: "migration-skipped-count", in: app), "1")
        XCTAssertEqual(value(of: "migration-imported-protected-count", in: app), "1")

        let attachment = XCTAttachment(screenshot: migrationScreenshot(in: app))
        attachment.name = "macOS guided migration completion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCorruptSourceShowsRecoverableError() throws {
        let app = try launchImporter(seedArgument: "-seed-migration-error")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["migration-error"].firstMatch.waitForExistence(timeout: 5))
        let back = app.buttons["migration-back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.click()
        XCTAssertTrue(app.buttons["migration-select-csv"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchImporter(seedArgument: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-open-deep-link-on-launch", "gancho://settings",
            "-force-ephemeral-store",
            "-force-capture-active",
            "-disable-screen-share-auto-pause",
            "-show-migration-importer",
            seedArgument,
            "-AppleLanguages", "(en)"
        ]
        app.launch()

        guard app.windows["Settings"].firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Settings window not exposed to the UI runner")
            app.terminate()
            throw CocoaError(.fileNoSuchFile)
        }
        let sheet = app.descendants(matching: .any)["migration-import-sheet"].firstMatch
        guard sheet.waitForExistence(timeout: 5) else {
            XCTFail("Migration sheet not exposed to the UI runner")
            app.terminate()
            throw CocoaError(.fileNoSuchFile)
        }
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    @MainActor
    private func value(of identifier: String, in app: XCUIApplication) -> String {
        let value = app.staticTexts[identifier].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5), "Missing value: \(identifier)")
        return (value.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? value.label
    }

    @MainActor
    private func migrationScreenshot(in app: XCUIApplication) -> XCUIScreenshot {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        return sheet.screenshot()
    }
}
