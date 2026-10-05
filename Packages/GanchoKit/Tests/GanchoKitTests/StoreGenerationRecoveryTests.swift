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
        for name in [
            "gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm", "gancho.sqlite.encrypting",
            "blobs/hash", "blobs/thumbnails/hash.png"
        ] {
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
                try StoreGenerationRecovery.archive(in: root, suffix: "fixture") {
                    if $0 == interruptedName { throw Interrupted() }
                }
            }
            let journal = root.appendingPathComponent(StoreGenerationRecovery.journalName)
            #expect(FileManager.default.fileExists(atPath: journal.path))
            let lease = try StoreGenerationRecovery.openLease(in: root)
            defer { lease.release() }
            let archived = root.appendingPathComponent(".unreadable-fixture")
            for member in StoreGenerationRecovery.members {
                let sourceExists = FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(member).path)
                let archivedExists = FileManager.default.fileExists(
                    atPath: archived.appendingPathComponent(member).path)
                #expect(!sourceExists && archivedExists)
            }
            let blob = try Data(contentsOf: archived.appendingPathComponent("blobs/hash"))
            let thumbnail = try Data(
                contentsOf: archived.appendingPathComponent("blobs/thumbnails/hash.png"))
            #expect(blob == Data("blobs/hash".utf8))
            #expect(thumbnail == Data("blobs/thumbnails/hash.png".utf8))
        }
    }

    @Test("An active generation blocks recovery across independent coordinator connections")
    func activeGenerationCannotBeMoved() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = try StoreGenerationRecovery.openLease(in: root)
        #expect(throws: (any Error).self) {
            try StoreGenerationRecovery.archive(in: root, suffix: "blocked")
        }
        let original = try Data(contentsOf: root.appendingPathComponent("gancho.sqlite"))
        #expect(original == Data("gancho.sqlite".utf8))
        shared.release()
        try StoreGenerationRecovery.archive(in: root, suffix: "allowed")
        let preserved = root.appendingPathComponent(".unreadable-allowed/blobs/hash")
        #expect(FileManager.default.fileExists(atPath: preserved.path))
    }

    @Test("Plaintext and fresh namespace initialization require exclusive ownership")
    func conversionCannotMoveAnActivePool() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fresh = try StoreGenerationRecovery.openLease(
            in: root, checkingPlaintextConversion: true)
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreGenerationRecovery.openLease(in: root)
        }
        let header = Data("SQLite format 3\u{0}".utf8)
        try header.write(to: root.appendingPathComponent("gancho.sqlite"))
        try fresh.downgrade()
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreGenerationRecovery.openLease(in: root, checkingPlaintextConversion: true)
        }
        fresh.release()
        let conversion = try StoreGenerationRecovery.openLease(
            in: root, checkingPlaintextConversion: true)
        defer { conversion.release() }
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreGenerationRecovery.openLease(in: root)
        }
    }

    #if SQLITE_HAS_CODEC
        @Test("Fresh-key binary recapture is readable; old generation survives maintenance")
        func binaryRecovery() async throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let oldKey = String(repeating: "a1", count: 32)
            let newKey = String(repeating: "b2", count: 32)
            let payload = Data("old-generation-binary-payload".utf8)
            let original = ClipItem(kind: .image, preview: "fixture", contentHash: "original")
            var old: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: root, passphrase: oldKey)
            let content = ClipContent.binary(data: payload, typeIdentifier: "public.data")
            try await old?.insert(original, content: content)
            old = nil
            let blobName = GanchoArchive.sha256(payload)
            let oldBlob = root.appendingPathComponent("blobs/\(blobName)")
            let oldBytes = try Data(contentsOf: oldBlob)
            let recovered = try GRDBClipboardStore.openEncrypted(
                directory: root, key: newKey, keyIsFresh: true)
            let recaptured = ClipItem(kind: .image, preview: "fixture", contentHash: "recaptured")
            try await recovered.insert(recaptured, content: content)
            #expect(try await recovered.content(for: recaptured.id) == content)
            _ = try await recovered.removeOrphanedBlobs()
            let children = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)
            let archivedGeneration = children.first {
                $0.lastPathComponent.hasPrefix(".unreadable-")
            }
            let archive = try #require(archivedGeneration)
            let archivedBlob = archive.appendingPathComponent("blobs/\(blobName)")
            let archivedBytes = try Data(contentsOf: archivedBlob)
            #expect(archivedBytes == oldBytes)
            let preserved = try GRDBClipboardStore(directory: archive, passphrase: oldKey)
            #expect(try await preserved.content(for: original.id) == content)
        }
    #endif
}
