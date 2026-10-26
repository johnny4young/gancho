import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Store health — Verify, size on disk, recent forgets and the weekly skip count")
struct StoreHealthTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("store-health-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Verify passes only for a keyed SQLCipher file that opens")
    func verify() async throws {
        let encryptedDir = directory()
        let plaintextDir = directory()
        defer {
            try? FileManager.default.removeItem(at: encryptedDir)
            try? FileManager.default.removeItem(at: plaintextDir)
        }
        let encrypted = try GRDBClipboardStore(
            directory: encryptedDir, passphrase: UUID().uuidString + UUID().uuidString)
        try await encrypted.insert(
            ClipItem(preview: "one", contentHash: "1"), content: .text("one"))
        let report = await encrypted.encryptionReport()
        #expect(report.cipherVersion != nil)
        #expect(report.fileIsEncrypted)
        #expect(report.opensWithKey)
        #expect(report.isVerified)

        let plaintext = try GRDBClipboardStore(directory: plaintextDir, passphrase: nil)
        try await plaintext.insert(
            ClipItem(preview: "one", contentHash: "1"), content: .text("one"))
        let open = await plaintext.encryptionReport()
        #expect(!open.fileIsEncrypted, "a plaintext file starts with SQLite's header")
        #expect(open.fileFound)
        #expect(!open.isVerified)

        let memory = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory()))
        try memory.migrate()
        let missing = await memory.encryptionReport()
        #expect(!missing.fileFound, "an in-memory store has no file to check")
        #expect(!missing.isVerified)
    }

    @Test("Size on disk counts the database and its blobs; an in-memory store is zero")
    func diskUsage() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try GRDBClipboardStore(directory: dir)
        try await store.insert(ClipItem(preview: "one", contentHash: "1"), content: .text("one"))
        #expect(await store.diskUsage() > 0)
        #expect(await store.diskUsage() == GRDBClipboardStore.allocatedSize(of: dir))

        let memory = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: directory()))
        try memory.migrate()
        #expect(await memory.diskUsage() == 0)
    }

    @Test("A recent forget keeps snippets, pins and board members, and older clips")
    func forgettable() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: directory()))
        try store.migrate()
        let now = Date()
        func clip(_ name: String, minutesAgo: Double, pinned: Bool = false) -> ClipItem {
            ClipItem(
                createdAt: now.addingTimeInterval(-minutesAgo * 60), preview: name,
                contentHash: name, isPinned: pinned)
        }
        let recent = clip("recent", minutesAgo: 2)
        let pinned = clip("pinned", minutesAgo: 3, pinned: true)
        let filed = clip("filed", minutesAgo: 4)
        let snippet = clip("snippet", minutesAgo: 5)
        let old = clip("old", minutesAgo: 30)
        for item in [recent, pinned, filed, snippet, old] {
            try await store.insert(item, content: .text(item.preview))
        }
        let board = try await store.createPinboard(name: "Work")
        try await store.assign(clipID: filed.id, toBoard: board.id)
        try await store.promoteToSnippet(id: snippet.id, title: "Snippet")

        let ids = try await store.forgettableClips(since: now.addingTimeInterval(-15 * 60)).map(
            \.id)
        #expect(ids == [recent.id])
        #expect(try await store.forgettableClips(since: now.addingTimeInterval(60)).isEmpty)
    }

    @Test("The weekly count adds protected skips from the last seven days only")
    func weeklyProtectedSkips() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: directory()))
        try store.migrate()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.recordPrivateSkippedCapture(isProtected: true, count: 2, at: now)
        try await store.recordPrivateSkippedCapture(
            isProtected: true, count: 3, at: now.addingTimeInterval(-6 * 86_400))
        try await store.recordPrivateSkippedCapture(
            isProtected: true, count: 40, at: now.addingTimeInterval(-7 * 86_400))
        try await store.recordPrivateSkippedCapture(isProtected: false, count: 9, at: now)
        #expect(try await store.protectedSkips(lastDays: 7, now: now) == 5)
        #expect(try await store.protectedSkips(lastDays: 1, now: now) == 2)
        #expect(try await store.protectedSkips(lastDays: 0, now: now) == 0)
    }
}
