import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Store generation recovery — preservation and interrupted moves")
struct StoreGenerationRecoveryTests {
    private struct Interrupted: Error {}

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("blobs/thumbnails"), withIntermediateDirectories: true)
        for name in ["gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm", "blobs/hash",
            "blobs/thumbnails/hash.png"]
        {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    @Test("Every interrupted member move resumes without mixing a new generation")
    func resumesEachMove() throws {
        for interruptedName in StoreGenerationRecovery.members {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(throws: Interrupted.self) {
                try StoreGenerationRecovery.archive(in: root, suffix: "fixture", afterMove: {
                    if $0 == interruptedName { throw Interrupted() }
                })
            }
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(StoreGenerationRecovery.journalName).path))
            let lease = try StoreGenerationRecovery.openLease(in: root)
            defer { lease.release() }
            let archived = root.appendingPathComponent(".unreadable-fixture")
            for member in StoreGenerationRecovery.members {
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(member).path))
                #expect(FileManager.default.fileExists(atPath: archived.appendingPathComponent(member).path))
            }
            #expect(try Data(contentsOf: archived.appendingPathComponent("blobs/hash")) == Data("blobs/hash".utf8))
            #expect(try Data(contentsOf: archived.appendingPathComponent("blobs/thumbnails/hash.png"))
                == Data("blobs/thumbnails/hash.png".utf8))
        }
    }

    @Test("An active generation blocks recovery across independent file descriptors")
    func activeGenerationCannotBeMoved() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = try StoreGenerationRecovery.openLease(in: root)
        #expect(throws: (any Error).self) {
            try StoreGenerationRecovery.archive(in: root, suffix: "blocked")
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("gancho.sqlite")) == Data("gancho.sqlite".utf8))
        shared.release()
        try StoreGenerationRecovery.archive(in: root, suffix: "allowed")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".unreadable-allowed/blobs/hash").path))
    }

    #if SQLITE_HAS_CODEC
        @Test("Fresh-key binary recapture is readable; old generation survives maintenance")
        func binaryRecovery() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let oldKey = String(repeating: "a1", count: 32)
            let newKey = String(repeating: "b2", count: 32)
            let payload = Data("old-generation-binary-payload".utf8)
            let original = ClipItem(kind: .image, preview: "fixture", contentHash: "original")
            var old: GRDBClipboardStore? = try GRDBClipboardStore(directory: root, passphrase: oldKey)
            try await old?.insert(original, content: .binary(data: payload, typeIdentifier: "public.data"))
            old = nil
            let oldBlob = root.appendingPathComponent("blobs/\(GanchoArchive.sha256(payload))")
            let oldBytes = try Data(contentsOf: oldBlob)
            let recovered = try GRDBClipboardStore.openEncrypted(directory: root, key: newKey, keyIsFresh: true)
            let recaptured = ClipItem(kind: .image, preview: "fixture", contentHash: "recaptured")
            try await recovered.insert(recaptured, content: .binary(data: payload, typeIdentifier: "public.data"))
            #expect(try await recovered.content(for: recaptured.id) == .binary(data: payload, typeIdentifier: "public.data"))
            _ = try await recovered.removeOrphanedBlobs()
            let archive = try #require(try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".unreadable-") })
            #expect(try Data(contentsOf: archive.appendingPathComponent("blobs/\(GanchoArchive.sha256(payload))")) == oldBytes)
            let preserved = try GRDBClipboardStore(directory: archive, passphrase: oldKey)
            #expect(try await preserved.content(for: original.id) == .binary(data: payload, typeIdentifier: "public.data"))
        }
    #endif
}
