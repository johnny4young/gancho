import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Scope counts — boards counted like the panel's list")
struct ScopeCountsTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("scope-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Archived and expired sensitive members are neither counted nor listed")
    func visibleMembersOnly() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let empty = try await store.createPinboard(name: "Empty")
        let visible = ClipItem(preview: "visible", contentHash: "v")
        let archived = ClipItem(preview: "archived", contentHash: "a")
        let expired = ClipItem(
            preview: "expired", contentHash: "e", isSensitive: true,
            expiresAt: .now.addingTimeInterval(-60))
        for item in [visible, archived, expired] {
            try await store.insert(item, content: .text(item.preview))
            try await store.assign(clipID: item.id, toBoard: work.id)
        }
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }

        let counts = try await store.scopeCounts(excluding: [])
        let visibleTotal = try await store.count()
        #expect(counts.total == visibleTotal)
        #expect(counts.boards[work.id] == 1)
        #expect(counts.boards[empty.id] == nil)
        let listed = try await store.items(inBoard: work.id, limit: 10)
        #expect(listed.map(\.id) == [visible.id], "the board list hides what the chip skips")
        let boardCount = try await store.count(inBoard: work.id)
        #expect(boardCount == listed.count)
    }

    @Test("Kinds are counted with the same visibility and sum to the total")
    func kindsSumToTheVisibleTotal() async throws {
        let store = try makeStore()
        let link = ClipItem(kind: .url, preview: "https://example.com", contentHash: "u")
        let code = ClipItem(kind: .code, preview: "let x = 1", contentHash: "c")
        let json = ClipItem(kind: .json, preview: "{}", contentHash: "j")
        let archived = ClipItem(kind: .url, preview: "https://archived.example", contentHash: "a")
        let expired = ClipItem(
            kind: .secret, preview: "expired", contentHash: "e", isSensitive: true,
            expiresAt: .now.addingTimeInterval(-60))
        for item in [link, code, json, archived, expired] {
            try await store.insert(item, content: .text(item.preview))
        }
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }

        let counts = try await store.scopeCounts(excluding: [])
        #expect(counts.kinds == [.url: 1, .code: 1, .json: 1])
        #expect(counts.kinds.values.reduce(0, +) == counts.total)
        let hiding = try await store.scopeCounts(excluding: [code.id])
        #expect(hiding.kinds[.code] == nil, "an excluded clip leaves its kind too")
    }

    @Test("Each board's kinds follow its visible members and sum to its count")
    func kindsPerBoard() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let design = try await store.createPinboard(name: "Design")
        let shared = ClipItem(kind: .json, preview: "{}", contentHash: "shared")
        let pending = ClipItem(kind: .url, preview: "https://pending.example", contentHash: "p")
        let archived = ClipItem(kind: .image, preview: "archived", contentHash: "a")
        let expired = ClipItem(
            kind: .secret, preview: "expired", contentHash: "e", isSensitive: true,
            expiresAt: .now.addingTimeInterval(-60))
        let members: [(ClipItem, [UUID])] = [
            (ClipItem(kind: .url, preview: "https://a.example", contentHash: "u1"), [work.id]),
            (ClipItem(kind: .url, preview: "https://b.example", contentHash: "u2"), [work.id]),
            (ClipItem(kind: .code, preview: "let x = 1", contentHash: "c"), [work.id]),
            (ClipItem(kind: .color, preview: "#112233", contentHash: "k1"), [work.id, design.id]),
            (ClipItem(kind: .color, preview: "#445566", contentHash: "k2"), [design.id]),
            (ClipItem(kind: .image, preview: "image", contentHash: "i"), [design.id]),
            (shared, [work.id, design.id]),
            (pending, [design.id]),
            (archived, [work.id]),
            (expired, [work.id])
        ]
        for (item, boards) in members {
            try await store.insert(item, content: .text(item.preview))
            for board in boards { try await store.assign(clipID: item.id, toBoard: board) }
        }
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }

        let counts = try await store.scopeCounts(excluding: [pending.id])
        #expect(counts.kindsByBoard[work.id] == [.url: 2, .code: 1, .color: 1, .json: 1])
        #expect(counts.kindsByBoard[design.id] == [.color: 2, .image: 1, .json: 1])
        for board in [work.id, design.id] {
            let summed = counts.kindsByBoard[board]?.values.reduce(0, +)
            #expect(summed == counts.boards[board])
        }
        let all = try await store.scopeCounts(excluding: [])
        #expect(all.kindsByBoard[design.id]?[.url] == 1, "only the excluded clip leaves")
    }

    @Test("A kind this build does not know counts as text on its board")
    func unknownKindPerBoardCountsAsText() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let future = ClipItem(kind: .url, preview: "https://future.example", contentHash: "f")
        try await store.insert(future, content: .text(future.preview))
        try await store.assign(clipID: future.id, toBoard: work.id)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET kind = 'future' WHERE id = ?",
                arguments: [future.id.uuidString])
        }

        let counts = try await store.scopeCounts(excluding: [])
        #expect(counts.kindsByBoard[work.id] == [.text: 1])
        #expect(counts.boards[work.id] == 1)
    }

    @Test("The per-board kind query walks the board index, not the whole clip table")
    func boardKindQueryUsesTheBoardIndex() async throws {
        let store = try makeStore()
        var boards: [Pinboard] = []
        for index in 0..<4 { boards.append(try await store.createPinboard(name: "b\(index)")) }
        let kinds: [ClipContentKind] = [.text, .url, .code, .color, .image]
        let seeded = (0..<2_000).map { index in
            (
                item: ClipItem(
                    kind: kinds[index % kinds.count], preview: "p\(index)",
                    contentHash: "h\(index)"),
                content: ClipContent?.some(.text("body"))
            )
        }
        try await store.importBatch(seeded)
        try await store.writer.write { [boards] db in
            for (index, entry) in seeded.prefix(200).enumerated() {
                try db.execute(
                    sql: "INSERT INTO clip_board (clipID, boardID) VALUES (?, ?)",
                    arguments: [entry.item.id.uuidString, boards[index % 4].id.uuidString])
            }
            try db.execute(sql: "ANALYZE")
        }
        let visible = "clip.isArchived = 0 AND \(GRDBClipboardStore.unexpiredPredicate)"
        let plan = try await store.writer.read { db in
            try String.fetchAll(
                db,
                sql: "EXPLAIN QUERY PLAN "
                    + GRDBClipboardStore.boardKindCountsSQL(visible: visible),
                arguments: [Date.now], adapter: ColumnMapping(["detail": "detail"]))
        }
        #expect(
            plan.contains { $0.contains("idx_clip_board_board") }, "board kinds planned as: \(plan)"
        )
        #expect(
            !plan.contains { $0.hasPrefix("SCAN clip") && !$0.contains("clip_board") },
            "board kinds scan every clip: \(plan)")
    }

    @Test("Excluded clips leave both the total and their boards")
    func excludesPendingDeletes() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let kept = ClipItem(preview: "kept", contentHash: "k")
        let pending = ClipItem(preview: "pending", contentHash: "p")
        let loose = ClipItem(preview: "loose", contentHash: "l")
        for item in [kept, pending, loose] {
            try await store.insert(item, content: .text(item.preview))
        }
        try await store.assign(clipID: kept.id, toBoard: work.id)
        try await store.assign(clipID: pending.id, toBoard: work.id)

        let all = try await store.scopeCounts(excluding: [])
        #expect(all.total == 3)
        #expect(all.boards[work.id] == 2)
        let hiding = try await store.scopeCounts(excluding: [pending.id, loose.id])
        #expect(hiding.total == 1)
        #expect(hiding.boards[work.id] == 1)
    }

    @Test("A bulk delete beyond SQLite's variable limit still counts")
    func excludesMoreIDsThanSQLiteBinds() async throws {
        let store = try makeStore()
        let kept = ClipItem(preview: "kept", contentHash: "k")
        let pending = ClipItem(preview: "pending", contentHash: "p")
        for item in [kept, pending] {
            try await store.insert(item, content: .text(item.preview))
        }
        let excluded = Set((0..<120_000).map { _ in UUID() }).union([pending.id])
        let counts = try await store.scopeCounts(excluding: excluded)
        #expect(counts.total == 1)
    }

    @Test("The in-memory fallback counts its rows by kind and leaves pending deletes out")
    func inMemoryFallback() async throws {
        let store = InMemoryClipboardStore()
        let text = ClipItem(kind: .text, preview: "text", contentHash: "t")
        let link = ClipItem(kind: .url, preview: "link", contentHash: "l")
        let pending = ClipItem(kind: .text, preview: "pending", contentHash: "p")
        for item in [text, link, pending] {
            try await store.insert(item, content: .text(item.preview))
        }
        let counts = try await store.scopeCounts(excluding: [pending.id])
        #expect(counts == ScopeCountSnapshot(total: 2, boards: [:], kinds: [.text: 1, .url: 1]))
    }
}
