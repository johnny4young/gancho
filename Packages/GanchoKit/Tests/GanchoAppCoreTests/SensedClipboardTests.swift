import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Sensed clipboard — the card's kind from detect hints, and the Open window")
struct SensedClipboardTests {
    @Test("Hints map to one kind, in the order the card names them")
    func mapping() {
        func sensed(
            _ content: Bool, url: Bool = false, search: Bool = false, number: Bool = false
        )
            -> SensedClipboard
        {
            SensedClipboard(
                hasContent: content, probableWebURL: url, probableWebSearch: search, number: number)
        }
        #expect(sensed(false, url: true) == .empty, "no content wins over a stale hint")
        #expect(sensed(true, url: true, search: true, number: true) == .link)
        #expect(sensed(true, search: true, number: true) == .searchText)
        #expect(sensed(true, number: true) == .number)
        #expect(sensed(true) == .other)
        #expect(SensedClipboard.link.tintKind == .url)
        #expect(SensedClipboard.number.tintKind == .text)
    }

    @Test("Open is offered inside the window and only for the same copy")
    func openWindow() {
        let savedAt = Date(timeIntervalSince1970: 1_000)
        let save = RecentPasteSave(clipID: UUID(), changeCount: 7, savedAt: savedAt)
        let window = RecentPasteSave.openWindow
        #expect(save.offersOpen(now: savedAt, currentChangeCount: 7))
        #expect(
            save.offersOpen(now: savedAt.addingTimeInterval(window - 0.1), currentChangeCount: 7))
        #expect(!save.offersOpen(now: savedAt.addingTimeInterval(window), currentChangeCount: 7))
        #expect(!save.offersOpen(now: savedAt, currentChangeCount: 8), "a new copy replaced it")
        #expect(!save.offersOpen(now: savedAt.addingTimeInterval(-1), currentChangeCount: 7))
    }
}
