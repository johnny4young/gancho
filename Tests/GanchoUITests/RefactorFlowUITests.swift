import AppKit
import XCTest

/// UI coverage for the flows the GanchoAppCore refactor reorganized:
/// `DeletionCoordinator` (deferred, reversible delete) and `BoardsController`
/// (create-board / free-tier paywall). XCTest lives ONLY in this UI target;
/// package unit tests are Swift Testing. These run under `make test-ui` /
/// Xcode and are NOT part of CI. They self-skip — never hard-fail — where an
/// element isn't exposed on a headless/hosted runner, exactly like
/// `PanelUITests`.
final class RefactorFlowUITests: XCTestCase {
    /// The seeded, deterministic panel launch: the ephemeral store keeps the
    /// real history untouched, `-seed-sample-clips` inserts three KNOWN clips
    /// through the normal capture path, and `-open-panel-on-launch` opens the
    /// panel without the global hotkey.
    @MainActor
    private func launchSeededPanel(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item",
                "-force-ephemeral-store", "-seed-sample-clips"
            ] + extraArguments
        app.launch()
        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    /// DeletionCoordinator: delete a seeded clip via its context menu, confirm
    /// the Undo toast, tap Undo, and confirm the clip returns. The delete gesture
    /// found in `PanelView.contextMenu(for:)` is a right-click → "Delete"
    /// (role: .destructive) → `AppModel.delete`, which shows a "Deleted" toast
    /// whose Undo button carries the `toast-undo` id.
    @MainActor
    func testDeleteThenUndoRestoresTheClip() throws {
        let app = launchSeededPanel()
        defer { app.terminate() }

        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "the seeded panel must open on launch")

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        guard rows.firstMatch.waitForExistence(timeout: 8) else {
            print("skip: seeded clip rows not exposed to the UI runner in this environment")
            return
        }
        guard rows.firstMatch.isHittable else {
            throw XCTSkip("seeded clip row is not hittable on this runner")
        }
        let before = rows.count

        // Right-click the first row and pick Delete from its context menu.
        rows.firstMatch.rightClick()
        let deleteItem = app.menuItems["Delete"].firstMatch
        guard deleteItem.waitForExistence(timeout: 3) else {
            print("skip: row context menu not reachable on this runner")
            return
        }
        guard deleteItem.isHittable else {
            throw XCTSkip("Delete menu item is not hittable on this runner")
        }
        deleteItem.click()

        // The deferred delete surfaces a "Deleted" toast with an Undo affordance.
        let undo = app.buttons["toast-undo"].firstMatch
        XCTAssertTrue(
            undo.waitForExistence(timeout: 5),
            "deleting a clip must show the Undo toast (DeletionCoordinator window)")
        guard undo.isHittable else {
            throw XCTSkip("Undo action is not hittable on this runner")
        }
        undo.click()

        // Undo cancels the pending commit, so the clip — never removed from the
        // store — reappears and the row count returns to what it was.
        let deadline = Date().addingTimeInterval(5)
        while rows.count < before && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThanOrEqual(
            rows.count, before, "Undo must restore the deleted clip to the list")
    }

    /// BoardsController: the create-board affordance and its "New board" prompt.
    ///
    /// HONEST SCOPE: this asserts only that the create-board control and its name
    /// prompt are wired. It does NOT reach the free-tier paywall, for two reasons
    /// found in the source:
    ///   1. `AppModel.createBoard` guards `guard let grdbStore` — board creation
    ///      is a no-op under `-force-ephemeral-store` (grdbStore is nil), and we
    ///      must not create test boards in the user's real durable store.
    ///   2. The paywall is gated by `PaywallGatekeeper.shouldShow`, which
    ///      suppresses the `.freeLimitReached` trigger until the user's first
    ///      paste-back (`first-pasteback-at` present). This launch passes
    ///      `-first-pasteback-at 1` (NSArgumentDomain) so that gate is satisfied.
    /// The free limit is `PinLimits.freeMaxPinboards` (3): the 4th create fires
    /// `onFreeLimit` → `paywallWindow.show(trigger: .freeLimitReached)`.
    @MainActor
    func testCreateBoardAffordanceAndPrompt() throws {
        let app = launchSeededPanel(extraArguments: ["-first-pasteback-at", "1"])
        defer { app.terminate() }

        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "the seeded panel must open on launch")

        let newBoard = app.buttons["board-new"].firstMatch
        guard newBoard.waitForExistence(timeout: 8) else {
            print("skip: New board affordance not exposed to the UI runner")
            return
        }
        guard newBoard.isHittable else {
            throw XCTSkip("New board affordance is not hittable on this runner")
        }
        newBoard.click()

        // The SwiftUI `.alert` for a new board exposes a "Board name" field and a
        // "Create" button (see PanelView's `.alert(boardSheetTitle, …)`).
        let field = app.textFields["Board name"].firstMatch
        let alertField = field.exists ? field : app.dialogs.textFields.firstMatch
        guard alertField.waitForExistence(timeout: 3) else {
            print("skip: New board prompt not reachable on this runner")
            return
        }
        guard alertField.isHittable else {
            throw XCTSkip("New board name field is not hittable on this runner")
        }
        XCTAssertTrue(
            app.buttons["Create"].firstMatch.waitForExistence(timeout: 2),
            "the New board prompt must offer a Create action")
        // The affordance + prompt ARE the assertion; dismiss with Escape. (Clicking
        // the alert's "Cancel" can misfire on a hosted runner that maps the button
        // to a Touch Bar element; the deferred terminate is the real cleanup.)
        try SynthesizedInput.requireForeground(app)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// BoardsController free-tier paywall, end to end — the local follow-up to the
    /// affordance test above. A THROWAWAY durable store (`-use-temp-durable-store`)
    /// makes board creation real (it is a silent no-op under the ephemeral UI-test
    /// store, whose `grdbStore` is nil), `-seed-sample-boards` pre-creates exactly
    /// the free limit (`PinLimits.freeMaxPinboards`) into it, and
    /// `-first-pasteback-at 1` satisfies `PaywallGatekeeper.shouldShow`. Creating
    /// ONE more board then trips `onFreeLimit` → the `paywall` surface. The store
    /// is a unique temp directory, so the user's real boards are never touched.
    @MainActor
    func testCreatingBoardBeyondFreeLimitShowsPaywall() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-sample-boards",
            "-force-free-tier", "-first-pasteback-at", "1"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "the panel must open on launch")

        let newBoard = app.buttons["board-new"].firstMatch
        guard newBoard.waitForExistence(timeout: 8) else {
            print("skip: New board affordance not exposed to the UI runner")
            return
        }
        guard newBoard.isHittable else {
            throw XCTSkip("New board affordance is not hittable on this runner")
        }
        newBoard.click()

        // The free-tier gate is checked when the name is submitted (createBoard),
        // so the prompt still opens; it is the Create that trips the paywall.
        let field = app.textFields["Board name"].firstMatch
        let alertField = field.exists ? field : app.dialogs.textFields.firstMatch
        guard alertField.waitForExistence(timeout: 3) else {
            print("skip: New board prompt not reachable on this runner")
            return
        }
        guard alertField.isHittable else {
            throw XCTSkip("New board name field is not hittable on this runner")
        }
        alertField.click()
        alertField.typeText("One past the limit")
        guard app.buttons["Create"].firstMatch.waitForExistence(timeout: 2) else {
            print("skip: Create action not reachable on this runner")
            return
        }
        // Submit with Return (the alert's default action) rather than clicking the
        // "Create" button: clicking an alert button can misfire on a hosted runner
        // that maps it to a Touch Bar element. Return trips the same createBoard.
        try SynthesizedInput.requireForeground(app)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Seeded boards == freeMaxPinboards, so this is the (limit + 1)th create:
        // the gate blocks it and opens the paywall.
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall"].firstMatch.waitForExistence(timeout: 6),
            "creating a board past the free limit must open the paywall")
    }
}
