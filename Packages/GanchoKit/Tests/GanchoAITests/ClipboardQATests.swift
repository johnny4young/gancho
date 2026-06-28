import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

/// `ClipboardQA.answer` needs the on-device model (device-gated, non-deterministic),
/// but `retrieve` — the privacy-critical grounding step — is pure FTS and unit-
/// testable. This pins the contract the Shortcuts intent and the app both rely on.
@Suite("Ask your clipboard — retrieval is secret-safe")
struct ClipboardQATests {
    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try GRDBClipboardStore(directory: dir), dir)
    }

    @Test("retrieve() surfaces matching clips but never a sensitive one")
    func retrieveFiltersSensitive() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.insert(
            ClipItem(preview: "apollo mission notes", contentHash: "a1"),
            content: .text("apollo mission notes"))
        try await store.insert(
            ClipItem(preview: "apollo launch checklist", contentHash: "a2"),
            content: .text("apollo launch checklist"))
        try await store.insert(
            ClipItem(preview: "apollo root password", contentHash: "a3", isSensitive: true),
            content: .text("apollo root password hunter2"))

        let hits = await ClipboardQA.retrieve(question: "apollo", store: store, useSemantic: false)

        #expect(!hits.isEmpty, "FTS should surface the matching non-sensitive clips")
        #expect(
            hits.allSatisfy { !$0.isSensitive },
            "a sensitive clip must never reach the grounding set, even when it matches")
        #expect(hits.contains { $0.preview == "apollo mission notes" })
    }

    @Test("retrieve() is empty for a blank question")
    func retrieveEmptyForBlank() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.insert(ClipItem(preview: "x", contentHash: "x"), content: .text("x"))

        let hits = await ClipboardQA.retrieve(question: "   ", store: store, useSemantic: false)
        #expect(hits.isEmpty)
    }
}
