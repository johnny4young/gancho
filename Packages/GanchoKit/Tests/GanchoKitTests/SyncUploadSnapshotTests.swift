import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Sync upload metadata and payload share one captured row")
struct SyncUploadSnapshotTests {
    @Test(arguments: [false, true])
    func committedEditsDoNotReplaceAnUploadsCapturedBody(bulk: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-upload-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = UploadSnapshotGate()
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace(options: .profile) { event in
                if case .profile(let statement, _) = event { gate.observe(statement.sql) }
            }
        }
        let pool = try DatabasePool(
            path: directory.appendingPathComponent("store.sqlite").path,
            configuration: configuration)
        let store = GRDBClipboardStore(
            writer: pool, blobs: BlobStore(directory: directory.appendingPathComponent("blobs")))
        try store.migrate()
        let item = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), preview: "first body",
            contentHash: "upload-snapshot")
        try await store.insert(item, content: .text("first body"))

        gate.arm()
        let upload = Task {
            if bulk { return try await store.pendingUploads().first }
            return try await store.pendingUpload(id: item.id)
        }
        defer { gate.resume() }
        try #require(await gate.waitForSnapshot(), "the first upload SELECT must finish")
        // The real WAL reader has materialized its row. A separate writer commits
        // while the reader is still inside the profile callback, before it returns.
        try await store.updateClipText(id: item.id, text: "second body")
        gate.resume()
        let captured = try #require(try await upload.value)

        #expect(captured.item.preview == "first body")
        #expect(captured.content == .text("first body"))
        #expect(try await store.content(for: item.id) == .text("second body"))
        // Acknowledging the older coherent snapshot must retain the newer upload.
        try await store.markUploaded(
            id: item.id, systemFields: Data([1]), uploadedAt: captured.item.updatedAt)
        let next = try #require(try await store.pendingUpload(id: item.id))
        #expect(next.item.preview == "second body")
        #expect(next.content == .text("second body"))
    }
}

/// Pauses after the actual first SELECT finishes, so the existing native store
/// can be edited on a second WAL connection. No production hook or sleep.
private final class UploadSnapshotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private let reached = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func observe(_ sql: String) {
        lock.lock()
        let shouldPause =
            armed && sql.hasPrefix("SELECT * FROM clip")
            && sql.contains("syncSystemFields IS NULL OR needsUpload = 1")
        if shouldPause { armed = false }
        lock.unlock()
        guard shouldPause else { return }
        reached.signal()
        _ = proceed.wait(timeout: .now() + 30)
    }

    func waitForSnapshot() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: self.reached.wait(timeout: .now() + 30) == .success)
            }
        }
    }

    func resume() { proceed.signal() }
}
