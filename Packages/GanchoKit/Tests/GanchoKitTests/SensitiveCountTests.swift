import Foundation
import Testing

@testable import GanchoKit

/// The Privacy Center's "Secrets masked" stat used to count clips whose preview
/// literally equalled the mask string — fragile. `sensitiveCount()` counts the
/// detection flag instead, so a secret counts whatever its masked preview looks
/// like.
@Suite("Sensitive count")
struct SensitiveCountTests {
    @Test("Counts every isSensitive clip regardless of its masked preview shape")
    func countsSensitive() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try GRDBClipboardStore(directory: dir)

        try await store.insert(
            ClipItem(preview: "just a note", contentHash: "n1"), content: .text("just a note"))
        // Two secrets whose masked previews differ — the old exact-match proxy
        // would only have caught one of them.
        try await store.insert(
            ClipItem(preview: "•••• 1A2B", contentHash: "s1", isSensitive: true),
            content: .text("AKIAEXAMPLEKEY"))
        try await store.insert(
            ClipItem(preview: "••••", contentHash: "s2", isSensitive: true),
            content: .text("hunter2"))

        #expect(try await store.sensitiveCount() == 2)
    }
}
