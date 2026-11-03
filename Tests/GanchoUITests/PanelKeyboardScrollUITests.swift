import XCTest

/// The sticky section header sits over the list, so a row scrolled to the top
/// edge can end up behind it.
final class PanelKeyboardScrollUITests: XCTestCase {
    private static let rowCount = 16

    @MainActor
    func testMovingUpKeepsTheSelectedRowClearOfTheStickyHeader() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-panel-sections", "-force-free-tier", "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages", "(en)",
            "-suppress-storage-notice-for-ui-test", "-telemetry-consent", "disabled",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-appearance", "light"
        ]
        app.launch()
        defer { app.terminate() }

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(row(0, in: app).waitForExistence(timeout: 10))
        search.click()
        guard SynthesizedInput.waitForKeyboardFocus(search, timeout: 2) else {
            throw XCTSkip("the search field must own keyboard focus to send arrow keys")
        }
        try SynthesizedInput.requireForeground(app)
        // Opening selects the first unpinned row, and ↓ wraps past the last one.
        let last = row(Self.rowCount - 1, in: app)
        for _ in 0..<Self.rowCount where !(last.exists && last.isSelected) {
            app.typeKey(.downArrow, modifierFlags: [])
        }
        XCTAssertTrue(last.isSelected, "the arrows never reached the last row")

        for index in stride(from: Self.rowCount - 2, through: 0, by: -1) {
            try SynthesizedInput.requireForeground(app)
            app.typeKey(.upArrow, modifierFlags: [])
            assertClearOfHeaders(index, in: app)
        }
        try keepRender(of: "history-panel", in: app, named: "Keyboard back at the first row")
    }

    @MainActor
    private func row(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        let label = String(format: "Panel clip %02d", index)
        return app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    @MainActor
    private func assertClearOfHeaders(
        _ index: Int, in app: XCUIApplication, line: UInt = #line
    ) {
        let selected = row(index, in: app)
        XCTAssertTrue(selected.waitForExistence(timeout: 3), "row \(index)", line: line)
        XCTAssertTrue(selected.isSelected, "row \(index)", line: line)
        let headers = app.descendants(matching: .any).matching(identifier: "panel-section-header")
        var covering: CGRect?
        for _ in 0..<10 {
            let frame = selected.frame.insetBy(dx: 0, dy: 1)
            covering = headers.allElementsBoundByIndex.map(\.frame).first { $0.intersects(frame) }
            if covering == nil { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(
            "row \(index) at \(selected.frame) is under the header at \(String(describing: covering))",
            line: line)
    }
}
