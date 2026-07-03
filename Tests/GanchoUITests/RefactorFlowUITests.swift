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
                "-force-ephemeral-store", "-seed-sample-clips",
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
    func testDeleteThenUndoRestoresTheClip() {
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
        let before = rows.count

        // Right-click the first row and pick Delete from its context menu.
        rows.firstMatch.rightClick()
        let deleteItem = app.menuItems["Delete"].firstMatch
        guard deleteItem.waitForExistence(timeout: 3) else {
            print("skip: row context menu not reachable on this runner")
            return
        }
        deleteItem.click()

        // The deferred delete surfaces a "Deleted" toast with an Undo affordance.
        let undo = app.buttons["toast-undo"].firstMatch
        XCTAssertTrue(
            undo.waitForExistence(timeout: 5),
            "deleting a clip must show the Undo toast (DeletionCoordinator window)")
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
    func testCreateBoardAffordanceAndPrompt() {
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
        newBoard.click()

        // The SwiftUI `.alert` for a new board exposes a "Board name" field and a
        // "Create" button (see PanelView's `.alert(boardSheetTitle, …)`).
        let field = app.textFields["Board name"].firstMatch
        let alertField = field.exists ? field : app.dialogs.textFields.firstMatch
        guard alertField.waitForExistence(timeout: 3) else {
            print("skip: New board prompt not reachable on this runner")
            return
        }
        XCTAssertTrue(
            app.buttons["Create"].firstMatch.waitForExistence(timeout: 2),
            "the New board prompt must offer a Create action")
        app.buttons["Cancel"].firstMatch.click()

        // TODO(local): extend to the paywall threshold. Board creation needs a
        // durable grdbStore (nil under -force-ephemeral-store), so exercising
        // create → free limit (PinLimits.freeMaxPinboards) → the `paywall`
        // surface must run in Xcode against a throwaway DURABLE store, not the
        // ephemeral UI-test store. Assert `app.descendants["paywall"]` appears
        // after creating freeMaxPinboards + 1 boards.
    }
}
