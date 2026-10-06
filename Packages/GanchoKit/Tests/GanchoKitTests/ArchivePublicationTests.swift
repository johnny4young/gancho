import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Whole-archive publication preserves the previous backup")
struct ArchivePublicationTests {
    private struct InjectedFailure: Error {}

    private func makeStore(in root: URL, name: String) throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent(name)))
        try store.migrate()
        return store
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
            }
        }
        return result
    }

    @Test("Source and checkpoint failures preserve every old byte and restoreability")
    func preservesExistingArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try makeStore(in: root, name: "original-blobs")
        try await original.insert(
            ClipItem(preview: "original", contentHash: "original"), content: .text("original"))
        let destination = root.appendingPathComponent("backup.ganchoarchive")
        try await GanchoArchive.export(from: original, to: destination)
        try Data("unrelated sentinel".utf8)
            .write(to: destination.appendingPathComponent("sentinel"))
        let before = try snapshot(destination)
        let replacement = try makeStore(in: root, name: "replacement-blobs")
        try await replacement.insert(
            ClipItem(preview: "replacement", contentHash: "replacement"), content: .text("new"))

        for failure in [GanchoArchive.ExportCheckpoint.rows, .blobs, .manifest, .promotion] {
            await #expect(throws: InjectedFailure.self) {
                try await GanchoArchive.export(
                    from: replacement, to: destination, options: .init(),
                    replacement: .replaceExisting,
                    checkpoint: { checkpoint in
                        if checkpoint == failure { throw InjectedFailure() }
                    })
            }
            #expect(try snapshot(destination) == before)
            let restored = try makeStore(in: root, name: "restored-\(UUID().uuidString)")
            let summary = try await GanchoArchive.restore(from: destination, into: restored)
            #expect(summary.inserted == 1)
            let siblings = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(!siblings.contains { $0.hasPrefix(".ganchoarchive-stage-") })
        }
    }

    @Test("Cancellation and missing source blobs cannot damage an existing backup")
    func cancellationAndMissingBlob() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStore(in: root, name: "source-blobs")
        let destination = root.appendingPathComponent("backup.ganchoarchive")
        try await GanchoArchive.export(from: source, to: destination)
        let before = try snapshot(destination)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await GanchoArchive.export(
                from: source, to: destination, replacement: .replaceExisting)
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        let payload = Data("binary fixture".utf8)
        try await source.insert(
            ClipItem(kind: .image, preview: "binary", contentHash: "binary"),
            content: .binary(data: payload, typeIdentifier: "public.data"))
        source.blobsForMaintenance.delete(hash: GanchoArchive.sha256(payload))
        await #expect(throws: (any Error).self) {
            try await GanchoArchive.export(
                from: source, to: destination, replacement: .replaceExisting)
        }
        #expect(try snapshot(destination) == before)
    }

    @Test("Replacement is explicit and successful promotion is self-consistent")
    func explicitSuccessfulReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStore(in: root, name: "blobs")
        let destination = root.appendingPathComponent("backup.ganchoarchive")
        try await GanchoArchive.export(from: source, to: destination)
        let before = try snapshot(destination)
        try await source.insert(
            ClipItem(preview: "new", contentHash: "new"), content: .text("new"))
        await #expect(throws: (any Error).self) {
            try await GanchoArchive.export(from: source, to: destination)
        }
        #expect(try snapshot(destination) == before)
        try await GanchoArchive.export(
            from: source, to: destination, replacement: .replaceExisting)
        let target = try makeStore(in: root, name: "restore-blobs")
        #expect(try await GanchoArchive.restore(from: destination, into: target).inserted == 1)
    }

    @Test("An actual rename failure preserves the prior archive and recovery stage")
    func actualRenameFailurePreservesBackup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStore(in: root, name: "source-blobs")
        let destination = root.appendingPathComponent("backup.ganchoarchive")
        try await GanchoArchive.export(from: source, to: destination)
        try Data("sentinel".utf8).write(to: destination.appendingPathComponent("sentinel"))
        let before = try snapshot(destination)
        let stage = try AtomicArchivePublication.makeStage(beside: destination)
        try Data("replacement fixture".utf8).write(to: stage.appendingPathComponent("clips.json"))
        let recoverable = root.appendingPathComponent(".recoverable-fixture-stage")
        try FileManager.default.moveItem(at: stage, to: recoverable)
        // Exercise the real Darwin syscall's ENOENT path, rather than throwing
        // at the checkpoint before calling the publication primitive.
        #expect(throws: POSIXError.self) {
            try AtomicArchivePublication.publish(
                stage, as: destination, replacement: .replaceExisting)
        }
        #expect(try snapshot(destination) == before)
        let stagedBytes = try Data(contentsOf: recoverable.appendingPathComponent("clips.json"))
        #expect(stagedBytes == Data("replacement fixture".utf8))
        let target = try makeStore(in: root, name: "restore-blobs")
        let summary = try await GanchoArchive.restore(from: destination, into: target)
        #expect(summary.inserted == 0)
    }

    @Test("Replacement refuses a folder that is not a Gancho archive")
    func replacementRefusesForeignFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStore(in: root, name: "blobs")
        let destination = root.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("user notes".utf8).write(to: destination.appendingPathComponent("notes.txt"))
        let before = try snapshot(destination)

        await #expect(throws: CocoaError.self) {
            try await GanchoArchive.export(
                from: source, to: destination, replacement: .replaceExisting)
        }
        #expect(try snapshot(destination) == before)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!siblings.contains { $0.hasPrefix(".ganchoarchive-stage-") })
    }

    @Test("Replacement accepts an empty folder, ignoring Finder metadata")
    func replacementAcceptsEmptyFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStore(in: root, name: "blobs")
        try await source.insert(
            ClipItem(preview: "kept", contentHash: "kept"), content: .text("kept"))
        let destination = root.appendingPathComponent("backup.ganchoarchive")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data().write(to: destination.appendingPathComponent(".DS_Store"))

        try await GanchoArchive.export(
            from: source, to: destination, replacement: .replaceExisting)
        let target = try makeStore(in: root, name: "restore-blobs")
        #expect(try await GanchoArchive.restore(from: destination, into: target).inserted == 1)
    }

    @Test(
        "Volumes without exclusive rename publish new archives and never replace",
        arguments: [ENOTSUP, EINVAL])
    func unsupportedExclusiveRename(failure: Int32) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Models exFAT/FAT/SMB: any flagged rename fails, a plain one works.
        let renamer: AtomicArchivePublication.Renamer = { source, destination, flags in
            flags == 0 ? AtomicArchivePublication.systemRename(source, destination, 0) : failure
        }

        let fresh = root.appendingPathComponent("fresh.ganchoarchive")
        let stage = try AtomicArchivePublication.makeStage(beside: fresh)
        try Data("fresh".utf8).write(to: stage.appendingPathComponent("manifest.json"))
        try AtomicArchivePublication.publish(
            stage, as: fresh, replacement: .failIfExists, renamer: renamer)
        #expect(
            try Data(contentsOf: fresh.appendingPathComponent("manifest.json"))
                == Data("fresh".utf8))

        for policy in [GanchoArchive.ReplacementPolicy.failIfExists, .replaceExisting] {
            let second = try AtomicArchivePublication.makeStage(beside: fresh)
            defer { try? FileManager.default.removeItem(at: second) }
            try Data("second".utf8).write(to: second.appendingPathComponent("manifest.json"))
            #expect(throws: CocoaError.self) {
                try AtomicArchivePublication.publish(
                    second, as: fresh, replacement: policy, renamer: renamer)
            }
            #expect(
                try Data(contentsOf: fresh.appendingPathComponent("manifest.json"))
                    == Data("fresh".utf8))
        }
    }
}
