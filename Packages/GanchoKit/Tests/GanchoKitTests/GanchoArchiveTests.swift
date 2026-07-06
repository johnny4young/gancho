import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Portable archive — export, restore, merge")
struct GanchoArchiveTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("arch-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).ganchoarchive")
    }

    private let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    @Test("Round-trip: emoji and language survive, blobs verify")
    func roundTrip() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "reunión 🪝 jueves", contentHash: "h1"),
            content: .text("reunión 🪝 jueves — más detalles aquí"))
        try await source.insert(
            ClipItem(kind: .image, preview: "Image", contentHash: "h2"),
            content: .binary(data: png, typeIdentifier: "public.png"))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = try await GanchoArchive.export(from: source, to: dir)
        #expect(manifest.clipCount == 2)
        #expect(manifest.checksums.count == 2)  // clips.json + 1 blob

        let target = try makeStore()
        let summary = try await GanchoArchive.restore(from: dir, into: target)
        #expect(summary.inserted == 2)
        #expect(try await target.count() == 2)
        let restored = try await target.items()
        #expect(restored.contains { $0.preview == "reunión 🪝 jueves" })
        #expect(
            try await target.content(for: restored.first { $0.kind == .image }!.id)
                == .binary(data: png, typeIdentifier: "public.png"))
    }

    @Test("A FileWrapper export (what iOS fileExporter writes) round-trips")
    func fileWrapperRoundTrip() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "backup me", contentHash: "fw1"), content: .text("backup me"))
        try await source.insert(
            ClipItem(kind: .image, preview: "Image", contentHash: "fw2"),
            content: .binary(data: png, typeIdentifier: "public.png"))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)

        // iOS exports the archive through a FileWrapper (`fileExporter`):
        // serialize the directory and write it back out, exactly as the system
        // does — the blob and clips must survive that hop.
        let exported = tempDir()
        defer { try? FileManager.default.removeItem(at: exported) }
        try FileWrapper(url: dir).write(to: exported, options: .atomic, originalContentsURL: nil)

        let target = try makeStore()
        let summary = try await GanchoArchive.restore(from: exported, into: target)
        #expect(summary.inserted == 2)
        let restored = try await target.items()
        #expect(restored.contains { $0.preview == "backup me" })
        #expect(
            try await target.content(for: restored.first { $0.kind == .image }!.id)
                == .binary(data: png, typeIdentifier: "public.png"))
    }

    @Test("Merge into an existing base dedupes by hash+device")
    func mergeDedupes() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "shared", contentHash: "h-same"), content: .text("shared"))
        try await source.insert(
            ClipItem(preview: "only in archive", contentHash: "h-new"),
            content: .text("only in archive"))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)

        let target = try makeStore()
        try await target.insert(
            ClipItem(preview: "shared", contentHash: "h-same"), content: .text("shared"))

        let summary = try await GanchoArchive.restore(from: dir, into: target)
        #expect(summary.inserted == 1)
        #expect(summary.skippedDuplicates == 1)
        #expect(try await target.count() == 2)
    }

    @Test("Corrupt clips data fails the checksum BEFORE touching the store")
    func corruptFails() async throws {
        let source = try makeStore()
        try await source.insert(ClipItem(preview: "x", contentHash: "h"), content: .text("x"))
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)

        try Data("tampered".utf8).write(to: dir.appendingPathComponent("clips.json"))

        let target = try makeStore()
        await #expect(throws: GanchoArchive.ArchiveError.checksumMismatch("clips.json")) {
            try await GanchoArchive.restore(from: dir, into: target)
        }
        #expect(try await target.count() == 0, "store must stay untouched")
    }

    @Test("Future archive versions are rejected clearly")
    func futureVersionRejected() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = GanchoArchive.Manifest(
            version: 99, exportedAt: .now, clipCount: 0, checksums: [:])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest)
            .write(to: dir.appendingPathComponent("manifest.json"))

        let target = try makeStore()
        await #expect(throws: GanchoArchive.ArchiveError.unsupportedVersion(99)) {
            try await GanchoArchive.restore(from: dir, into: target)
        }
    }

    @Test("Exclude-sensitive and metadata-only options hold")
    func exportOptions() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "●●●● 6789", contentHash: "hs", isSensitive: true),
            content: .text("ghp_secret"))
        try await source.insert(
            ClipItem(preview: "plain", contentHash: "hp"), content: .text("plain body"))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = try await GanchoArchive.export(
            from: source, to: dir,
            options: .init(excludeSensitive: true, metadataOnly: true))
        #expect(manifest.clipCount == 1)

        let clips = try String(
            contentsOf: dir.appendingPathComponent("clips.json"), encoding: .utf8)
        #expect(!clips.contains("ghp_secret"))
        #expect(!clips.contains("plain body"), "metadata-only must drop content text")
    }

    @Test("Large payload survives the round-trip")
    func largePayload() async throws {
        let source = try makeStore()
        let big = String(repeating: "large payload line\n", count: 50_000)
        try await source.insert(
            ClipItem(preview: "big", contentHash: "hb"), content: .text(big))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)
        let target = try makeStore()
        try await GanchoArchive.restore(from: dir, into: target)

        let item = try #require(try await target.items().first)
        #expect(try await target.content(for: item.id) == .text(big))
    }
}
