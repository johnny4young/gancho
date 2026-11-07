import XCTest

extension XCUIElement {
    /// `waitForExistence` first looks after a second even when the element is
    /// already there; one check up front skips that second.
    @MainActor
    func appears(within timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    @MainActor
    func waitForNonexistence(timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }

    @MainActor
    func waitForHittable(timeout: TimeInterval) -> Bool {
        if exists && isHittable { return true }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
