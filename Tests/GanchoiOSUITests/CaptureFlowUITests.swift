import UIKit
import XCTest

/// iOS UI coverage for the capture→enrich path the GanchoAppCore refactor
/// touched. XCTest lives ONLY in UI-test targets; package unit tests are Swift
/// Testing. These run under `make test-ui-ios` / Xcode and on the weekly hosted
/// UI workflow, outside the pull-request gate. Reaching a screen self-skips
/// where a headless runner doesn't expose it, like `PrivacyCenterUITests`; the
/// presence of an app-owned accessibility identifier is asserted, because a
/// missing one is a product regression, not an environment limitation. The
/// paste handoff runs only on a pasteboard the test can own. Every `-seed-*`,
/// `-pin-*` and `-ui-test-*` launch argument these tests pass is a DEBUG-only
/// hook (the GanchoiOS scheme tests the Debug configuration); a Release build
/// ignores them.
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
    func testBoardAppearancePersistsPaletteSelection() throws {
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
        XCTAssertTrue(waitForSelected(blue), "tapping a swatch must select it")

        let save = app.buttons["board-appearance-save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()
        // Use XCTest's element wait so disappearance is checked against fresh
        // accessibility snapshots, not an async generic predicate scheduler.
        XCTAssertTrue(
            save.waitForNonExistence(timeout: 5),
            "a successful durable update must dismiss the editor")

        try openAppearanceEditor(for: board, in: app)
        let persisted = app.buttons["board-color-2E70D1"].firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 4))
        XCTAssertTrue(
            waitForSelected(persisted),
            "reopening after model refresh must retain the persisted palette token")
    }

    /// Predicate expectations sample about once a second, so the timeout
    /// must span several samples.
    @MainActor
    private func waitForSelected(_ element: XCUIElement) -> Bool {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"), object: element)
        return XCTWaiter.wait(for: [selected], timeout: 4) == .completed
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
    /// in the bottom bar, and `ingest` shows the `save-note` ("Saved")
    /// confirmation, saves the text as a history row, and dismisses the note.
    ///
    /// The test only ever touches a pasteboard it owns. Simulator mirrors this
    /// pasteboard to the Mac's clipboard when pasteboard sync is on, and
    /// reading content it did not write asks iOS for paste permission (a prompt
    /// once stalled this test for 26 minutes). So occupancy is checked through
    /// metadata alone, the sample is written only onto an empty pasteboard, and
    /// teardown clears it only while the sample is still the latest write.
    ///
    /// The note normally lives two seconds. On the hosted runner the paste
    /// landed (the history row and the durable "Saved" chip were in the
    /// failure hierarchy) but the note had come and gone between two
    /// accessibility snapshots, which can be seconds apart there. The app is
    /// therefore launched with a longer note lifetime, the test proves the
    /// note is the tap's own (none is on screen before it), asserts the
    /// durable outcome (the pasted text as a history row), and then asserts
    /// the dismissal, so the product's own timer stays covered.
    @MainActor
    func testPasteControlTapSavesPasteboardContent() throws {
        let sample = "gancho paste-drive sample"
        let noteLifetime = 15
        let pasteboard = UIPasteboard.general
        // Metadata only: none of these reads the content or prompts.
        let occupied =
            pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages
            || pasteboard.hasColors
        var sampleChangeCount: Int?
        if !occupied {
            pasteboard.string = sample
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
            "-skip-welcome-on-launch", "-force-ephemeral-store", "-AppleLanguages", "(en)",
            "-ui-test-save-note-lifetime", "\(noteLifetime)"
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
        // Causation: the note asserted below must be THIS tap's. A leftover
        // shared-inbox item ingested at activation would already show one.
        let note = app.descendants(matching: .any)["save-note"].firstMatch
        XCTAssertFalse(note.exists, "no status note may be on screen before the tap")
        paste.tap()

        // The handoff runs `IOSAppModel.ingest(providers:)`: the status row
        // shows the `save-note` ("Saved") chip, a success-kind note, and the
        // pasted text lands in history as a row. The waits are bounded
        // generously: the hosted runner is slow, and existence polling samples
        // about once per second — which is also why the note lifetime above
        // is far longer than the two seconds a user sees.
        XCTAssertTrue(note.waitForExistence(timeout: 15), "the Saved note must show")
        XCTAssertTrue(note.label.contains("Saved"), "the note was \(note.label)")
        XCTAssertEqual(note.value as? String, "Done", "a saved note must expose its success kind")
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", sample)
        ).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "tapping the paste control must save the pasteboard content as a history row")
        // The product's own dismissal, at the lifetime the launch asked for.
        XCTAssertTrue(
            note.waitForNonExistence(timeout: Double(noteLifetime) + 15),
            "the note must dismiss after its lifetime")
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
            // The pinned load failure must not read as a success: its kind is
            // the chip's accessibility value ("Error" in Spanish too).
            XCTAssertEqual(
                note.value as? String, "Error", "a failure note must expose its kind")
        }
    }
}
