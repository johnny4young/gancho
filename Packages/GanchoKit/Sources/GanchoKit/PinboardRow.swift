import Foundation
import GRDB

/// Database row ↔ domain mapping for board metadata. Internal so the public
/// store surface stays expressed in `Pinboard`.
struct PinboardRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinboard"

    var id: String
    var name: String
    var sfSymbol: String
    var sortIndex: Int
    var createdAt: Date
    var isSystem: Bool
    var colorHex: String?
    var emoji: String?

    init(board: Pinboard) {
        id = board.id.uuidString
        name = board.name
        sfSymbol = board.sfSymbol
        sortIndex = board.sortIndex
        createdAt = board.createdAt
        isSystem = board.isSystem
        colorHex = board.colorHex
        emoji = board.emoji
    }

    var board: Pinboard {
        Pinboard(
            id: UUID(uuidString: id) ?? UUID(), name: name, sfSymbol: sfSymbol,
            sortIndex: sortIndex, createdAt: createdAt, isSystem: isSystem,
            colorHex: colorHex, emoji: emoji)
    }
}
