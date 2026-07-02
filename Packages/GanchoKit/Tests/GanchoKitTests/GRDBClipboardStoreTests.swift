import Foundation
import GRDB
import Testing

@testable import GanchoKit

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
        #expect(blobFiles.filter { $0 != "thumbnails" }.isEmpty, "orphaned blob must be removed")
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
        let csv = String(decoding: try await store.exportCSV(), as: UTF8.self)

        #expect(csv.contains("\"he said \"\"hi\"\", twice\""))
        #expect(csv.contains("\"line one\nline two\""))
    }

    @Test("CSV export neutralizes leading formula characters (CSV injection)")
    func csvFormulaInjectionGuard() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "=SUM(A1:A9)", contentHash: "h1"),
            content: .text("=HYPERLINK(\"https://evil.example\",\"click\")"))
        let csv = String(decoding: try await store.exportCSV(), as: UTF8.self)

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

        let json = String(
            decoding: try await store.exportJSON(excludeSensitive: true), as: UTF8.self)
        #expect(!json.contains("ghp_notARealTokenJustAShapeForTesting01"))
        #expect(json.contains("plain body"))

        let csv = String(
            decoding: try await store.exportCSV(excludeSensitive: true), as: UTF8.self)
        #expect(!csv.contains("ghp_notARealTokenJustAShapeForTesting01"))
        #expect(csv.contains("plain body"))

        // The default (protocol) form still includes everything — no silent
        // behavior change for existing callers.
        let full = String(decoding: try await store.exportJSON(), as: UTF8.self)
        #expect(full.contains("ghp_notARealTokenJustAShapeForTesting01"))
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
