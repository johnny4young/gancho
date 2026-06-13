import Foundation
import GRDB
import Testing

@testable import GanchoKit

/// The extension-safety contract, exercised: two DatabasePools over the SAME
/// database file (the closest in-process stand-in for app + extension
/// processes — same WAL, same locking protocol) writing the same clip.
@Suite("Cross-process storage safety (WAL)")
struct CrossProcessStorageTests {
    @Test("Two pools on one database: same clip dedupes, nothing corrupts")
    func walConcurrentWriters() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeA = try GRDBClipboardStore(directory: dir)
        let storeB = try GRDBClipboardStore(directory: dir)

        let hash = ClipItem.hash(of: "shared clip", kind: .text)
        // Interleave writes from both "processes".
        for round in 0..<20 {
            let store = round.isMultiple(of: 2) ? storeA : storeB
            try await store.insert(
                ClipItem(preview: "shared clip", contentHash: hash),
                content: .text("shared clip"))
        }

        // Both sides agree: one row, consistent read, index intact.
        #expect(try await storeA.count() == 1)
        #expect(try await storeB.count() == 1)
        #expect(try await storeB.search(ClipSearchQuery(text: "shared")).count == 1)

        // Distinct content from B is immediately visible to A.
        try await storeB.insert(
            ClipItem(preview: "from B", contentHash: "h-b"), content: .text("from B"))
        #expect(try await storeA.count() == 2)
    }

    @Test("Group-less fallback resolves to Application Support")
    func storageLocationFallback() {
        let url = SharedStorageLocation.storeDirectory(appGroupID: nil)
        #expect(url.path.contains("Application Support"))

        let bogus = SharedStorageLocation.storeDirectory(appGroupID: "group.nonexistent.xyz")
        // Either a container (if the OS grants it) or the fallback — never a crash.
        #expect(!bogus.path.isEmpty)
    }
}
