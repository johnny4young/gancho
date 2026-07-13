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

    /// Chooses a palette token through the iPhone UI and reopens the editor to
    /// prove the value survived the durable store write and model refresh.
    @MainActor
    func testBoardAppearancePersistsPaletteSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-sample-boards",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen not exposed to the UI runner in this environment")
        }
        let board = app.buttons["Seed board 1"].firstMatch
        guard board.waitForExistence(timeout: 8), board.isHittable else {
            throw XCTSkip("seeded board chip is not reachable on this runner")
        }

        try openAppearanceEditor(for: board, in: app)
        let blue = app.buttons["board-color-2E70D1"].firstMatch
        guard blue.waitForExistence(timeout: 4), blue.isHittable else {
            throw XCTSkip("board color controls are not reachable on this runner")
        }
        blue.tap()
        XCTAssertEqual(blue.value as? String, "Selected")

        let save = app.buttons["board-appearance-save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()
        XCTAssertFalse(save.waitForExistence(timeout: 5))

        try openAppearanceEditor(for: board, in: app)
        XCTAssertEqual(
            app.buttons["board-color-2E70D1"].firstMatch.value as? String, "Selected",
            "reopening after model refresh must retain the persisted palette token")
    }

    @MainActor
    private func openAppearanceEditor(
        for board: XCUIElement, in app: XCUIApplication
    ) throws {
        board.press(forDuration: 1)
        let customize = app.buttons["Customize board…"].firstMatch
        guard customize.waitForExistence(timeout: 4), customize.isHittable else {
            throw XCTSkip("board appearance context action is not reachable on this runner")
        }
        customize.tap()
        XCTAssertTrue(
            app.buttons["board-color-automatic"].firstMatch.waitForExistence(timeout: 4),
            "the board appearance action must open its editor")
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
