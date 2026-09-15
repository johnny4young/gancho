import UIKit
import XCTest

/// iOS UI coverage for the capture→enrich path the GanchoAppCore refactor
/// touched. XCTest lives ONLY in UI-test targets; package unit tests are Swift
/// Testing. These run under `make test-ui-ios` / Xcode and on the weekly hosted
/// UI workflow, outside the pull-request gate. Reaching a screen self-skips
/// where a headless runner doesn't expose it, like `PrivacyCenterUITests`; the
/// presence of an app-owned accessibility identifier is asserted, because a
/// missing one is a product regression, not an environment limitation. The
/// paste handoff runs only on a pasteboard the test can own.
final class CaptureFlowUITests: XCTestCase {
    /// Capture→saved via the deterministic seed path, independent of the system
    /// paste control exercised below: drives the SAME `IOSAppModel.ingest`
    /// capture→enrich path via `-seed-sample-clips` and asserts a seeded clip
    /// lands in the history list.
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
        // insert → search), so a `clip-row` must appear in the list. 15s, not
        // 8: on a cold shared-CI simulator the seed→ingest→refresh chain has
        // been observed to outlast the shorter wait while still succeeding.
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 15),
            "a seeded clip must appear in the history via the capture path")
    }

    /// Chooses a palette token through the iPhone UI and reopens the editor to
    /// prove the value survived the durable store write and model refresh.
    @MainActor
    func testBoardAppearancePersistsPaletteSelection() async throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-sample-boards",
            "-force-free-tier",
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
        let dismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: save)
        dismissal.expectationDescription = "a successful durable update must dismiss the editor"
        await fulfillment(of: [dismissal], timeout: 5)

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
    /// exercises the real handoff: seed the system pasteboard, tap the control
    /// in the bottom bar, and the status row flashes its `save-note` ("Saved")
    /// confirmation via `ingest`.
    ///
    /// The test only ever touches a pasteboard it owns. Simulator mirrors this
    /// pasteboard to the Mac's clipboard when pasteboard sync is on, and
    /// reading content it did not write asks iOS for paste permission (a prompt
    /// once stalled this test for 26 minutes). So occupancy is checked through
    /// metadata alone, the sample is written only onto an empty pasteboard, and
    /// teardown clears it only while the sample is still the latest write.
    @MainActor
    func testPasteControlTapSavesPasteboardContent() throws {
        let pasteboard = UIPasteboard.general
        // Metadata only: none of these reads the content or prompts.
        let occupied =
            pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages
            || pasteboard.hasColors
        var sampleChangeCount: Int?
        if !occupied {
            pasteboard.string = "gancho paste-drive sample"
            sampleChangeCount = pasteboard.changeCount
        }
        defer {
            // A copy made after the sample, on the Mac or in the simulator, is
            // someone else's: leave it.
            if let sampleChangeCount, pasteboard.changeCount == sampleChangeCount {
                pasteboard.items = []
            }
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-force-ephemeral-store", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen not exposed to the UI runner in this environment")
        }
        // The control's identity and label are the app's, whatever the
        // pasteboard holds, so they are asserted before any skip.
        let paste = app.descendants(matching: .any)["paste-control"].firstMatch
        guard paste.waitForExistence(timeout: 5) else {
            XCTFail("paste control not found on the capture screen (see PasteControlView)")
            return
        }
        // SwiftUI writes its accessibility attributes onto the hosted control;
        // the wrapper's own VoiceOver label must survive that bridging.
        XCTAssertEqual(paste.label, "Paste into Gancho")

        guard sampleChangeCount != nil else {
            throw XCTSkip(
                "the simulator pasteboard already holds content this test did not write; "
                    + "the paste handoff runs only on an empty pasteboard so a synced clipboard "
                    + "is never replaced. Run it on a fresh simulator.")
        }
        paste.tap()

        // The handoff runs `IOSAppModel.ingest(providers:)` → the status row
        // flashes the `save-note` ("Saved") chip.
        XCTAssertTrue(
            app.descendants(matching: .any)["save-note"].firstMatch.waitForExistence(timeout: 8),
            "tapping the paste control must save the pasteboard content (Saved note)")
    }

    /// Spanish at the largest accessibility text size once squeezed the sensed
    /// type to nothing and pushed the info button off screen. The status row
    /// must reflow instead: the type keeps a readable width and the button
    /// stays a reachable 44 pt target inside the screen.
    @MainActor
    func testPasteboardStatusRowReflowsAtAccessibilitySizes() throws {
        try assertStatusRowReflows(pinningLongNote: false)
    }

    /// The same at the largest accessibility size with a long real status note
    /// in the chip, the widest thing the row ever shows.
    @MainActor
    func testLongStatusNoteReflowsAtAccessibilitySizes() throws {
        try assertStatusRowReflows(pinningLongNote: true)
    }

    @MainActor
    private func assertStatusRowReflows(pinningLongNote: Bool) throws {
        let app = XCUIApplication()
        // The durable throwaway store keeps the "history isn't being saved"
        // banner away, which at this size would fill the screen on its own.
        app.launchArguments =
            [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-force-free-tier",
                "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ] + (pinningLongNote ? ["-pin-long-save-note"] : [])
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen not exposed to the UI runner in this environment")
        }
        let info = app.buttons["pasteboard-info"].firstMatch
        guard info.waitForExistence(timeout: 5) else {
            XCTFail("the clipboard privacy info button must be on the capture screen")
            return
        }
        let screen = app.frame
        XCTAssertTrue(info.isHittable, "the privacy explanation must stay reachable")
        XCTAssertGreaterThanOrEqual(info.frame.width, 44, "the info target must stay operable")
        XCTAssertGreaterThanOrEqual(info.frame.height, 44, "the info target must stay operable")
        XCTAssertTrue(screen.contains(info.frame), "the info button must stay inside the screen")

        let title = app.staticTexts["pasteboard-status-title"].firstMatch
        XCTAssertTrue(title.exists, "the sensed type must be on the status row")
        XCTAssertGreaterThan(title.frame.width, 44, "the sensed type must keep a readable width")
        XCTAssertTrue(screen.contains(title.frame), "the sensed type must stay inside the screen")

        if pinningLongNote {
            let note = app.descendants(matching: .any)["save-note"].firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 3), "the pinned note must show")
            XCTAssertTrue(screen.contains(note.frame), "a long note must wrap, not run off screen")
        }
    }
}
