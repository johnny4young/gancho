import XCTest

/// The reveal helper's scroll steps: short enough that no row can sit between
/// two of them, and long enough to cross the whole form either way.
final class RevealDeltasTests: XCTestCase {
    func testStepsStayWithinHalfTheVisibleHeight() {
        for height in [150, 399, 400, 900] as [CGFloat] {
            let deltas = XCUIElement.revealDeltas(visibleHeight: height)
            let longest = deltas.map(abs).max() ?? 0
            // Half the height, but never under 100 pt nor over 400 pt.
            XCTAssertLessThanOrEqual(longest, max(100, height / 2), "height \(height)")
            XCTAssertLessThanOrEqual(longest, 400, "height \(height)")
        }
    }

    func testStepsCoverTheSameDistanceAtEveryHeight() {
        for height in [0, 150, 399, 400, 900] as [CGFloat] {
            let deltas = XCUIElement.revealDeltas(visibleHeight: height)
            let outward = deltas.prefix { $0 < 0 }.reduce(0, +)
            XCTAssertLessThanOrEqual(outward, -1200, "height \(height)")
            XCTAssertGreaterThanOrEqual(deltas.reduce(0, +), 1200, "past the origin at \(height)")
        }
    }
}
