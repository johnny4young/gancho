import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

private actor BlobCleanupBarrier {
    private var paused = false
    private var entered: CheckedContinuation<Void, Never>?
    private var continued: CheckedContinuation<Void, Never>?

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { entered = $0 }
    }

    func pause() async {
        await withCheckedContinuation { continuation in
            continued = continuation
            paused = true
            entered?.resume()
            entered = nil
        }
    }

    func resume() { continued?.resume() }
}

@Suite("Blob adoption and orphan deletion share cross-process ownership")
struct BlobOwnershipRaceTests {
    private enum Adoption: CaseIterable, Sendable { case capture, batch, inbox, sync, restore }

    @Test("Cleanup paused after its reference read owns the lease until deletion finishes")
    func adoptionCannotCommitIntoTheDeletionGap() async throws {
        for adoption in Adoption.allCases {
            for cleanup in 0..<3 {
                try await runRace(adoption: adoption, cleanup: cleanup)
            }
        }
    }

    private func runRace(adoption: Adoption, cleanup: Int) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store")
        let first = try GRDBClipboardStore(directory: directory)
        let second = try GRDBClipboardStore(directory: directory)
        let payload = Data("same-binary-fixture".utf8)
        let hash = try first.blobsForMaintenance.write(payload)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: first.blobsForMaintenance.directory
                .appendingPathComponent(hash).path)
        let archive = root.appendingPathComponent("fixture.ganchoarchive")
        try await prepareArchive(adoption: adoption, root: root, archive: archive, payload: payload)
        let barrier = BlobCleanupBarrier()
        let deleting = Task {
            switch cleanup {
            case 0:
                await first.removeBlobIfOrphaned(hash) { await barrier.pause() }
            case 1:
                _ = try await first.removeBlobsIfOrphaned(
                    [hash], afterReferenceCheck: { await barrier.pause() })
            default:
                _ = try await first.removeOrphanedBlobs(
                    olderThan: .now, afterReferenceCheck: { await barrier.pause() })
            }
        }
        await barrier.waitUntilPaused()
        // An independent coordinator connection proves the committed logical
        // token is still held after the read, without a timing-based sleep.
        let competing = try BlobOwnershipLease.tryAcquire(
            for: second.blobOwnershipDirectory())
        #expect(competing == nil)
        competing?.release()
        let item = ClipItem(kind: .image, preview: "fixture", contentHash: "adopted")
        let content = ClipContent.binary(data: payload, typeIdentifier: "public.data")
        let adopting = Task {
            try await adopt(adoption, in: second, item: item, content: content, archive: archive)
        }
        await barrier.resume()
        try await deleting.value
        try await adopting.value
        let items = try await second.items(offset: 0, limit: 5)
        let stored = try #require(items.first)
        #expect(try await second.content(for: stored.id) == content)
        let coordinator = directory.appendingPathComponent(StoreProcessOwnership.fileName)
        #expect(FileManager.default.fileExists(atPath: coordinator.path))
    }

    private func prepareArchive(
        adoption: Adoption, root: URL, archive: URL, payload: Data
    ) async throws {
        if adoption == .restore {
            let source = try GRDBClipboardStore(directory: root.appendingPathComponent("source"))
            try await source.insert(
                ClipItem(kind: .image, preview: "fixture", contentHash: "source"),
                content: .binary(data: payload, typeIdentifier: "public.data"))
            try await GanchoArchive.export(from: source, to: archive)
        }
    }

    private func adopt(
        _ adoption: Adoption, in store: GRDBClipboardStore, item: ClipItem,
        content: ClipContent, archive: URL
    ) async throws {
        switch adoption {
        case .capture: _ = try await store.insert(item, content: content)
        case .batch: try await store.importBatch([(item, content)])
        case .inbox:
            _ = try await store.insertInboxDelivery(id: "fixture", item: item, content: content)
        case .sync:
            _ = try await store.applyRemoteUpsert(item, content: content, systemFields: Data())
        case .restore: _ = try await GanchoArchive.restore(from: archive, into: store)
        }
    }

    @Test("Cancellation while waiting leaves the payload unchanged")
    func canceledWait() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root)
        let payload = Data("fixture".utf8)
        let hash = try store.blobsForMaintenance.write(payload)
        let held = try await store.acquireBlobOwnership()
        defer { held.release() }
        let cleanup = Task { try await store.removeBlobsIfOrphaned([hash]) }
        cleanup.cancel()
        await #expect(throws: CancellationError.self) { try await cleanup.value }
        #expect(try store.blobsForMaintenance.read(hash: hash) == payload)
    }

    @Test("Borrowing a production writer cannot create a second ownership domain")
    func injectedWriterSharesProductionOwnership() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let production = try GRDBClipboardStore(directory: root)
        let injected = GRDBClipboardStore(
            writer: production.writer, blobs: production.blobsForMaintenance)
        #expect(try production.blobOwnershipDirectory() == injected.blobOwnershipDirectory())
        let held = try await production.acquireBlobOwnership()
        defer { held.release() }
        let competing = try BlobOwnershipLease.tryAcquire(for: injected.blobOwnershipDirectory())
        #expect(competing == nil)
        competing?.release()
    }

    @Test("Independent in-memory fixtures do not share a temporary-parent coordinator")
    func inMemoryFixtureNamespaces() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent("a")))
        let second = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent("b")))
        let held = try await first.acquireBlobOwnership()
        defer { held.release() }
        let independent = try await second.acquireBlobOwnership()
        independent.release()
        #expect(try first.blobOwnershipDirectory() != second.blobOwnershipDirectory())
    }

    @Test("A live owner produces bounded busy instead of unsafe lease expiry")
    func liveOwnerWaitIsBounded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root)
        let held = try await store.acquireBlobOwnership()
        defer { held.release() }
        await #expect(throws: StoreProcessOwnership.Failure.self) {
            try await store.acquireBlobOwnership()
        }
        let competing = try BlobOwnershipLease.tryAcquire(for: store.blobOwnershipDirectory())
        #expect(competing == nil)
        competing?.release()
    }

    @Test("A shipped legacy sweep cannot remove the coordinator")
    func legacySweepKeepsCoordination() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root)
        _ = try store.blobsForMaintenance.write(Data("orphan fixture".utf8))
        let ownership = try await store.acquireBlobOwnership()
        defer { ownership.release() }
        let directory = store.blobsForMaintenance.directory
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        // Reproduce the shipped pre-lease sweep's exact exclusions. It does not
        // skip hidden root files. The coordinator is outside the blob root.
        for name in files where name != "thumbnails" && name != BlobStore.migrationMarker {
            store.blobsForMaintenance.delete(hash: name)
        }
        let competing = try BlobOwnershipLease.tryAcquire(for: store.blobOwnershipDirectory())
        #expect(competing == nil)
        competing?.release()
        let protected = root.appendingPathComponent(StoreProcessOwnership.fileName)
        #expect(FileManager.default.fileExists(atPath: protected.path))
    }

    @Test("Text, file and metadata writes never wait for the blob lease")
    func nonBinaryWritesSkipTheLease() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GRDBClipboardStore(directory: root)
        // A long import, restore or sync page in any process holds this lease.
        let held = try await store.acquireBlobOwnership()
        defer { held.release() }
        let clock = ContinuousClock()
        let started = clock.now

        _ = try await store.insert(
            ClipItem(preview: "typed", contentHash: "typed"), content: .text("typed"))
        _ = try await store.insert(
            ClipItem(preview: "file", contentHash: "file"),
            content: .fileReferences(["/tmp/fixture.txt"]))
        try await store.importBatch([
            (ClipItem(preview: "imported", contentHash: "imported"), .text("imported"))
        ])
        _ = try await store.insertInboxDelivery(
            id: "text-fixture", item: ClipItem(preview: "inbox", contentHash: "inbox"),
            content: .text("inbox"))
        _ = try await store.applyRemoteUpsert(
            ClipItem(preview: "remote", contentHash: "remote"), content: .text("remote"),
            systemFields: Data())
        _ = try await store.applyRemoteChanges(
            clips: [
                RemoteClipChange(
                    item: ClipItem(preview: "page", contentHash: "page"), content: .text("page"),
                    systemFields: Data(), boardIDs: [])
            ],
            boards: [], clipDeletions: [], boardDeletions: [])

        #expect(clock.now - started < .seconds(2))
        let previews = Set(try await store.items(offset: 0, limit: 10).map(\.preview))
        #expect(previews.isSuperset(of: ["typed", "file", "imported", "inbox", "remote"]))
        // Binary adoption still waits for the holder and reports busy.
        await #expect(throws: StoreProcessOwnership.Failure.self) {
            try await store.insert(
                ClipItem(kind: .image, preview: "image", contentHash: "image"),
                content: .binary(data: Data("image".utf8), typeIdentifier: "public.data"))
        }
    }
}
