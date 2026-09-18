import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Saved-filter scope reload on local history changes")
struct LibraryScopeReloadTests {
    private let fixed = Date(timeIntervalSinceReferenceDate: 1_000)

    private func clip(_ n: Int, pinned: Bool = false, uses: Int = 0) -> ClipItem {
        ClipItem(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
            createdAt: fixed, updatedAt: fixed, preview: "row \(n)", isPinned: pinned, uses: uses)
    }

    @Test("A captured or deleted clip reruns the selected saved filter")
    func addedAndRemoved() {
        let before = [clip(1), clip(2)]
        #expect(
            LibraryScopeReload.isNeeded(
                savedFilterSelected: true, previous: before, current: [clip(3)] + before))
        #expect(
            LibraryScopeReload.isNeeded(
                savedFilterSelected: true, previous: before, current: [clip(1)]))
    }

    @Test("An edit or a pin flip on a shown clip reruns it too")
    func editedAndPinned() {
        let before = [clip(1)]
        var edited = clip(1)
        edited.updatedAt = fixed.addingTimeInterval(60)
        #expect(
            LibraryScopeReload.isNeeded(
                savedFilterSelected: true, previous: before, current: [edited]))
        #expect(
            LibraryScopeReload.isNeeded(
                savedFilterSelected: true, previous: before, current: [clip(1, pinned: true)]))
    }

    @Test("Use counters alone, or a reorder, never rerun a ranked result set")
    func usageOnly() {
        #expect(
            !LibraryScopeReload.isNeeded(
                savedFilterSelected: true, previous: [clip(1), clip(2)],
                current: [clip(2, uses: 5), clip(1)]))
    }

    @Test("Paged scopes are left to their own next page")
    func otherScopes() {
        #expect(
            !LibraryScopeReload.isNeeded(
                savedFilterSelected: false, previous: [clip(1)], current: [clip(1), clip(2)]))
    }
}
