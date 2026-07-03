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
    func testSeededCaptureAppearsInHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-force-ephemeral-store", "-seed-sample-clips"]
        app.launch()

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            print("skip: capture screen not exposed to the UI runner in this environment")
            return
        }

        // The seeded clips flow through the real capture path (ingest → store
        // insert → search), so a `clip-row` must appear in the list.
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 8),
            "a seeded clip must appear in the history via the capture path")
    }

    /// The capture/save control itself is present on the capture screen. Driving
    /// its OS-mediated tap and asserting the "Saved" confirmation needs a real
    /// simulator/device run, so that is left as a local TODO.
    @MainActor
    func testPasteControlIsPresent() {
        let app = XCUIApplication()
        app.launchArguments = ["-force-ephemeral-store"]
        app.launch()

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            print("skip: capture screen not exposed to the UI runner in this environment")
            return
        }

        let paste = app.descendants(matching: .any)["paste-control"].firstMatch
        XCTAssertTrue(
            paste.waitForExistence(timeout: 5),
            "the capture screen must expose the paste/save control")

        // TODO(local): drive the UIPasteControl tap and assert the existing
        // `save-note` ("Saved") confirmation. The system paste-permission tap
        // isn't scriptable on a headless runner, so this needs a real
        // simulator/device pass in Xcode.
    }
}
