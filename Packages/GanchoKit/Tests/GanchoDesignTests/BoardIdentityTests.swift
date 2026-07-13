import Foundation
import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("Board identity")
struct BoardIdentityTests {
    @Test("The persisted color palette is closed, unique, and canonical")
    func colorPaletteIsClosed() {
        let tokens = BoardIdentityColor.allCases.map(\.rawValue)

        #expect(tokens.count == 6)
        #expect(Set(tokens).count == tokens.count)
        #expect(
            tokens.allSatisfy {
                $0.range(of: #"^#[0-9A-F]{6}$"#, options: .regularExpression) != nil
            })
        #expect(BoardIdentityColor.canonicalToken("#2e70d1") == "#2E70D1")
        #expect(BoardIdentityColor.canonicalToken("#FFFFFF") == nil)
        #expect(BoardIdentityColor.canonicalToken(nil) == nil)
    }

    @Test("Every picker token has presentation metadata")
    func presentationMetadataIsComplete() throws {
        let colorOptions = BoardIdentityColor.allCases
        let emojiOptions = BoardIdentityEmoji.allCases

        #expect(colorOptions.map(\.id) == colorOptions.map(\.rawValue))
        #expect(emojiOptions.map(\.id) == emojiOptions.map(\.rawValue))
        #expect(colorOptions.map { String(describing: $0.color) }.allSatisfy { !$0.isEmpty })
        #expect(colorOptions.map { String(describing: $0.name) }.allSatisfy { !$0.isEmpty })
        #expect(emojiOptions.map { String(describing: $0.name) }.allSatisfy { !$0.isEmpty })

        let userID = try #require(UUID(uuidString: "05000000-0000-4000-A000-000000000002"))
        let favorite = Pinboard(id: Pinboard.favoritesID, name: "Favorites", isSystem: true)
        let user = Pinboard(id: userID, name: "Work", colorHex: BoardIdentityColor.blue.rawValue)
        let effectiveColors = [favorite, user].map {
            String(describing: BoardColors.color(for: $0))
        }
        #expect(effectiveColors.allSatisfy { !$0.isEmpty })
    }

    @Test("A valid override wins over the board's automatic color")
    func persistedColorWins() throws {
        let id = try #require(UUID(uuidString: "05000000-0000-4000-A000-000000000001"))
        let automatic = Pinboard(id: id, name: "Automatic")
        let customized = Pinboard(id: id, name: "Customized", colorHex: "#2E70D1")
        let invalid = Pinboard(id: id, name: "Invalid", colorHex: "#FFFFFF")

        #expect(BoardColors.option(for: automatic) == .brown)
        #expect(BoardColors.option(for: customized) == .blue)
        #expect(BoardColors.option(for: invalid) == .brown)
    }

    @Test("Only picker emoji tokens are rendered as board identity")
    func emojiTokensAreClosed() {
        let tokens = BoardIdentityEmoji.allCases.map(\.rawValue)

        #expect(tokens.count == 12)
        #expect(Set(tokens).count == tokens.count)
        #expect(BoardIdentityEmoji.canonicalToken("🎨") == "🎨")
        #expect(BoardIdentityEmoji.canonicalToken("🧪") == nil)
        #expect(BoardIdentityEmoji.canonicalToken(nil) == nil)
    }
}
