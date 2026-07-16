import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Database row mappings")
struct DatabaseRowMappingTests {
    @Test("ClipRow preserves every domain field and keeps payload references separate")
    func clipRoundTrip() async throws {
        let clip = ClipItem(
            id: try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555")),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_200),
            kind: .richText,
            title: "Release notes",
            preview: "Ship safely",
            contentHash: "row-mapping-hash",
            sourceAppBundleID: "com.example.Editor",
            sourceDeviceName: "Mac",
            isPinned: true,
            isSensitive: false,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            tags: ["release", "safe"],
            keyword: "ship",
            uses: 7)
        var row = ClipRow(item: clip)
        row.contentText = "Full payload"
        row.contentBlobHash = "blob-hash"
        row.contentTypeIdentifier = "public.rtf"
        let persistedRow = row
        let rowID = row.id

        let database = try DatabaseQueue()
        try GanchoDatabaseMigrator.make().migrate(database)
        let fetchedRow = try await database.write { db in
            try persistedRow.insert(db)
            return try ClipRow.fetchOne(db, key: rowID)
        }
        let fetched = try #require(fetchedRow)

        #expect(fetched.item == clip)
        #expect(fetched.contentText == "Full payload")
        #expect(fetched.contentBlobHash == "blob-hash")
        #expect(fetched.contentTypeIdentifier == "public.rtf")
    }

    @Test("PinboardRow preserves synced identity metadata")
    func pinboardRoundTrip() async throws {
        let board = Pinboard(
            id: try #require(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")),
            name: "Launch",
            sfSymbol: "paperplane",
            sortIndex: 4,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isSystem: false,
            colorHex: "#34C759",
            emoji: "🚀")

        let database = try DatabaseQueue()
        try GanchoDatabaseMigrator.make().migrate(database)
        let fetchedRow = try await database.write { db in
            let row = PinboardRow(board: board)
            try row.insert(db)
            return try PinboardRow.fetchOne(db, key: row.id)
        }
        let fetched = try #require(fetchedRow)

        #expect(fetched.board == board)
    }
}
