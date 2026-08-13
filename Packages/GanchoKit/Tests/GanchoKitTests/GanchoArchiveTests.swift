import CryptoKit
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

    private func readManifest(from directory: URL) throws -> GanchoArchive.Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            GanchoArchive.Manifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    }

    private func writeManifest(
        _ manifest: GanchoArchive.Manifest, to directory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest)
            .write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func readRows(from directory: URL) throws -> [ClipRow] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [ClipRow].self,
            from: Data(contentsOf: directory.appendingPathComponent("clips.json")))
    }

    private func writeRows(_ rows: [ClipRow], to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rows)
        try data.write(to: directory.appendingPathComponent("clips.json"), options: .atomic)
        var manifest = try readManifest(from: directory)
        manifest.checksums["clips.json"] = sha256(data)
        try writeManifest(manifest, to: directory)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func writeBinaryArchive(to directory: URL) async throws -> String {
        let source = try makeStore()
        try await source.insert(
            ClipItem(kind: .image, preview: "Image", contentHash: "binary-row"),
            content: .binary(data: png, typeIdentifier: "public.png"))
        let manifest = try await GanchoArchive.export(from: source, to: directory)
        return try #require(
            manifest.checksums.keys.compactMap { path in
                path.hasPrefix("blobs/") ? String(path.dropFirst("blobs/".count)) : nil
            }.first)
    }

    private func expectCorruptRestore(
        from directory: URL, into store: GRDBClipboardStore,
        limits: GanchoArchive.RestoreLimits = .production
    ) async {
        do {
            _ = try await GanchoArchive.restore(from: directory, into: store, limits: limits)
            Issue.record("expected the archive to be rejected")
        } catch let error as GanchoArchive.ArchiveError {
            guard case .corruptArchive = error else {
                Issue.record("expected corruptArchive, got \(error)")
                return
            }
        } catch {
            Issue.record("expected ArchiveError, got \(error)")
        }
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
}

extension GanchoArchiveTests {
    @Test("Backup defaults exclude sensitive clips")
    func defaultBackupExcludesSensitive() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "●●●●", contentHash: "secret", isSensitive: true),
            content: .text("ghp_private_value"))
        try await source.insert(
            ClipItem(preview: "plain", contentHash: "plain"), content: .text("plain"))

        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = try await GanchoArchive.export(from: source, to: dir)
        let rows = try readRows(from: dir)

        #expect(manifest.clipCount == 1)
        #expect(rows.count == 1)
        #expect(rows.first?.contentHash == "plain")
        let encoded = try Data(contentsOf: dir.appendingPathComponent("clips.json"))
        let archiveText = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(!archiveText.contains("ghp_private_value"))
    }

    @Test("Manifest paths cannot traverse outside the archive")
    func traversalPathRejected() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(preview: "safe", contentHash: "safe"), content: .text("safe"))
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)

        var manifest = try readManifest(from: dir)
        manifest.checksums["blobs/../../outside"] = String(repeating: "0", count: 64)
        try writeManifest(manifest, to: dir)

        let target = try makeStore()
        await expectCorruptRestore(from: dir, into: target)
        #expect(try await target.count() == 0)
    }

    @Test("Declared symlinks are rejected without reading their targets")
    func symlinkedBlobRejected() async throws {
        let dir = tempDir()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-outside-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outside)
        }
        let hash = try await writeBinaryArchive(to: dir)
        try png.write(to: outside)
        let blob = dir.appendingPathComponent("blobs/\(hash)")
        try FileManager.default.removeItem(at: blob)
        try FileManager.default.createSymbolicLink(at: blob, withDestinationURL: outside)

        let target = try makeStore()
        await expectCorruptRestore(from: dir, into: target)
        #expect(!target.blobsForMaintenance.contains(hash: hash))
        #expect(try await target.count() == 0)
    }

    @Test("Blob bytes, checksums, and filenames must identify the same content")
    func renamedBlobRejected() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = try await writeBinaryArchive(to: dir)
        let renamedHash = String(
            repeating: hash == String(repeating: "a", count: 64) ? "b" : "a", count: 64)
        let original = dir.appendingPathComponent("blobs/\(hash)")
        let renamed = dir.appendingPathComponent("blobs/\(renamedHash)")
        try FileManager.default.moveItem(at: original, to: renamed)
        var manifest = try readManifest(from: dir)
        manifest.checksums.removeValue(forKey: "blobs/\(hash)")
        manifest.checksums["blobs/\(renamedHash)"] = renamedHash
        try writeManifest(manifest, to: dir)
        // Reference the renamed blob so it is actually restored — its bytes
        // still hash to the original digest, and must fail at write time.
        var rows = try readRows(from: dir)
        rows[0].contentBlobHash = renamedHash
        try writeRows(rows, to: dir)

        let target = try makeStore()
        do {
            _ = try await GanchoArchive.restore(from: dir, into: target)
            Issue.record("renamed bytes must fail their content-addressed checksum")
        } catch let error as GanchoArchive.ArchiveError {
            #expect(error == .checksumMismatch("blobs/\(renamedHash)"))
        }
        #expect(try await target.count() == 0)
    }

    @Test("Blob references must be lowercase SHA-256 values")
    func invalidBlobReferenceRejected() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await writeBinaryArchive(to: dir)
        var rows = try readRows(from: dir)
        rows[0].contentBlobHash = rows[0].contentBlobHash?.uppercased()
        try writeRows(rows, to: dir)

        let target = try makeStore()
        await expectCorruptRestore(from: dir, into: target)
        #expect(try await target.count() == 0)
    }

    @Test("Missing and orphaned blob declarations are tolerated, never restored")
    func blobReferenceSetMismatchesTolerated() async throws {
        let missingDir = tempDir()
        let orphanDir = tempDir()
        defer {
            try? FileManager.default.removeItem(at: missingDir)
            try? FileManager.default.removeItem(at: orphanDir)
        }

        // The shipped v1 exporter silently skipped store-missing blobs while
        // keeping the rows that reference them: every row restores, and the
        // missing payload stays missing — no blob is invented.
        let missingHash = try await writeBinaryArchive(to: missingDir)
        var missingManifest = try readManifest(from: missingDir)
        missingManifest.checksums.removeValue(forKey: "blobs/\(missingHash)")
        try writeManifest(missingManifest, to: missingDir)
        try FileManager.default.removeItem(
            at: missingDir.appendingPathComponent("blobs/\(missingHash)"))
        let missingTarget = try makeStore()
        let missingSummary = try await GanchoArchive.restore(
            from: missingDir, into: missingTarget)
        #expect(missingSummary.inserted == 1)
        #expect(try await missingTarget.count() == 1)
        #expect(!missingTarget.blobsForMaintenance.contains(hash: missingHash))

        // A declared blob no row references is valid input but junk output:
        // the rows restore and the orphan never enters the store.
        _ = try await writeBinaryArchive(to: orphanDir)
        let orphan = Data("orphan".utf8)
        let orphanHash = sha256(orphan)
        try orphan.write(to: orphanDir.appendingPathComponent("blobs/\(orphanHash)"))
        var orphanManifest = try readManifest(from: orphanDir)
        orphanManifest.checksums["blobs/\(orphanHash)"] = orphanHash
        try writeManifest(orphanManifest, to: orphanDir)
        let orphanTarget = try makeStore()
        let orphanSummary = try await GanchoArchive.restore(
            from: orphanDir, into: orphanTarget)
        #expect(orphanSummary.inserted == 1)
        #expect(try await orphanTarget.count() == 1)
        #expect(!orphanTarget.blobsForMaintenance.contains(hash: orphanHash))
    }

    @Test("Manifest clip count must exactly match clips.json")
    func clipCountMismatchRejected() async throws {
        let source = try makeStore()
        try await source.insert(ClipItem(preview: "x", contentHash: "x"), content: .text("x"))
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)
        var manifest = try readManifest(from: dir)
        manifest.clipCount += 1
        try writeManifest(manifest, to: dir)

        let target = try makeStore()
        await expectCorruptRestore(from: dir, into: target)
        #expect(try await target.count() == 0)
    }

    @Test("Manifest, clips, rows, blobs, and aggregate bytes are bounded")
    func restoreResourceLimits() async throws {
        let textDir = tempDir()
        let binaryDir = tempDir()
        defer {
            try? FileManager.default.removeItem(at: textDir)
            try? FileManager.default.removeItem(at: binaryDir)
        }

        let source = try makeStore()
        try await source.insert(ClipItem(preview: "x", contentHash: "x"), content: .text("x"))
        try await GanchoArchive.export(from: source, to: textDir)
        _ = try await writeBinaryArchive(to: binaryDir)

        var manifestLimit = GanchoArchive.RestoreLimits.production
        manifestLimit.manifestBytes = 1
        await expectCorruptRestore(
            from: textDir, into: try makeStore(), limits: manifestLimit)

        var clipsLimit = GanchoArchive.RestoreLimits.production
        clipsLimit.clipsBytes = 1
        await expectCorruptRestore(from: textDir, into: try makeStore(), limits: clipsLimit)

        var rowLimit = GanchoArchive.RestoreLimits.production
        rowLimit.rowCount = 0
        await expectCorruptRestore(from: textDir, into: try makeStore(), limits: rowLimit)

        var countLimit = GanchoArchive.RestoreLimits.production
        countLimit.blobCount = 0
        await expectCorruptRestore(from: binaryDir, into: try makeStore(), limits: countLimit)

        var blobLimit = GanchoArchive.RestoreLimits.production
        blobLimit.blobBytes = png.count - 1
        await expectCorruptRestore(from: binaryDir, into: try makeStore(), limits: blobLimit)

        var totalLimit = GanchoArchive.RestoreLimits.production
        totalLimit.totalBlobBytes = Int64(png.count - 1)
        await expectCorruptRestore(from: binaryDir, into: try makeStore(), limits: totalLimit)
    }

    /// Deliberate: blob ownership can't be decided atomically with the
    /// database, so an eager delete could race a concurrent capture that just
    /// adopted the hash. The safe outcome is a harmless content-addressed
    /// orphan, re-adopted by any future capture of the same content.
    @Test("A database failure rolls back rows and leaves created blobs as orphans")
    func databaseFailureLeavesOrphanBlobs() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = try await writeBinaryArchive(to: dir)
        let target = try makeStore()
        try await target.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_archive_insert
                    BEFORE INSERT ON clip
                    BEGIN SELECT RAISE(ABORT, 'restore rejected'); END
                    """)
        }

        do {
            _ = try await GanchoArchive.restore(from: dir, into: target)
            Issue.record("the trigger should reject the restore transaction")
        } catch {}
        #expect(try await target.count() == 0)
        #expect(target.blobsForMaintenance.contains(hash: hash))
    }

    @Test("Rollback never deletes a blob that existed before restore")
    func databaseFailurePreservesExistingBlob() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = try await writeBinaryArchive(to: dir)
        let target = try makeStore()
        #expect(try target.blobsForMaintenance.write(png) == hash)
        try await target.writer.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER reject_archive_insert
                    BEFORE INSERT ON clip
                    BEGIN SELECT RAISE(ABORT, 'restore rejected'); END
                    """)
        }

        do {
            _ = try await GanchoArchive.restore(from: dir, into: target)
            Issue.record("the trigger should reject the restore transaction")
        } catch {}
        #expect(try await target.count() == 0)
        #expect(try target.blobsForMaintenance.read(hash: hash) == png)
    }

    @Test("Unlisted physical files are ignored for forward compatibility")
    func unrelatedFilesAreIgnored() async throws {
        let dir = tempDir()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlisted-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outside)
        }
        _ = try await writeBinaryArchive(to: dir)
        try Data("not declared".utf8).write(
            to: dir.appendingPathComponent("blobs/not-a-manifest-entry"))
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("unlisted-link"), withDestinationURL: outside)

        let target = try makeStore()
        let summary = try await GanchoArchive.restore(from: dir, into: target)
        #expect(summary.inserted == 1)
        #expect(try await target.count() == 1)
    }

    @Test("Export refuses a row whose content-addressed blob is missing")
    func exportRejectsMissingSourceBlob() async throws {
        let source = try makeStore()
        try await source.insert(
            ClipItem(kind: .image, preview: "Image", contentHash: "missing-source"),
            content: .binary(data: png, typeIdentifier: "public.png"))
        let hash = sha256(png)
        source.blobsForMaintenance.delete(hash: hash)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect(throws: GanchoArchive.ArchiveError.self) {
            try await GanchoArchive.export(from: source, to: dir)
        }
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
