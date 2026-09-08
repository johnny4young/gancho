import CryptoKit
import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Archive export — streamed, byte-identical to the array encoding")
struct ArchiveStreamingTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("archive-stream-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Streaming row by row produces the same bytes as encoding the array")
    func streamedBytesMatchTheArrayEncoding() async throws {
        let store = try makeStore()
        for index in 0..<40 {
            _ = try await store.insert(
                ClipItem(
                    kind: .text, title: "t\(index)", preview: "p\(index)",
                    contentHash: "h\(index)",
                    isSensitive: index.isMultiple(of: 7)),
                content: .text("body \(index) — ünïcode, \"quotes\", \\backslash"))
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = try await GanchoArchive.export(
            from: store, to: directory, options: .init(excludeSensitive: false))
        let streamed = try Data(contentsOf: directory.appendingPathComponent("clips.json"))

        // What the previous implementation wrote: fetch everything, encode the
        // array in one go. The format and its checksum are a restore contract,
        // so the streamed bytes have to be indistinguishable from it.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let rows = try await store.writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
        }
        #expect(streamed == (try encoder.encode(rows)))

        // And the manifest still describes what was written.
        #expect(manifest.clipCount == rows.count)
        let digest = SHA256.hash(data: streamed).map { String(format: "%02x", $0) }.joined()
        #expect(manifest.checksums["clips.json"] == digest)
    }

    @Test("Excluding sensitive rows drops them from the stream and the count")
    func sensitiveExclusionStillHolds() async throws {
        let store = try makeStore()
        for index in 0..<10 {
            _ = try await store.insert(
                ClipItem(
                    kind: .text, preview: "p\(index)", contentHash: "h\(index)",
                    isSensitive: index < 4),
                content: .text("body"))
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = try await GanchoArchive.export(
            from: store, to: directory, options: .init(excludeSensitive: true))

        #expect(manifest.clipCount == 6)
        let streamed = try Data(contentsOf: directory.appendingPathComponent("clips.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ClipRow].self, from: streamed)
        #expect(decoded.count == 6)
        #expect(!decoded.contains { $0.isSensitive })
    }

    @Test("A failed export leaves no half-written clips.json behind")
    func stagingLeavesNothingOnFailure() async throws {
        let store = try makeStore()
        _ = try await store.insert(
            ClipItem(kind: .image, preview: "img", contentHash: "img"),
            content: .binary(data: Data([0x1, 0x2]), typeIdentifier: "public.png"))
        // Delete the blob the export will demand, so it throws after the rows
        // have already streamed.
        let blobs = FileManager.default.temporaryDirectory
        _ = blobs  // the store's blob dir is per-test; emptying it is enough
        try? FileManager.default.removeItem(at: store.blobsForMaintenance.directory)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: (any Error).self) {
            try await GanchoArchive.export(from: store, to: directory)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(
            !leftovers.contains { $0.hasPrefix(".clips.json.") },
            "a staging file survived: \(leftovers)")
    }
}
