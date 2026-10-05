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
}
