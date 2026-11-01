import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Merged clip parts")
struct ClipPartsTests {
    @Test("Parts join and split back, separators inside a part included")
    func roundTrip() throws {
        let parts = ["Ana Restrepo", "Cra. 43A\n#1-50", "+57 300 000 0000 👋🏽"]
        let (text, boundaries) = try #require(ClipParts.join(parts, separator: .newline))
        #expect(text == parts.joined(separator: "\n"))
        #expect(boundaries.split(text) == parts)

        let (comma, rejoined) = try #require(boundaries.rejoined(text, with: .comma))
        #expect(comma == parts.joined(separator: ", "))
        #expect(rejoined.split(comma) == parts)
        #expect(ClipParts(encoded: boundaries.encoded) == boundaries)
    }

    @Test("Edited text, one part, too many parts and junk don't split")
    func refusals() {
        let boundaries = ClipParts(separator: .space, lengths: [2, 2])
        #expect(boundaries.split("ab cd") == ["ab", "cd"])
        #expect(boundaries.split("ab cde") == nil)
        #expect(boundaries.split("abxcd") == nil)
        #expect(ClipParts.join(["one"], separator: .newline) == nil)
        let many = Array(repeating: "x", count: ClipParts.maximumParts + 1)
        #expect(ClipParts.join(many, separator: .newline) == nil)
        #expect(ClipParts(encoded: "{not json") == nil)
        #expect(ClipParts(encoded: String(repeating: " ", count: 2_000)) == nil)
        #expect(ClipParts(encoded: ClipParts(separator: .space, lengths: [3]).encoded) == nil)
    }

    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clip-parts-tests-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory))
        try store.migrate()
        return (store, directory)
    }

    @Test("A merge writes text, parts and kind, moves the clip up and marks it for upload")
    func mergeWrites() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try await store.insert(
            ClipItem(
                createdAt: .distantPast, kind: .text, preview: "Ana", contentHash: "a"),
            content: .text("Ana"))
        let (text, parts) = try #require(ClipParts.join(["Ana", "Cra. 43A"], separator: .newline))

        #expect(
            try await store.mergeClipText(
                id: item.id, expecting: "Ana", text: text, parts: parts, kind: .address))
        let merged = try #require(try await store.item(id: item.id))
        #expect(merged.parts == parts)
        #expect(merged.kind == .address)
        #expect(merged.lastUsedAt.map { $0 > .distantPast } == true)
        #expect(try await store.content(for: item.id) == .text(text))
        #expect(try await store.pendingUploadIDs().contains(item.id))
        #expect(
            try await store.items(offset: 0, limit: 1).first?.parts == parts, "lists carry parts")

        try await store.updateClipText(id: item.id, text: "edited")
        #expect(try await store.item(id: item.id)?.parts == nil, "an edit drops the parts")
    }

    @Test("A merge refuses a changed, sensitive, snippet or masked target")
    func mergeRefusals() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plain = try await store.insert(
            ClipItem(contentHash: "p"), content: .text("one"))
        let secret = try await store.insert(
            ClipItem(contentHash: "s", isSensitive: true), content: .text("one"))
        let (text, parts) = try #require(ClipParts.join(["one", "two"], separator: .newline))

        #expect(
            !(try await store.mergeClipText(
                id: plain.id, expecting: "other", text: text, parts: parts, kind: .text)))
        #expect(
            !(try await store.mergeClipText(
                id: secret.id, expecting: "one", text: text, parts: parts, kind: .text)))
        #expect(
            !(try await store.mergeClipText(
                id: plain.id, expecting: "one", text: text, parts: parts, kind: .jwt)))
        #expect(
            !(try await store.mergeClipText(
                id: plain.id, expecting: "one", text: "mismatch", parts: parts, kind: .text)))
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isSnippet = 1 WHERE id = ?", arguments: [plain.id.uuidString])
        }
        #expect(
            !(try await store.mergeClipText(
                id: plain.id, expecting: "one", text: text, parts: parts, kind: .text)))
    }

    @Test("A remote update keeps parts only when it leaves the text alone")
    func syncKeepsParts() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let item = try await store.insert(
            ClipItem(updatedAt: base, contentHash: "m"), content: .text("one"))
        let (text, parts) = try #require(ClipParts.join(["one", "two"], separator: .newline))
        _ = try await store.mergeClipText(
            id: item.id, expecting: "one", text: text, parts: parts, kind: .text)
        let local = try #require(try await store.item(id: item.id))

        var oldClient = local
        oldClient.parts = nil
        oldClient.updatedAt = local.updatedAt.addingTimeInterval(1)
        oldClient.isPinned = true
        _ = try await store.applyRemoteUpsert(
            oldClient, content: .text(text), systemFields: Data([1]))
        #expect(try await store.item(id: item.id)?.parts == parts)

        var newClient = oldClient
        let comma = ClipParts(separator: .comma, lengths: [3, 3])
        newClient.parts = comma
        newClient.updatedAt = oldClient.updatedAt.addingTimeInterval(1)
        _ = try await store.applyRemoteUpsert(
            newClient, content: .text("one, two"), systemFields: Data([2]))
        #expect(try await store.item(id: item.id)?.parts == comma)

        var edited = newClient
        edited.parts = nil
        edited.updatedAt = newClient.updatedAt.addingTimeInterval(1)
        _ = try await store.applyRemoteUpsert(
            edited, content: .text("one, tw0"), systemFields: Data([3]))
        #expect(try await store.item(id: item.id)?.parts == nil, "an edit elsewhere drops them")
    }
}
