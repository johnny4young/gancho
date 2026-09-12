import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Combined text — deterministic, bounded and explicit")
struct CombinedTextServiceTests {
    private func part(_ text: String) -> CombinedTextPart {
        CombinedTextPart(id: UUID(), content: .text(text))
    }

    @Test("Composition preserves caller order, Unicode and embedded newlines")
    func orderAndSeparators() throws {
        let service = CombinedTextService()
        let parts = [part("Hola\nniño"), part("世界"), part("e\u{301}")]
        #expect(try service.compose(parts, separator: "\n\n") == "Hola\nniño\n\n世界\n\ne\u{301}")
        #expect(
            try service.compose(Array(parts.reversed()), separator: " — ")
                == "e\u{301} — 世界 — Hola\nniño")
        #expect(try service.compose(parts, separator: "") == "Hola\nniño世界e\u{301}")
    }

    @Test(
        "Incompatible, protected and missing parts never disappear silently",
        arguments: [CombinedTextPart.Content.incompatible, .protected, .unavailable, .tooLarge])
    func rejectsPartialResult(_ content: CombinedTextPart.Content) throws {
        #expect(
            try CombinedTextService().compose(
                [part("first"), CombinedTextPart(id: UUID(), content: content)], separator: "\n")
                == nil)
    }

    @Test("Byte budget includes separators and never splits Unicode")
    func limits() throws {
        #expect(
            try TextComposition.join(["é", "😀"], separator: "\n", maximumUTF8Bytes: 7) == "é\n😀")
        #expect(throws: TextCompositionError.tooLarge) {
            try TextComposition.join(["é", "😀"], separator: "\n", maximumUTF8Bytes: 6)
        }
        #expect(try TextComposition.join([], separator: "\n", maximumUTF8Bytes: 0).isEmpty)
        #expect(try CombinedTextService().compose([], separator: "\n") == nil)
        #expect(throws: TextCompositionError.tooLarge) {
            try CombinedTextService().compose(
                [part(String(repeating: "x", count: 1_048_577))], separator: "\n")
        }
    }

    @Test("MCP default composition retains the prior double-newline contract")
    func mcpContract() throws {
        let texts = ["alpha", "", "β\nγ"]
        #expect(
            try TextComposition.join(texts, separator: "\n\n") == texts.joined(separator: "\n\n"))
    }
}

@Suite("Combined text source validation")
struct CombinedTextSourceTests {
    @Test("Current protected, missing and binary rows are reported in caller order")
    func sourceValidation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "combined-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try GRDBClipboardStore(directory: directory)
        let text = ClipItem(contentHash: "text")
        let image = ClipItem(kind: .image, contentHash: "image")
        let protected = ClipItem(contentHash: "protected", isSensitive: true)
        let expired = ClipItem(contentHash: "expired", expiresAt: .distantPast)
        _ = try await store.insert(text, content: .text("first"))
        _ = try await store.insert(
            image, content: .binary(data: Data([1]), typeIdentifier: "public.png"))
        _ = try await store.insert(protected, content: .text("synthetic protected"))
        _ = try await store.insert(expired, content: .text("synthetic expired"))
        let missing = UUID()
        let service = CombinedTextService()
        let ids = [missing, text.id, image.id, protected.id, expired.id]
        let parts = try await service.load(ids: ids, from: store)
        #expect(parts.map(\.id) == ids)
        #expect(
            parts.map(\.content) == [
                .unavailable, .text("first"), .incompatible, .protected, .protected
            ])
        #expect(try service.compose(parts, separator: "\n") == nil)
        try await store.delete(id: text.id)
        #expect(try await service.load(ids: [text.id], from: store).first?.content == .unavailable)
    }
}

/// A later content read changes an earlier clip before the batch finishes.
private actor ChangingCombinationReader: ClipReading {
    enum Change: Sendable { case protect, delete, replace, expire }
    let first = ClipItem(contentHash: "first")
    let second = ClipItem(contentHash: "second")
    private let change: Change
    private var changed = false
    private var metadataReads = 0
    init(change: Change) { self.change = change }
    func ids() -> [UUID] { [first.id, second.id] }
    func readCount() -> Int { metadataReads }
    func items(ids: [UUID]) async throws -> [ClipItem] {
        metadataReads += 1
        return ids.compactMap { id in
            if id == second.id { return second }
            guard id == first.id else { return nil }
            guard changed else { return first }
            var current = first
            switch change {
            case .protect: current.isSensitive = true
            case .delete: return nil
            case .replace: current.contentHash = "replacement"
            case .expire: current.expiresAt = .distantPast
            }
            return current
        }
    }
    func content(for id: UUID) async throws -> ClipContent? {
        if id == second.id { changed = true }
        return .text("Synthetic text")
    }
    func item(id: UUID) async throws -> ClipItem? { try await items(ids: [id]).first }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func count() async throws -> Int { 2 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }
}

@Suite("Combined text batch revalidation")
struct CombinedTextBatchValidationTests {
    @Test(
        "Later reads cannot release an earlier changed clip",
        arguments: [
            ChangingCombinationReader.Change.protect, .delete, .replace, .expire
        ])
    fileprivate func revalidatesWholeBatch(change: ChangingCombinationReader.Change) async throws {
        let reader = ChangingCombinationReader(change: change)
        let service = CombinedTextService()
        let parts = try await service.load(ids: reader.ids(), from: reader)
        #expect(parts.first?.content == .unavailable)
        #expect(try service.compose(parts, separator: "\n") == nil)
        #expect(await reader.readCount() == 2)
    }
}
