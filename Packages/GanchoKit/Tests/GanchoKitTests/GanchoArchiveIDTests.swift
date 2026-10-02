import CryptoKit
import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Portable archive — restored ids are canonical")
struct GanchoArchiveIDTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("arch-id-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    /// Rewrites clips.json through `transform` and refreshes its checksum.
    private func rewriteRows(in directory: URL, _ transform: ([ClipRow]) -> [ClipRow]) throws {
        let clips = directory.appendingPathComponent("clips.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            transform(try decoder.decode([ClipRow].self, from: Data(contentsOf: clips))))
        try data.write(to: clips, options: .atomic)

        let manifestURL = directory.appendingPathComponent("manifest.json")
        var manifest = try decoder.decode(
            GanchoArchive.Manifest.self, from: Data(contentsOf: manifestURL))
        manifest.checksums["clips.json"] = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    @Test("Malformed ids get a fresh UUID and lowercase ids are canonicalized")
    func idsAreValidated() async throws {
        let source = try makeStore()
        let lower = UUID()
        try await source.insert(ClipItem(preview: "a", contentHash: "a"), content: .text("a"))
        try await source.insert(ClipItem(preview: "b", contentHash: "b"), content: .text("b"))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-id-\(UUID().uuidString).ganchoarchive")
        defer { try? FileManager.default.removeItem(at: dir) }
        try await GanchoArchive.export(from: source, to: dir)
        try rewriteRows(in: dir) { rows in
            var rows = rows
            rows[0].id = "not-a-uuid"
            rows[1].id = lower.uuidString.lowercased()
            return rows
        }

        let target = try makeStore()
        _ = try await GanchoArchive.restore(from: dir, into: target)

        let ids = try await target.writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM clip")
        }
        #expect(ids.count == 2)
        #expect(ids.allSatisfy { UUID(uuidString: $0)?.uuidString == $0 })
        #expect(ids.contains(lower.uuidString))
        #expect(try await target.content(for: lower) != nil)
    }
}
