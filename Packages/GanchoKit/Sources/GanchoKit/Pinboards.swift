import Foundation
import GRDB

/// A named collection of pinned clips that survives history retention.
public struct Pinboard: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var sortIndex: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, sortIndex: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
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
            try PinboardRow.order(Column("sortIndex").asc, Column("createdAt").asc)
                .fetchAll(db).map(\.board)
        }
    }

    @discardableResult
    public func createPinboard(name: String) async throws -> Pinboard {
        let board = Pinboard(name: name)
        try await writer.write { db in
            let nextIndex =
                (try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM pinboard") ?? -1) + 1
            var row = PinboardRow(board: board)
            row.sortIndex = nextIndex
            try row.insert(db)
        }
        return board
    }

    /// Deleting a board never deletes its clips — they return to history.
    public func deletePinboard(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET pinboardID = NULL WHERE pinboardID = ?",
                arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM pinboard WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// nil board = back to plain history. Assigning also pins (a board
    /// member is by definition retained).
    public func assign(clipID: UUID, toBoard boardID: UUID?) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET pinboardID = ?, isPinned = ?, updatedAt = ? WHERE id = ?",
                arguments: [boardID?.uuidString, boardID != nil, Date(), clipID.uuidString])
        }
    }

    public func items(inBoard boardID: UUID) async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow.filter(Column("pinboardID") == boardID.uuidString)
                .order(Column("sortIndex").asc, Column("updatedAt").desc)
                .fetchAll(db).map(\.item)
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
    var sortIndex: Int
    var createdAt: Date

    init(board: Pinboard) {
        id = board.id.uuidString
        name = board.name
        sortIndex = board.sortIndex
        createdAt = board.createdAt
    }

    var board: Pinboard {
        Pinboard(
            id: UUID(uuidString: id) ?? UUID(), name: name, sortIndex: sortIndex,
            createdAt: createdAt)
    }
}
