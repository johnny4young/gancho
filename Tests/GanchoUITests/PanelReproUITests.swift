import AppKit
import XCTest

/// Reproduction + regression guard for the on-device panel report: after
/// capturing several clips (with a Pinned section above Today), the grouped
/// history list showed multiple rows highlighted at once and several different
/// clips badged with the SAME ⌘N shortcut. Both symptoms mean two rows shared a
/// global list index — the pinned-first + date-bucket index math
/// `PanelSearchModel` owns. XCTest lives ONLY in this UI target; these run under
/// `make test-ui` (a foreground GUI session), are NOT part of CI, and self-skip
/// where elements aren't exposed on a headless runner.
final class PanelReproUITests: XCTestCase {
    @MainActor
    private func selectThreeRows(_ app: XCUIApplication, rows: XCUIElementQuery) throws {
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.downArrow, modifierFlags: [.shift])
        app.typeKey(.downArrow, modifierFlags: [.shift])
        let threeSelected = NSPredicate { _, _ in
            rows.allElementsBoundByIndex.filter(\.isSelected).count == 3
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: threeSelected, object: app)], timeout: 5),
            .completed,
            "Shift-Down must extend the cursor into a three-row contiguous selection")
    }

    @MainActor
    private func verifyBatchBoardAssignment(_ app: XCUIApplication, search: XCUIElement) {
        let addToBoard = app.buttons["selection-add-to-board-button"].firstMatch
        XCTAssertTrue(addToBoard.waitForExistence(timeout: 3))
        addToBoard.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["board-picker"].firstMatch.waitForExistence(
                timeout: 3),
            "the board picker must accept the full selected batch")
        let boardRow = app.descendants(matching: .any)["board-picker-board-row"].firstMatch
        XCTAssertTrue(boardRow.waitForExistence(timeout: 3))
        boardRow.click()
        let allAssigned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"), object: boardRow)
        XCTAssertEqual(
            XCTWaiter.wait(for: [allAssigned], timeout: 5), .completed,
            "one board action must assign every selected clip")
        let boardFilter = app.textFields["board-picker-filter"].firstMatch
        XCTAssertTrue(boardFilter.waitForExistence(timeout: 3))
        boardFilter.click()
        boardFilter.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.exists, "closing the board picker must keep the panel open")
    }

    /// Uses an in-panel probe coordinate so the runner can start a real AppKit
    /// drag without touching an unrelated Finder window. The probe reports the
    /// session pasteboard's independent file-URL item count.
    @MainActor
    func testMultiFileClipDragsEveryFileAndKeepsPanelOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-multi-file-drag",
            "-show-multi-file-drop-target", "-place-panel-for-ui-test",
            "-force-free-tier"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        let target = app.descendants(matching: .any)["multi-file-drop-target"].firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 8), "multi-file row not exposed")
        try XCTSkipUnless(target.waitForExistence(timeout: 3), "drop target not exposed")
        if app.state != .runningForeground {
            app.activate()
            _ = app.wait(for: .runningForeground, timeout: 2)
        }
        try SynthesizedInput.requireForeground(app)

        let prepared = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "Multi-file drag probe, prepared 2, pasteboard 0"),
            object: target)
        XCTAssertEqual(
            XCTWaiter.wait(for: [prepared], timeout: 5), .completed,
            "the path-only preflight must expose both URLs before dragging")
        let source = row.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        let destination = target.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // A short press or instantaneous release can be interpreted as a click
        // when the full macOS UI suite leaves the automation server under
        // load. Move slowly and dwell over the destination so AppKit observes
        // at least one destination update before the synthesized mouse-up.
        source.press(
            forDuration: 0.5, thenDragTo: destination,
            withVelocity: .slow, thenHoldForDuration: 0.5)

        let populated = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "Multi-file drag probe, prepared 2, pasteboard 2"),
            object: target)
        XCTAssertEqual(
            XCTWaiter.wait(for: [populated], timeout: 8), .completed,
            "one drag must publish both file URLs as separate pasteboard items")
        XCTAssertTrue(search.exists, "the panel must remain open after the drop")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "panel-multi-file-drag-pasteboard"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The AppKit drag responder must not capture macOS's Control-click
    /// context-menu gesture once multi-file preflight activates it.
    @MainActor
    func testMultiFileRowControlClickOpensContextMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-multi-file-drag",
            "-show-multi-file-drop-target", "-place-panel-for-ui-test",
            "-force-free-tier"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        let target = app.descendants(matching: .any)["multi-file-drop-target"].firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 8), "multi-file row not exposed")
        try XCTSkipUnless(target.waitForExistence(timeout: 3), "drop target not exposed")
        let prepared = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "Multi-file drag probe, prepared 2, pasteboard 0"),
            object: target)
        XCTAssertEqual(
            XCTWaiter.wait(for: [prepared], timeout: 5), .completed,
            "the AppKit row bridge must be active before the gesture is tested")

        try SynthesizedInput.controlClick(row, in: app)

        let delete = app.menuItems["Delete"].firstMatch
        XCTAssertTrue(
            delete.waitForExistence(timeout: 3),
            "Control-click must reach the row context menu instead of the drag bridge")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "panel-multi-file-control-click-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Seeds a throwaway durable store with three PINNED clips plus four
    /// same-day clips (`-seed-panel-repro`), opens the panel, and asserts the two
    /// invariants the report violated.
    @MainActor
    func testGroupedPanelKeepsOneSelectionAndDistinctShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "the seeded panel must open on launch")

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        try XCTSkipUnless(
            rows.firstMatch.waitForExistence(timeout: 8),
            "seeded clip rows not exposed to the UI runner in this environment")
        // The seed captures four same-day clips one at a time AFTER the panel
        // opens (~0.9s + 4×0.2s), each a live refresh; wait for them to land so
        // the assertions see the full pinned-3 + today-4 list.
        let settle = Date().addingTimeInterval(3)
        while rows.count < 7 && Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let all = rows.allElementsBoundByIndex
        try XCTSkipUnless(all.count >= 4, "not enough seeded rows exposed (\(all.count))")

        // Invariant 1 — exactly ONE row is selected. The report showed several
        // rows highlighted together (`selectedIndex` matched more than one row).
        let selectedCount = all.filter { $0.isSelected }.count
        XCTAssertEqual(
            selectedCount, 1,
            "exactly one clip row must be selected; \(selectedCount) were highlighted")

        // Invariant 2 — the ⌘N quick-paste shortcuts are DISTINCT. The report
        // showed different clips all badged ⌘4 (a repeated global index). The
        // badge is exposed as each row's accessibility value ("⌘4").
        let shortcuts = all.compactMap { $0.value as? String }.filter { $0.hasPrefix("⌘") }
        XCTAssertGreaterThanOrEqual(
            shortcuts.count, 3, "the first rows must carry ⌘N badges; got \(shortcuts)")
        XCTAssertEqual(
            shortcuts.count, Set(shortcuts).count,
            "each visible row must carry a distinct ⌘N shortcut; got \(shortcuts)")
    }

    @MainActor
    func testKeyboardSelectionLoadsOnlyTheSelectedPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier",
            "-start-capture-paused"
        ]
        app.launch()
        defer { app.terminate() }

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        try XCTSkipUnless(
            rows.firstMatch.waitForExistence(timeout: 8),
            "seeded clip rows not exposed to the UI runner in this environment")

        let preview = app.descendants(matching: .any)["preview-content"].firstMatch
        try XCTSkipUnless(
            preview.waitForExistence(timeout: 5),
            "selected preview is not exposed to the UI runner in this environment")
        let firstValue = preview.value as? String

        // Arrow keys are app-level (global) events; only send them once the
        // panel is verifiably frontmost so navigation lands on Gancho.
        try SynthesizedInput.requireForeground(app)
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", firstValue ?? ""),
            object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let selected = rows.allElementsBoundByIndex.first(where: \.isSelected)
        let selectedDescription = selected?.label ?? ""
        let loadedValue = preview.value as? String ?? ""
        XCTAssertTrue(
            selectedDescription.contains(loadedValue),
            "the visible preview must belong to the newly selected row")
    }

    @MainActor
    func testShiftArrowExtendsAContiguousSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier",
            "-start-capture-paused"
        ]
        app.launch()
        defer { app.terminate() }

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        try XCTSkipUnless(
            rows.firstMatch.waitForExistence(timeout: 8),
            "seeded clip rows not exposed to the UI runner in this environment")
        let settle = Date().addingTimeInterval(3)
        while rows.count < 4 && Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try XCTSkipUnless(rows.count >= 4, "not enough seeded rows exposed (\(rows.count))")

        try selectThreeRows(app, rows: rows)

        let contextBar = app.descendants(matching: .any)["selection-context-bar"].firstMatch
        XCTAssertTrue(contextBar.waitForExistence(timeout: 3))
        XCTAssertEqual(contextBar.label, "3 clips")

        let addToStack = app.buttons["selection-add-to-stack-button"].firstMatch
        XCTAssertTrue(addToStack.waitForExistence(timeout: 3))
        addToStack.click()
        let stack = app.buttons["paste-stack-strip"].firstMatch
        XCTAssertTrue(stack.waitForExistence(timeout: 3))
        XCTAssertTrue(
            stack.label.contains("3"),
            "batch enqueue must add all three selected clips in one action")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "panel-batch-context-actions"
        attachment.lifetime = .keepAlways
        add(attachment)

        let beforeDelete = rows.count
        let delete = app.buttons["selection-delete-button"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.click()

        let undo = app.buttons["toast-undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        let hidden = NSPredicate { _, _ in rows.count <= beforeDelete - 3 }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: hidden, object: app)], timeout: 3),
            .completed,
            "batch delete must hide every selected row together")

        undo.click()
        let restored = NSPredicate { _, _ in rows.count >= beforeDelete }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: restored, object: app)], timeout: 5),
            .completed,
            "one Undo action must restore the entire deleted selection")

        // Undo refreshes the list and intentionally restores single-selection.
        // Select a batch again to exercise board assignment independently.
        try selectThreeRows(app, rows: rows)
        verifyBatchBoardAssignment(app, search: search)
    }
}
