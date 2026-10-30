import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("MCP recognized-text grants")
struct MCPRecognizedTextReadTests {
    private static let reviewedText = "Queue sits between API and workers"
    private static let pixels = Data([0x89, 0x50, 0x4E, 0x47, 0x01])

    private struct Fixture {
        let store: GRDBClipboardStore
        let image: ClipItem
        let note: ClipItem
    }

    private func makeFixture(
        imageText: String? = reviewedText, configure: (inout ClipItem) -> Void = { _ in }
    ) async throws -> Fixture {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "recognized-text-\(UUID())")))
        try store.migrate()
        var image = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), kind: .image, title: "Diagram",
            contentHash: "recognized-image")
        configure(&image)
        try await store.insert(
            image, content: .binary(data: Self.pixels, typeIdentifier: "public.png"))
        if let imageText { try await store.attachExtractedText(id: image.id, text: imageText) }
        let note = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), preview: "Deploy note",
            contentHash: "recognized-note")
        try await store.insert(note, content: .text("Deploy note"))
        return Fixture(store: store, image: image, note: note)
    }

    private func grant(
        _ fixture: Fixture, scope: MCPAccessScope = .all,
        representations: [UUID: [MCPClipRepresentation]]?
    ) -> MCPClientGrant {
        let items = [fixture.image, fixture.note]
        return MCPClientGrant(
            clientName: "Recognized text fixture", scope: scope,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: Set(items.map(\.id)),
                clipRevisions: Dictionary(
                    uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.contextRevision) }),
                clipRepresentations: representations.map { values in
                    Dictionary(uniqueKeysWithValues: values.map { ($0.key.uuidString, $0.value) })
                }))
    }

    private func approvedImageGrant(
        _ fixture: Fixture, scope: MCPAccessScope = .all
    ) -> MCPClientGrant {
        grant(
            fixture, scope: scope,
            representations: [fixture.image.id: [.recognizedText(reviewing: Self.reviewedText)]])
    }

    private func read(
        _ id: UUID, _ grant: MCPClientGrant, in fixture: Fixture
    ) async throws -> MCPClipReadResult {
        try await fixture.store.readForMCP(
            id: id, grant: grant, requiresContextPack: true, now: .now)
    }

    @Test("A recognized-text grant returns only the reviewed OCR text, never the image")
    func returnsReviewedText() async throws {
        let fixture = try await makeFixture()
        let result = try await read(fixture.image.id, approvedImageGrant(fixture), in: fixture)
        guard case .reviewed(let item, let text?, nil) = result else {
            Issue.record("expected recognized text, got \(result)")
            return
        }
        #expect(item.id == fixture.image.id)
        #expect(text == Self.reviewedText)
    }

    @Test(
        "Re-recognized text closes the grant for content and metadata reads alike",
        arguments: [MCPAccessScope.all, .metadata])
    func rewrittenTextFailsClosed(scope: MCPAccessScope) async throws {
        let fixture = try await makeFixture()
        try await fixture.store.attachExtractedText(
            id: fixture.image.id, text: "Unreviewed replacement")
        let stored = try #require(try await fixture.store.item(id: fixture.image.id))
        #expect(
            stored.contextRevision == fixture.image.contextRevision,
            "the rewrite keeps the revision, so only the text comparison can catch it")
        #expect(
            try await read(fixture.image.id, approvedImageGrant(fixture, scope: scope), in: fixture)
                == .outsideContext)
    }

    @Test("A metadata grant on an approved image returns metadata without the text")
    func metadataScopeWithholdsText() async throws {
        let fixture = try await makeFixture()
        let result = try await read(
            fixture.image.id, approvedImageGrant(fixture, scope: .metadata), in: fixture)
        guard case .metadata(let item) = result else {
            Issue.record("expected metadata only, got \(result)")
            return
        }
        #expect(item.id == fixture.image.id)
    }

    @Test("Recognized text is never granted for a clip that is not an image")
    func textClipCannotUseRecognizedText() async throws {
        let fixture = try await makeFixture()
        let grant = grant(
            fixture, representations: [fixture.note.id: [.recognizedText(reviewing: "Deploy note")]]
        )
        #expect(try await read(fixture.note.id, grant, in: fixture) == .outsideContext)
    }

    @Test("An image without stored OCR text cannot satisfy a recognized-text grant")
    func missingTextFailsClosed() async throws {
        let fixture = try await makeFixture(imageText: nil)
        #expect(
            try await read(fixture.image.id, approvedImageGrant(fixture), in: fixture)
                == .outsideContext)
    }

    @Test("A sensitive image stays refused even with a matching recognized-text grant")
    func sensitiveImageIsRefused() async throws {
        let fixture = try await makeFixture { $0.isSensitive = true }
        #expect(
            try await read(fixture.image.id, approvedImageGrant(fixture), in: fixture)
                == .sensitive)
    }

    @Test(
        "A grant without representations keeps returning the image, never its OCR text",
        arguments: [nil, [:]] as [[UUID: [MCPClipRepresentation]]?])
    func legacyGrantNeverReturnsRecognizedText(
        representations: [UUID: [MCPClipRepresentation]]?
    ) async throws {
        let fixture = try await makeFixture()
        let result = try await read(
            fixture.image.id, grant(fixture, representations: representations), in: fixture)
        guard case .content(_, let content) = result else {
            Issue.record("expected the original content, got \(result)")
            return
        }
        #expect(content == .binary(data: Self.pixels, typeIdentifier: "public.png"))
    }

    @Test("Representations round-trip, and a pack that predates them reads as original")
    func codec() throws {
        let id = UUID()
        let pack = MCPContextPack(
            name: "Reviewed", clipIDs: [id],
            clipRepresentations: [id.uuidString: [.recognizedText(reviewing: "text")]])
        let decoded = try JSONDecoder().decode(
            MCPContextPack.self, from: JSONEncoder().encode(pack))
        #expect(decoded == pack)
        #expect(decoded.representations(of: id).first?.authorizes(recognizedText: "text") == true)
        #expect(decoded.representations(of: id).first?.authorizes(recognizedText: "text ") == false)

        var legacy =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any]
        legacy?.removeValue(forKey: "clipRepresentations")
        let legacyPack = try JSONDecoder().decode(
            MCPContextPack.self, from: JSONSerialization.data(withJSONObject: legacy ?? [:]))
        #expect(legacyPack.representations(of: id).isEmpty)
    }

    @Test("An unknown representation fails to decode instead of widening access")
    func unknownRepresentationIsRejected() throws {
        let id = UUID()
        var object =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(MCPContextPack(name: "Reviewed", clipIDs: [id])))
            as? [String: Any]
        object?["clipRepresentations"] = [id.uuidString: [["rawImage": [String: String]()]]]
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                MCPContextPack.self, from: JSONSerialization.data(withJSONObject: object ?? [:]))
        }
    }

    @Test("Stored image text is read only for a permitted image that has some")
    func storedImageText() async throws {
        let fixture = try await makeFixture()
        let store = fixture.store
        #expect(
            try await store.storedImageText(id: fixture.image.id, now: .now) == Self.reviewedText)
        #expect(try await store.storedImageText(id: fixture.note.id, now: .now) == nil)

        let expired = try await makeFixture { $0.expiresAt = .now.addingTimeInterval(-60) }
        #expect(try await expired.store.storedImageText(id: expired.image.id, now: .now) == nil)
        let sensitive = try await makeFixture { $0.isSensitive = true }
        #expect(
            try await sensitive.store.storedImageText(id: sensitive.image.id, now: .now) == nil)
        let blank = try await makeFixture(imageText: "  \n")
        #expect(try await blank.store.storedImageText(id: blank.image.id, now: .now) == nil)
    }
}
