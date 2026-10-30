import Foundation
import GanchoKit
import Testing

@testable import ClipboardCore

@Suite("Share sheet — choices and the board snapshot")
struct ShareChoicesTests {
    let key = Data(repeating: 0xC3, count: 32)

    @Test("Choices ride the sealed deposit to the drain")
    func choicesRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-choices-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = SharedInbox(directory: dir, key: key)
        let choices = SharedInbox.ShareChoices(
            title: "Example Domain", boardIDs: [UUID()], newBoardName: "Brand", isPinned: true)
        try inbox.deposit(
            SharedInbox.PreparedCapture(
                capture: PasteboardCapture(text: "https://example.com"), kind: .url,
                choices: choices))
        let read = try inbox.readPending()
        #expect(read.deliveries.map(\.prepared.choices) == [choices])
    }

    @Test("A capture written before the sheet existed decodes with no choices")
    func legacyDecodes() throws {
        let legacy = try JSONEncoder().encode(
            LegacyPrepared(capture: PasteboardCapture(text: "old"), kind: .text))
        let decoded = try JSONDecoder().decode(SharedInbox.PreparedCapture.self, from: legacy)
        #expect(decoded.choices == nil)
        #expect(decoded.capture.textRepresentation == "old")
    }

    @Test("The board snapshot round-trips sealed, and reads as none without its key")
    func boardSnapshot() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("boards-\(UUID().uuidString).sealed")
        defer { try? FileManager.default.removeItem(at: file) }
        let boards = [Pinboard(name: "Favorites", isSystem: true), Pinboard(name: "Brand Work")]
        try SharedBoardSnapshot(file: file, key: key).write(boards)
        #expect(SharedBoardSnapshot(file: file, key: key).read() == boards)
        let bytes = try Data(contentsOf: file)
        #expect(!bytes.contains(Data("Brand Work".utf8)), "board names stay sealed")
        let otherKey = Data(repeating: 0x11, count: 32)
        #expect(SharedBoardSnapshot(file: file, key: otherKey).read().isEmpty)
    }

    @Test("The share sheet shows by default; the switch makes it save at once")
    func instantSaveDefaultsOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "share-pref-\(UUID().uuidString)"))
        #expect(!ShareSheetPreference.savesInstantly(in: defaults))
        ShareSheetPreference.setSavesInstantly(true, in: defaults)
        #expect(ShareSheetPreference.savesInstantly(in: defaults))
    }

    private struct LegacyPrepared: Encodable {
        var capture: PasteboardCapture
        var kind: ClipContentKind?
    }
}

@Suite("Share sheet — the suggested title")
struct ShareTitleSuggestionTests {
    @Test("The sharing app's page title is offered")
    func pageTitle() {
        #expect(
            ShareTitleSuggestion.title(
                attributedTitle: nil, contentText: "Example Domain",
                sharedTexts: ["https://example.com/"]) == "Example Domain")
    }

    @Test("Text that is the shared content, a URL or several lines is never a title")
    func neverTheContent() {
        let token = "opaque-shared-text-0000"
        #expect(
            ShareTitleSuggestion.title(
                attributedTitle: nil, contentText: token, sharedTexts: [token]) == nil)
        #expect(
            ShareTitleSuggestion.title(
                attributedTitle: nil, contentText: "token opaque-shared-text",
                sharedTexts: ["opaque-shared-text"]) == nil)
        #expect(
            ShareTitleSuggestion.title(
                attributedTitle: "https://example.com", contentText: nil, sharedTexts: []) == nil)
        #expect(
            ShareTitleSuggestion.title(
                attributedTitle: "one\ntwo", contentText: nil, sharedTexts: []) == nil)
    }
}
