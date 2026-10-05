import Foundation
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
        // Independent descriptor proves the cross-process kernel lease
        // is actually held after the read, without a timing-based sleep.
        let competing = try BlobOwnershipLease.tryAcquire(
            for: second.blobsForMaintenance.directory)
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
        #expect(FileManager.default.fileExists(
            atPath: second.blobsForMaintenance.directory
                .appendingPathComponent(".ownership.lock").path))
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
}
