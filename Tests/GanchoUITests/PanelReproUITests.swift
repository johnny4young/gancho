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
    /// Seeds a throwaway durable store with three PINNED clips plus four
    /// same-day clips (`-seed-panel-repro`), opens the panel, and asserts the two
    /// invariants the report violated.
    @MainActor
    func testGroupedPanelKeepsOneSelectionAndDistinctShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier",
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
}
