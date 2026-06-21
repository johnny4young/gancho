import Foundation
import GRDB

/// A user-made collection ("board") for grouping clips. A distinct axis from
/// the type filters and from the Library: a clip can belong to many boards
/// (the `clip_board` junction), and membership — unlike pinning — does not sync
/// (it stays device-local). Board members survive history retention.
public struct Pinboard: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    /// Neutral SF Symbol shown in the board rail (the active board takes the
    /// system accent, not the glyph).
    public var sfSymbol: String
    public var sortIndex: Int
    public var createdAt: Date
    /// Built-in boards (Favorites) can't be renamed or deleted and always sort
    /// first; user boards are fully editable.
    public var isSystem: Bool

    public init(
        id: UUID = UUID(), name: String, sfSymbol: String = "square.stack",
        sortIndex: Int = 0, createdAt: Date = .now, isSystem: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.isSystem = isSystem
    }

    /// The always-present, non-deletable Favorites board (seeded by migration).
    /// Display its name via a localized label keyed on `isSystem`, not this raw
    /// value, so it reads "Favoritos" in Spanish.
    public static let favoritesID = UUID(uuidString: "FA000000-0000-4000-A000-000000000001")!
}

/// Free-tier ceilings (PasteBar pattern — the cleanest conversion gate on
/// the market). Pure functions: the command layer consults them with the
/// user's tier; enforcement UX (paywall) is the monetization ticket's job.
public enum PinLimits {
    public static let freeMaxPins = 10
    public static let freeMaxPinboards = 1

    public static func canPin(currentPinCount: Int, isPro: Bool) -> Bool {
        isPro || currentPinCount < freeMaxPins
    }

    public static func canCreatePinboard(currentBoardCount: Int, isPro: Bool) -> Bool {
        isPro || currentBoardCount < freeMaxPinboards
    }
}

extension GRDBClipboardStore {
    // MARK: - Pins

    public func setPinned(id: UUID, _ pinned: Bool) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isPinned = ?, updatedAt = ? WHERE id = ?",
                arguments: [pinned, Date(), id.uuidString])
        }
    }

    public func pinnedCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE isPinned = 1") ?? 0
        }
    }

    // MARK: - Pinboards

    public func pinboards() async throws -> [Pinboard] {
        try await writer.read { db in
            try PinboardRow.order(
                Column("isSystem").desc, Column("sortIndex").asc, Column("createdAt").asc
            )
            .fetchAll(db).map(\.board)
        }
    }

    @discardableResult
    public func createPinboard(
        name: String, sfSymbol: String = "square.stack"
    ) async throws
        -> Pinboard
    {
        let board = Pinboard(name: name, sfSymbol: sfSymbol)
        try await writer.write { db in
            let nextIndex =
                (try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM pinboard") ?? -1) + 1
            var row = PinboardRow(board: board)
            row.sortIndex = nextIndex
            try row.insert(db)
        }
        return board
    }

    /// System boards (Favorites) are immutable — the `isSystem = 0` guard makes
    /// rename a no-op on them even if the UI ever offered it.
    public func renameBoard(id: UUID, name: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET name = ?, needsUpload = 1 WHERE id = ? AND isSystem = 0",
                arguments: [name, id.uuidString])
        }
    }

    /// Deleting a board never deletes its clips — the `clip_board` rows cascade
    /// away and the clips return to plain history. System boards can't be
    /// deleted (the `isSystem = 0` guard).
    public func deletePinboard(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM pinboard WHERE id = ? AND isSystem = 0",
                arguments: [id.uuidString])
        }
    }

    /// Add a clip to a board (idempotent). Orthogonal to pinning: board
    /// membership does not touch `isPinned`.
    public func assign(clipID: UUID, toBoard boardID: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO clip_board (clipID, boardID) VALUES (?, ?)",
                arguments: [clipID.uuidString, boardID.uuidString])
        }
    }

    public func unassign(clipID: UUID, fromBoard boardID: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM clip_board WHERE clipID = ? AND boardID = ?",
                arguments: [clipID.uuidString, boardID.uuidString])
        }
    }

    public func removeFromAllBoards(clipID: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM clip_board WHERE clipID = ?", arguments: [clipID.uuidString])
        }
    }

    /// The boards a clip belongs to — drives the context menu's checkmarks.
    public func boardIDs(forClip clipID: UUID) async throws -> Set<UUID> {
        try await writer.read { db in
            let ids = try String.fetchAll(
                db, sql: "SELECT boardID FROM clip_board WHERE clipID = ?",
                arguments: [clipID.uuidString])
            return Set(ids.compactMap { UUID(uuidString: $0) })
        }
    }

    public func items(inBoard boardID: UUID) async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow
                .filter(
                    sql: "id IN (SELECT clipID FROM clip_board WHERE boardID = ?)",
                    arguments: [boardID.uuidString]
                )
                .order(Column("isPinned").desc, Column("updatedAt").desc)
                .fetchAll(db).map(\.item)
        }
    }

    public func count(inBoard boardID: UUID) async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM clip_board WHERE boardID = ?",
                arguments: [boardID.uuidString]) ?? 0
        }
    }

    /// Replace a clip's board membership from a synced set (the sync layer's
    /// receive path). Any id without a local board gets an unnamed placeholder
    /// so membership is never lost; its name/glyph arrive with the board's own
    /// synced record. `INSERT OR IGNORE` leaves an existing board (e.g. the
    /// seeded Favorites) untouched.
    public func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws {
        try await writer.write { db in
            for boardID in boardIDs {
                // needsUpload = 0: a placeholder is a stub for a board owned by
                // another device — its real record syncs in, we don't push it.
                try db.execute(
                    sql: "INSERT OR IGNORE INTO pinboard "
                        + "(id, name, sfSymbol, sortIndex, createdAt, isSystem, needsUpload) "
                        + "VALUES (?, '', 'square.stack', 0, ?, 0, 0)",
                    arguments: [boardID.uuidString, Date()])
            }
            try db.execute(
                sql: "DELETE FROM clip_board WHERE clipID = ?", arguments: [clipID.uuidString])
            for boardID in boardIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO clip_board (clipID, boardID) VALUES (?, ?)",
                    arguments: [clipID.uuidString, boardID.uuidString])
            }
        }
    }

    /// Manual reorder (the SDK-27 Reorderable Containers API replaces the
    /// call sites when it ships; the column stays either way).
    public func setSortIndex(clipID: UUID, _ index: Int) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET sortIndex = ? WHERE id = ?",
                arguments: [index, clipID.uuidString])
        }
    }
}

struct PinboardRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinboard"

    var id: String
    var name: String
    var sfSymbol: String
    var sortIndex: Int
    var createdAt: Date
    var isSystem: Bool

    init(board: Pinboard) {
        id = board.id.uuidString
        name = board.name
        sfSymbol = board.sfSymbol
        sortIndex = board.sortIndex
        createdAt = board.createdAt
        isSystem = board.isSystem
    }

    var board: Pinboard {
        Pinboard(
            id: UUID(uuidString: id) ?? UUID(), name: name, sfSymbol: sfSymbol,
            sortIndex: sortIndex, createdAt: createdAt, isSystem: isSystem)
    }
}
