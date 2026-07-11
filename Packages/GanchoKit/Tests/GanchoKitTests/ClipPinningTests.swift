import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

private func makePinningStore() throws -> (GRDBClipboardStore, URL) {
    let blobDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clip-pinning-tests-\(UUID().uuidString)", isDirectory: true)
    let store = GRDBClipboardStore(
        writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDirectory))
    try store.migrate()
    return (store, blobDirectory)
}

private func fillPinLimit(in store: GRDBClipboardStore) async throws {
    for index in 0..<PinLimits.freeMaxPins {
        try await store.insert(
            ClipItem(
                preview: "pinned \(index)", contentHash: "pinned-\(index)", isPinned: true),
            content: .text("pinned \(index)"))
    }
}

@Suite("Clip pinning — intents policy and direct entity lookup")
struct ClipPinningTests {
    @Test("Free users receive the pin limit without mutating the clip")
    func freeLimit() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await fillPinLimit(in: store)
        let target = ClipItem(preview: "target", contentHash: "target")
        try await store.insert(target, content: .text("target"))

        let result = try await ClipPinning.perform(
            .pin, clipID: target.id, tier: .free, store: store)

        #expect(result == .freeLimitReached)
        #expect(try await store.items(ids: [target.id]).first?.isPinned == false)
    }

    @Test("Pro users pin beyond the free limit")
    func proBypassesLimit() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await fillPinLimit(in: store)
        let target = ClipItem(preview: "target", contentHash: "target")
        try await store.insert(target, content: .text("target"))

        let result = try await ClipPinning.perform(
            .pin, clipID: target.id, tier: .pro, store: store)

        #expect(result == .pinned)
        #expect(try await store.items(ids: [target.id]).first?.isPinned == true)
        #expect(try await store.pinnedCount() == PinLimits.freeMaxPins + 1)
    }

    @Test("Pin and unpin are idempotent and explicit")
    func idempotentActions() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = ClipItem(preview: "target", contentHash: "target")
        try await store.insert(target, content: .text("target"))

        #expect(
            try await ClipPinning.perform(.pin, clipID: target.id, tier: .free, store: store)
                == .pinned)
        #expect(
            try await ClipPinning.perform(.pin, clipID: target.id, tier: .free, store: store)
                == .alreadyPinned)
        #expect(
            try await ClipPinning.perform(.unpin, clipID: target.id, tier: .free, store: store)
                == .unpinned)
        #expect(
            try await ClipPinning.perform(.unpin, clipID: target.id, tier: .free, store: store)
                == .alreadyUnpinned)
    }

    @Test("Unknown and deleted identifiers are unavailable")
    func unavailableIdentifiers() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(
            try await ClipPinning.perform(.pin, clipID: UUID(), tier: .pro, store: store)
                == .clipUnavailable)

        let deleted = ClipItem(preview: "deleted", contentHash: "deleted")
        try await store.insert(deleted, content: .text("deleted"))
        try await store.delete(id: deleted.id)
        #expect(
            try await ClipPinning.perform(.pin, clipID: deleted.id, tier: .pro, store: store)
                == .clipUnavailable)
    }

    @Test("Direct lookup resolves an entity older than the first 500 clips")
    func oldEntityLookup() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let old = ClipItem(
            createdAt: base, preview: "old", contentHash: "old")
        try await store.insert(old, content: .text("old"))
        for index in 1...500 {
            try await store.insert(
                ClipItem(
                    createdAt: base.addingTimeInterval(Double(index)),
                    preview: "new \(index)", contentHash: "new-\(index)"),
                content: .text("new \(index)"))
        }

        #expect(!((try await store.items(offset: 0, limit: 500)).contains { $0.id == old.id }))
        #expect(try await store.items(ids: [old.id]).map(\.id) == [old.id])
    }

    @Test("Direct lookup preserves request order and omits unknown identifiers")
    func directLookupOrder() async throws {
        let (store, directory) = try makePinningStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ClipItem(preview: "first", contentHash: "first")
        let second = ClipItem(preview: "second", contentHash: "second")
        try await store.insert(first, content: .text("first"))
        try await store.insert(second, content: .text("second"))

        let result = try await store.items(ids: [second.id, UUID(), first.id, second.id])
        #expect(result.map(\.id) == [second.id, first.id, second.id])
    }

    @Test("System-surface presentation masks sensitive flags and secret kinds")
    func sensitivePresentation() {
        let flagged = ClipItem(
            kind: .text, title: "secret title", preview: "secret body",
            contentHash: "flagged", isSensitive: true)
        let malformedSecret = ClipItem(
            kind: .secret, title: "API key", preview: "AKIAIOSFODNN7EXAMPLE",
            contentHash: "kind-only", isSensitive: false)

        #expect(ClipSafePresentation.displayText(for: flagged) == ClipSafePresentation.masked)
        #expect(
            ClipSafePresentation.displayText(for: malformedSecret)
                == ClipSafePresentation.masked)
    }
}
