import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Board drop — what a clip dropped on a board does")
struct BoardDropTests {
    private let clip = ClipItem(kind: .text, preview: "hello", contentHash: "h")

    @Test("A visible clip not yet on the board is added; one already there is not")
    func addOrAlreadyMember() {
        #expect(BoardDrop.decide(item: clip, isMember: false, isPendingDeletion: false) == .add)
        #expect(
            BoardDrop.decide(item: clip, isMember: true, isPendingDeletion: false)
                == .alreadyMember)
    }

    @Test("A missing, deleting, expired or protected clip is ignored")
    func ignored() {
        #expect(BoardDrop.decide(item: nil, isMember: false, isPendingDeletion: false) == .ignore)
        #expect(BoardDrop.decide(item: clip, isMember: false, isPendingDeletion: true) == .ignore)
        var expired = clip
        expired.expiresAt = Date(timeIntervalSince1970: 10)
        #expect(
            BoardDrop.decide(
                item: expired, isMember: false, isPendingDeletion: false,
                now: Date(timeIntervalSince1970: 20)) == .ignore)
        var secret = clip
        secret.isSensitive = true
        #expect(
            BoardDrop.decide(item: secret, isMember: false, isPendingDeletion: false) == .ignore)
    }

    @Test("The drag carries the id only, and nothing else parses as one")
    func payloadRoundTrip() {
        let id = UUID()
        #expect(BoardDrop.clipID(from: BoardDrop.payload(for: id)) == id)
        #expect(BoardDrop.clipID(from: Data("not an id".utf8)) == nil)
        #expect(BoardDrop.payload(for: id).count == id.uuidString.utf8.count)
    }
}
