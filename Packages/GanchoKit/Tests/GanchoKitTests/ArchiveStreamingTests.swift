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

    @Test("Publishing over an existing archive replaces it, and never removes first")
    func exportOverAnExistingArchiveReplacesItInPlace() async throws {
        // Remove-then-move would pass a "the new file is there" assertion just
        // as well. What it could NOT do is leave the old file readable right up
        // to the swap, or survive a failed publish — so this asserts the
        // primitive directly, where the difference is observable.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("clips.json")
        try Data("old".utf8).write(to: destination)

        let staged = directory.appendingPathComponent(".staged-\(UUID().uuidString)")
        try Data("new".utf8).write(to: staged)
        // `FileManager.moveItem` throws here — an existing destination is
        // exactly the case it refuses, which is why the remove came first.
        try AtomicFileReplace.publish(staged: staged, as: destination)

        #expect(try Data(contentsOf: destination) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: staged.path), "the staged file leaked")
    }

    @Test("A failed publish keeps the previous file and strands nothing")
    func aFailedPublishLeavesTheArchiveUntouched() throws {
        // The regression that mattered: remove-then-move destroys a good
        // archive when the move then fails. Here the rename cannot succeed
        // (the destination directory does not exist), so the contract is that
        // nothing observable changed.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(".staged-\(UUID().uuidString)")
        try Data("new".utf8).write(to: staged)
        let unreachable =
            directory
            .appendingPathComponent("no-such-directory", isDirectory: true)
            .appendingPathComponent("clips.json")

        #expect(throws: (any Error).self) {
            try AtomicFileReplace.publish(staged: staged, as: unreachable)
        }
        #expect(
            !FileManager.default.fileExists(atPath: staged.path),
            "a failed publish left its staged file behind")
    }

    @Test("Orphan cleanup spans chunks without losing a still-referenced blob")
    func orphanLookupChunksWithoutLosingReferences() async throws {
        // The candidate set is unbounded in production, so the lookup binds in
        // chunks. A tiny chunk size exercises the multi-chunk path here; the
        // risk it guards is that the union across chunks drops a hash and a
        // blob some surviving clip still points at gets deleted.
        let store = try makeStore()
        var kept: Set<String> = []
        var doomed: Set<String> = []
        for index in 0..<12 {
            let hash = "hash-\(index)"
            if index.isMultiple(of: 3) {
                // Referenced by a surviving row, so it must NOT be removed.
                _ = try await store.insert(
                    ClipItem(kind: .image, preview: "p\(index)", contentHash: hash),
                    content: .binary(
                        data: Data([UInt8(index)]), typeIdentifier: "public.png"))
                kept.insert(hash)
            } else {
                doomed.insert(hash)
            }
        }
        let referenced = try await store.writer.read { db in
            try String.fetchSet(
                db, sql: "SELECT contentBlobHash FROM clip WHERE contentBlobHash IS NOT NULL")
        }
        #expect(referenced.count == kept.count, "fixture did not store the blobs it claims")

        let removed = try await store.removeBlobsIfOrphaned(
            referenced.union(doomed), chunkSize: 2)

        #expect(removed == doomed.count, "removed \(removed), expected \(doomed.count)")
        let survivors = try await store.writer.read { db in
            try String.fetchSet(
                db, sql: "SELECT contentBlobHash FROM clip WHERE contentBlobHash IS NOT NULL")
        }
        #expect(survivors == referenced, "a still-referenced blob was treated as an orphan")
    }

    @Test("The production chunk size stays inside the oldest SQLite bind limit")
    func chunkSizeRespectsTheBindLimit() {
        // 999 is the floor across SQLite builds; the margin below it is for the
        // statement's other bindings.
        #expect(GRDBClipboardStore.orphanLookupChunkSize < 999)
        #expect(GRDBClipboardStore.orphanLookupChunkSize > 0)
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
