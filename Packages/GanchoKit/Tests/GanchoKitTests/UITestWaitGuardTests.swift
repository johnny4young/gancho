import Foundation
import Testing

@Suite("UI tests check an element before polling for it")
struct UITestWaitGuardTests {
    /// XCTest's own waits first look after a second, even for an element already on screen.
    @Test func waitsGoThroughTheCheckFirstHelpers() throws {
        let tests = LocalizationTests.repoRoot.appendingPathComponent("Tests")
        var offenders: [String] = []
        for target in ["GanchoUITests", "GanchoiOSUITests"] {
            offenders += try DesignTokenGuardTests.matches(
                of: #"\.waitFor(Existence|NonExistence)\("#,
                in: tests.appendingPathComponent(target))
        }
        #expect(
            offenders.isEmpty,
            "use appears(within:) or waitForNonexistence(timeout:): \(offenders)")
    }
}
