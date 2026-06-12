import Foundation
import Testing

@testable import GanchoKit

@Suite("ClipItem")
struct ClipItemTests {
    @Test("Same content and kind produce the same hash")
    func hashIsDeterministic() {
        let a = ClipItem.hash(of: "hello", kind: .text)
        let b = ClipItem.hash(of: "hello", kind: .text)
        #expect(a == b)
        #expect(a.count == 64)
    }

    @Test("Different content or kind produce different hashes")
    func hashDiscriminates() {
        let base = ClipItem.hash(of: "hello", kind: .text)
        #expect(ClipItem.hash(of: "hello!", kind: .text) != base)
        #expect(ClipItem.hash(of: "hello", kind: .code) != base)
    }
}

@Suite("InMemoryClipboardStore")
struct InMemoryClipboardStoreTests {
    @Test("Re-inserting identical content moves it to the top instead of duplicating")
    func dedupeMovesToTop() async throws {
        let store = InMemoryClipboardStore()
        let hashA = ClipItem.hash(of: "alpha", kind: .text)
        let hashB = ClipItem.hash(of: "beta", kind: .text)

        try await store.insert(ClipItem(preview: "alpha", contentHash: hashA))
        try await store.insert(ClipItem(preview: "beta", contentHash: hashB))
        let duplicate = try await store.insert(ClipItem(preview: "alpha", contentHash: hashA))

        let items = try await store.items()
        #expect(items.count == 2)
        #expect(items.first?.contentHash == hashA)
        #expect(duplicate.lastUsedAt != nil)
    }

    @Test("Delete removes by id")
    func deleteRemoves() async throws {
        let store = InMemoryClipboardStore()
        let item = try await store.insert(
            ClipItem(preview: "x", contentHash: ClipItem.hash(of: "x", kind: .text)))
        try await store.delete(id: item.id)
        let items = try await store.items()
        #expect(items.isEmpty)
    }
}
