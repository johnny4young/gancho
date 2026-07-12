import UIKit
import XCTest

/// iOS UI coverage for the capture→enrich path the GanchoAppCore refactor
/// touched. XCTest lives ONLY in UI-test targets; package unit tests are Swift
/// Testing. These run under `make test-ui` / Xcode and are NOT part of CI, and
/// self-skip — never hard-fail — where an element isn't exposed on a
/// headless/hosted runner, exactly like `PrivacyCenterUITests`.
final class CaptureFlowUITests: XCTestCase {
    /// Capture→saved via the deterministic seed path. The system `UIPasteControl`
    /// is mediated by an OS paste-permission tap that XCUITest can't drive on a
    /// headless runner, and `UIPasteboard` can't be seeded from the UI runner —
    /// so this drives the SAME `IOSAppModel.ingest` capture→enrich path via
    /// `-seed-sample-clips` and asserts a seeded clip lands in the history list.
    @MainActor
    func testSeededCaptureAppearsInHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-force-ephemeral-store", "-seed-sample-clips"
        ]
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen not exposed to the UI runner in this environment")
        }

        // The seeded clips flow through the real capture path (ingest → store
        // insert → search), so a `clip-row` must appear in the list.
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 8),
            "a seeded clip must appear in the history via the capture path")
    }

    /// Drives the `UIPasteControl` tap end to end. The control grants one-shot
    /// pasteboard access on tap with NO permission prompt, so a synthetic tap
    /// exercises the real handoff: seed the system pasteboard, tap, and the
    /// capture card flashes its `save-note` ("Saved") confirmation via `ingest`.
    @MainActor
    func testPasteControlTapSavesPasteboardContent() throws {
        UIPasteboard.general.string = "gancho paste-drive sample"
        let app = XCUIApplication()
        app.launchArguments = ["-skip-welcome-on-launch", "-force-ephemeral-store"]
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen not exposed to the UI runner in this environment")
        }
        let paste = app.descendants(matching: .any)["paste-control"].firstMatch
        guard paste.waitForExistence(timeout: 5) else {
            throw XCTSkip("paste control not exposed to the UI runner")
        }
        paste.tap()

        // The handoff runs `IOSAppModel.ingest(providers:)` → the card flashes the
        // `save-note` ("Saved") label.
        XCTAssertTrue(
            app.descendants(matching: .any)["save-note"].firstMatch.waitForExistence(timeout: 8),
            "tapping the paste control must save the pasteboard content (Saved note)")
    }
}
