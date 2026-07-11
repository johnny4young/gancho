import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

/// In-memory database + throwaway blob directory per test.
private func makeStore() throws -> (GRDBClipboardStore, URL) {
    let blobDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("blob-tests-\(UUID().uuidString)", isDirectory: true)
    let store = GRDBClipboardStore(
        writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDir))
    try store.migrate()
    return (store, blobDir)
}

/// 1×1 PNG for blob/thumbnail round-trips.
private let tinyPNG = Data(
    base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)!

@Suite("GRDBClipboardStore — schema, content, export")
struct GRDBClipboardStoreTests {

    @Test("recentForBrowse floats pinned to the top, then orders by capture time")
    func recentForBrowseOrder() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        // Oldest capture but pinned → must lead. The rest follow by capture time
        // (newest first), regardless of recent use (`lastUsedAt` is ignored here).
        let pinnedOld = ClipItem(
            createdAt: now.addingTimeInterval(-3 * 86_400),
            preview: "pinned-old", contentHash: ClipItem.hash(of: "a", kind: .text), isPinned: true)
        let usedMiddle = ClipItem(
            createdAt: now.addingTimeInterval(-86_400), lastUsedAt: now,
            preview: "middle", contentHash: ClipItem.hash(of: "b", kind: .text))
        let newest = ClipItem(
            createdAt: now, preview: "newest", contentHash: ClipItem.hash(of: "c", kind: .text))
        for item in [pinnedOld, usedMiddle, newest] {
            try await store.insert(item, content: .text(item.preview))
        }
        #expect(
            try await store.recentForBrowse(offset: 0, limit: 10).map(\.id)
                == [pinnedOld.id, newest.id, usedMiddle.id])
    }

    @Test("Text clips round-trip metadata and content")
    func textRoundTrip() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(
            kind: .url, title: "Example", preview: "https://example.com",
            contentHash: ClipItem.hash(of: "https://example.com", kind: .url),
            sourceAppBundleID: "com.apple.Safari", tags: ["web", "ref"])
        try await store.insert(item, content: .text("https://example.com"))

        let fetched = try #require(try await store.items().first)
        // Dates round-trip at SQLite's millisecond precision — compare
        // identity and fields, with tolerance on timestamps.
        #expect(fetched.id == item.id)
        #expect(fetched.kind == item.kind)
        #expect(fetched.title == item.title)
        #expect(fetched.preview == item.preview)
        #expect(fetched.contentHash == item.contentHash)
        #expect(fetched.sourceAppBundleID == item.sourceAppBundleID)
        #expect(fetched.tags == item.tags)
        #expect(abs(fetched.createdAt.timeIntervalSince(item.createdAt)) < 0.01)
        #expect(try await store.content(for: item.id) == .text("https://example.com"))
        #expect(try await store.count() == 1)
    }

    @Test("Binary clips store blobs on disk, not in the row")
    func binaryGoesToBlobStore() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(
            kind: .image, preview: "Image", contentHash: ClipItem.hash(of: tinyPNG, kind: .image))
        try await store.insert(item, content: .binary(data: tinyPNG, typeIdentifier: "public.png"))

        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0 != "thumbnails" }
        #expect(blobFiles.count == 1, "blob must land on disk")
        #expect(
            try await store.content(for: item.id)
                == .binary(data: tinyPNG, typeIdentifier: "public.png"))
    }

    @Test("Thumbnails are warmed at write and cached")
    func warmedThumbnail() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(kind: .image, preview: "Image", contentHash: "img")
        try await store.insert(item, content: .binary(data: tinyPNG, typeIdentifier: "public.png"))

        // Warmed from the in-memory data at write time — the cache exists before
        // any thumbnail request, so a memory-tight reader never loads the full
        // blob just to build it.
        #expect(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("thumbnails").path))

        let url = try #require(try await store.thumbnailURL(for: item.id))
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Repeat requests return the cached file.
        #expect(try await store.thumbnailURL(for: item.id) == url)
    }

    @Test("File references round-trip as paths")
    func fileReferences() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(kind: .fileReference, preview: "a.txt, b.txt", contentHash: "files")
        try await store.insert(
            item, content: .fileReferences(["/tmp/a.txt", "/tmp/b.txt"]))

        #expect(
            try await store.content(for: item.id)
                == .fileReferences(["/tmp/a.txt", "/tmp/b.txt"]))
    }

    @Test("Paging orders pins first, then recency")
    func pagingAndPins() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<10 {
            let item = ClipItem(
                createdAt: base.addingTimeInterval(Double(index)),
                lastUsedAt: base.addingTimeInterval(Double(index)),
                preview: "clip \(index)", contentHash: "h\(index)",
                isPinned: index == 3)
            try await store.insert(item, content: .text("clip \(index)"))
        }

        let firstPage = try await store.items(offset: 0, limit: 3)
        #expect(firstPage.first?.preview == "clip 3", "pinned floats to the top")
        #expect(firstPage.map(\.preview) == ["clip 3", "clip 9", "clip 8"])

        let secondPage = try await store.items(offset: 3, limit: 3)
        #expect(secondPage.map(\.preview) == ["clip 7", "clip 6", "clip 5"])
    }

    @Test("Delete removes the row and the now-orphaned blob")
    func deleteCleansBlobs() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(kind: .image, preview: "Image", contentHash: "img")
        try await store.insert(item, content: .binary(data: tinyPNG, typeIdentifier: "public.png"))
        try await store.delete(id: item.id)

        #expect(try await store.count() == 0)
        let blobFiles =
            (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(!blobFiles.contains { $0 != "thumbnails" }, "orphaned blob must be removed")
    }

    @Test("deleteAllSensitive removes orphaned blobs but never a shared one")
    func deleteAllSensitiveKeepsSharedBlobs() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Same bytes → one content-addressed blob file, referenced by a
        // sensitive row AND a plain row (distinct contentHash keeps two rows).
        let sensitive = ClipItem(
            kind: .image, preview: "secret shot", contentHash: "h-secret", isSensitive: true)
        let plain = ClipItem(kind: .image, preview: "plain shot", contentHash: "h-plain")
        for item in [sensitive, plain] {
            try await store.insert(
                item, content: .binary(data: tinyPNG, typeIdentifier: "public.png"))
        }

        #expect(try await store.deleteAllSensitive() == 1)
        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0 != "thumbnails" }
        #expect(blobFiles.count == 1, "the plain row still references the blob")
        #expect(
            try await store.content(for: plain.id)
                == .binary(data: tinyPNG, typeIdentifier: "public.png"))

        // With the last reference gone the blob file goes too.
        try await store.delete(id: plain.id)
        let leftover = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0 != "thumbnails" }
        #expect(leftover.isEmpty)
    }

    @Test("JSON export is versioned and carries content text")
    func jsonExport() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "hello", contentHash: "h1"), content: .text("hello world"))
        let data = try await store.exportJSON()
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["version"] as? Int == 1)
        let clips = try #require(object["clips"] as? [[String: Any]])
        #expect(clips.count == 1)
        #expect(clips[0]["contentText"] as? String == "hello world")
    }

    @Test("CSV export escapes quotes, commas and newlines")
    func csvExport() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "he said \"hi\", twice", contentHash: "h1"),
            content: .text("line one\nline two"))
        let csv = try #require(String(bytes: try await store.exportCSV(), encoding: .utf8))

        #expect(csv.contains("\"he said \"\"hi\"\", twice\""))
        #expect(csv.contains("\"line one\nline two\""))
    }

    @Test("Streamed CSV keeps createdAt order, with sensitive rows skipped in place")
    func csvStreamedOrder() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.insert(
            ClipItem(createdAt: base, preview: "first", contentHash: "h1"),
            content: .text("first"))
        try await store.insert(
            ClipItem(
                createdAt: base.addingTimeInterval(60), preview: "middle secret",
                contentHash: "h2", isSensitive: true),
            content: .text("middle secret"))
        try await store.insert(
            ClipItem(createdAt: base.addingTimeInterval(120), preview: "last", contentHash: "h3"),
            content: .text("last"))

        let filteredCSV = try #require(
            String(bytes: try await store.exportCSV(excludeSensitive: true), encoding: .utf8))
        let lines = filteredCSV.split(separator: "\n")
        #expect(lines.count == 3, "header + the two non-sensitive rows")
        #expect(lines[1].contains("first"))
        #expect(lines[2].contains("last"))
        #expect(!lines.contains { $0.contains("middle secret") })
    }

    @Test("CSV export neutralizes leading formula characters (CSV injection)")
    func csvFormulaInjectionGuard() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "=SUM(A1:A9)", contentHash: "h1"),
            content: .text("=HYPERLINK(\"https://evil.example\",\"click\")"))
        let csv = try #require(String(bytes: try await store.exportCSV(), encoding: .utf8))

        // A leading = + - @ (or tab/CR) is prefixed with a single apostrophe
        // BEFORE the normal RFC-4180 quoting, so spreadsheets render it as
        // literal text instead of executing it as a formula.
        #expect(csv.contains("'=SUM(A1:A9)"))
        #expect(csv.contains("\"'=HYPERLINK(\"\"https://evil.example\"\",\"\"click\"\")\""))
        #expect(!csv.contains(",=SUM"), "no field may start with a raw =")
    }

    @Test("Exports can exclude detector-flagged sensitive clips")
    func exportExcludesSensitive() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "●●●● 6789", contentHash: "hs", isSensitive: true),
            content: .text("ghp_notARealTokenJustAShapeForTesting01"))
        try await store.insert(
            ClipItem(preview: "plain", contentHash: "hp"), content: .text("plain body"))

        let json = try #require(
            String(bytes: try await store.exportJSON(excludeSensitive: true), encoding: .utf8))
        #expect(!json.contains("ghp_notARealTokenJustAShapeForTesting01"))
        #expect(json.contains("plain body"))

        let csv = try #require(
            String(bytes: try await store.exportCSV(excludeSensitive: true), encoding: .utf8))
        #expect(!csv.contains("ghp_notARealTokenJustAShapeForTesting01"))
        #expect(csv.contains("plain body"))

        // The default (protocol) form still includes everything — no silent
        // behavior change for existing callers.
        let full = try #require(String(bytes: try await store.exportJSON(), encoding: .utf8))
        #expect(full.contains("ghp_notARealTokenJustAShapeForTesting01"))
    }

    @Test("Raw-key adoption is env-gated (GANCHO_RAWKEY_ADOPT=1) and OFF by default")
    func rawKeyAdoptionFlag() {
        // `encrypted(directory:keychainAccessGroup:)` branches on exactly this
        // gate; only the literal "1" opts in (rollout: `.audit/06` §5).
        #expect(!GRDBClipboardStore.rawKeyAdoptionEnabled(environment: [:]))
        #expect(
            !GRDBClipboardStore.rawKeyAdoptionEnabled(
                environment: ["GANCHO_RAWKEY_ADOPT": "0"]))
        #expect(
            !GRDBClipboardStore.rawKeyAdoptionEnabled(
                environment: ["GANCHO_RAWKEY_ADOPT": "true"]))
        #expect(
            GRDBClipboardStore.rawKeyAdoptionEnabled(
                environment: ["GANCHO_RAWKEY_ADOPT": "1"]))
    }

    @Test("v16 creates the hot-query indexes")
    func hotQueryIndexes() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The migration is raw SQL, so a typo would only surface at migrate
        // time — assert the indexes actually landed on their tables. (Whether
        // the planner picks them is checked with EXPLAIN QUERY PLAN on a Mac;
        // an unused index is a perf regression, never a correctness one.)
        let clipIndexes = try await store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_index_list('clip')")
        }
        #expect(clipIndexes.contains("idx_clip_recent_activity"))
        #expect(clipIndexes.contains("idx_clip_browse"))
        #expect(clipIndexes.contains("idx_clip_sensitive"))

        let junctionIndexes = try await store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_index_list('clip_board')")
        }
        #expect(junctionIndexes.contains("idx_clip_board_board"))
    }

    @Test("v17 lands its indexes, columns, and local-only tables")
    func v17SchemaLanded() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.writer.read { db in
            let clipIndexes = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_index_list('clip')")
            #expect(clipIndexes.contains("idx_clip_keyword"))
            #expect(clipIndexes.contains("idx_clip_dedupe"))
            #expect(clipIndexes.contains("idx_clip_frecency"))

            let boardColumns = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_table_info('pinboard')")
            #expect(boardColumns.contains("colorHex"))
            #expect(boardColumns.contains("emoji"))

            let embeddingColumns = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_table_info('clip_embedding')")
            #expect(embeddingColumns.contains("modelVersion"))

            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            #expect(tables.contains("search_history"))
            #expect(tables.contains("clip_app_stats"))
        }
    }

    @Test("recordUse bumps uses and lastUsedAt without flagging a re-upload")
    func recordUseBumpsWithoutSyncFlag() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(preview: "pasted", contentHash: "h-use")
        try await store.insert(item, content: .text("pasted"))
        // Whatever the insert left as pending-upload state is the baseline;
        // recordUse must not change it (no sync storm per paste).
        let pendingBefore = try await store.pendingUploadIDs()

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.recordUse(id: item.id, now: now)
        try await store.recordUse(id: item.id, now: now.addingTimeInterval(60))

        let fetched = try #require(try await store.items().first { $0.id == item.id })
        #expect(fetched.uses == 2, "every use bumps the counter")
        #expect(
            abs(
                (fetched.lastUsedAt ?? .distantPast).timeIntervalSince1970
                    - (now.timeIntervalSince1970 + 60)) < 0.01,
            "lastUsedAt freshens to the latest use")
        #expect(
            try await store.pendingUploadIDs() == pendingBefore,
            "recordUse must never flag the clip for re-upload")
    }

    @Test("recordUse survives the move-to-top write after a macOS paste")
    func recordUseSurvivesMoveToTop() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = ClipItem(preview: "pasted", contentHash: "h-use-move")
        try await store.insert(item, content: .text("pasted"))

        // AppModel records the use first, then calls insert(item, content: nil)
        // to move the existing row back to the top of recents.
        try await store.recordUse(id: item.id, now: .now)
        _ = try await store.insert(item, content: nil)

        let fetched = try #require(try await store.items().first { $0.id == item.id })
        #expect(fetched.uses == 1, "the move-to-top write must preserve the use count")
    }

    @Test("A board's color and emoji round-trip through the store")
    func boardIdentityPersists() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Prove the column mapping independently of the editor UI.
        let board = Pinboard(
            name: "Design", sfSymbol: "paintbrush", colorHex: "#34C759", emoji: "🎨")
        try await store.writer.write { db in try PinboardRow(board: board).insert(db) }

        let fetched = try #require(try await store.pinboards().first { $0.id == board.id })
        #expect(fetched.colorHex == "#34C759")
        #expect(fetched.emoji == "🎨")

        // A board without identity stays nil (old boards decode cleanly).
        let plain = Pinboard(name: "Plain")
        try await store.writer.write { db in try PinboardRow(board: plain).insert(db) }
        let fetchedPlain = try #require(try await store.pinboards().first { $0.id == plain.id })
        #expect(fetchedPlain.colorHex == nil)
        #expect(fetchedPlain.emoji == nil)
    }

    @Test("Migrations are idempotent across re-opens")
    func migrationIdempotent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try GRDBClipboardStore(directory: dir)
        try await first.insert(ClipItem(preview: "persisted", contentHash: "p1"))

        // Re-open the same directory: migrator must no-op, data must survive.
        let second = try GRDBClipboardStore(directory: dir)
        #expect(try await second.count() == 1)
        #expect(try await second.items().first?.preview == "persisted")
    }
}
