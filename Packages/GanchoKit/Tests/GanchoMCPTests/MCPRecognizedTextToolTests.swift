import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP tools — recognized-text grants on the wire")
struct MCPRecognizedTextToolTests {
    private static let reviewedText = "Queue sits between API and workers"
    private static let replacement = "Unreviewed replacement mentions payroll"

    private struct Fixture {
        let store: GRDBClipboardStore
        let image: ClipItem
        let note: ClipItem
    }

    private func makeFixture() async throws -> Fixture {
        let store = try MCPTestStore.make()
        let reviewedAt = Date.now.addingTimeInterval(-60)
        let image = ClipItem(
            updatedAt: reviewedAt, kind: .image, title: "Private roadmap", preview: "Image",
            contentHash: "wire-image", sourceAppBundleID: "com.example.private", isPinned: true)
        try await store.insert(
            image,
            content: .binary(data: Data([0x89, 0x50, 0x4E, 0x47]), typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: image.id, text: Self.reviewedText)
        let note = ClipItem(
            updatedAt: reviewedAt, title: "Deploy note", preview: "Deploy note",
            contentHash: "wire-note", sourceAppBundleID: "com.example.notes")
        try await store.insert(note, content: .text("Deploy note body"))
        return Fixture(store: store, image: image, note: note)
    }

    private func runner(
        _ fixture: Fixture, approvesImageText: Bool = true, scope: MCPAccessScope = .all,
        store: (any MCPClipStore)? = nil
    ) -> MCPToolRunner {
        let items = [fixture.image, fixture.note]
        let grant = MCPClientGrant(
            clientName: "Wire fixture", scope: scope,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: Set(items.map(\.id)),
                clipRevisions: Dictionary(
                    uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.contextRevision) }),
                clipRepresentations: approvesImageText
                    ? [fixture.image.id.uuidString: .recognizedText(reviewing: Self.reviewedText)]
                    : nil))
        return MCPToolRunner(
            store: store ?? fixture.store, grantProvider: { .active(grant) }, log: { _ in })
    }

    private func getClip(_ id: UUID, with runner: MCPToolRunner) async -> MCPToolResult {
        await runner.call(tool: "get_clip", arguments: .object(["id": .string(id.uuidString)]))
    }

    private func wireText(_ result: MCPToolResult) -> String {
        result.content.map(\.text).joined()
    }

    /// Only the identifying fields survive; the review never showed the rest.
    private func expectIdentityOnly(_ summary: JSONValue?, of item: ClipItem) {
        #expect(summary?["id"]?.stringValue == item.id.uuidString)
        #expect(summary?["kind"]?.stringValue == "image")
        #expect(summary?["createdAt"] != nil)
        for hidden in ["title", "preview", "isPinned", "sourceApp"] {
            #expect(summary?[hidden] == nil, "\(hidden) must stay hidden")
        }
    }

    @Test("get_clip returns the reviewed text, labelled as recognized text")
    func getClipReturnsRecognizedText() async throws {
        let fixture = try await makeFixture()
        let result = await getClip(fixture.image.id, with: runner(fixture))
        let json = try resultJSON(result)

        #expect(!result.isError)
        #expect(json["content"]?.stringValue == Self.reviewedText)
        #expect(json["representation"]?.stringValue == "recognizedText")
        #expect(json["contentWithheld"]?.boolValue == false)
        #expect(!wireText(result).contains("binary content"))
        expectIdentityOnly(json["summary"], of: fixture.image)
        #expect(!wireText(result).contains("Private roadmap"))
    }

    @Test("A metadata-scope read of an approved image hides the same fields")
    func metadataReadHidesSummary() async throws {
        let fixture = try await makeFixture()
        let json = try resultJSON(
            await getClip(fixture.image.id, with: runner(fixture, scope: .metadata)))
        #expect(json["contentWithheld"]?.boolValue == true)
        expectIdentityOnly(json["summary"], of: fixture.image)
    }

    @Test("get_clip of an ordinary text clip carries no representation label")
    func textClipHasNoRepresentation() async throws {
        let fixture = try await makeFixture()
        let json = try resultJSON(await getClip(fixture.note.id, with: runner(fixture)))
        #expect(json["content"]?.stringValue == "Deploy note body")
        #expect(json["representation"] == nil)
        #expect(json["summary"]?["title"]?.stringValue == "Deploy note")
        #expect(json["summary"]?["sourceApp"]?.stringValue == "com.example.notes")
    }

    @Test("Re-recognized text is refused like a missing clip and never sent")
    func rewrittenTextIsRefused() async throws {
        let fixture = try await makeFixture()
        let runner = runner(fixture)
        try await fixture.store.attachExtractedText(id: fixture.image.id, text: Self.replacement)
        let result = await getClip(fixture.image.id, with: runner)

        #expect(result.isError)
        #expect(wireText(result) == "No clip with that id.")
    }

    @Test("A grant that never approved the text returns the image description, not its text")
    func unapprovedImageNeverReturnsText() async throws {
        let fixture = try await makeFixture()
        let result = await getClip(
            fixture.image.id, with: runner(fixture, approvesImageText: false))
        let json = try resultJSON(result)

        #expect(json["content"]?.stringValue?.hasPrefix("[binary content: public.png") == true)
        #expect(json["representation"] == nil)
        #expect(!wireText(result).contains(Self.reviewedText))
    }

    @Test("paste_stack combines reviewed text and labels the recognized part")
    func pasteStackIncludesRecognizedText() async throws {
        let fixture = try await makeFixture()
        let result = await runner(fixture).call(
            tool: "paste_stack",
            arguments: .object([
                "ids": .array([
                    .string(fixture.note.id.uuidString), .string(fixture.image.id.uuidString)
                ])
            ]))
        let json = try resultJSON(result)
        let clips = try #require(json["clips"]?.arrayValue)

        #expect(json["combinedText"]?.stringValue == "Deploy note body\n\n\(Self.reviewedText)")
        #expect(clips.map { $0["representation"]?.stringValue } == [nil, "recognizedText"])
        #expect(clips.map { $0["title"]?.stringValue } == ["Deploy note", nil])
    }

    @Test("search_clips matches reviewed text, and nothing once the text is re-recognized")
    func searchStopsMatchingRewrittenText() async throws {
        let fixture = try await makeFixture()
        let runner = runner(fixture)
        func search(_ query: String) async throws -> [String?] {
            let result = await runner.call(
                tool: "search_clips", arguments: .object(["query": .string(query)]))
            return try resultJSON(result)["clips"]?.arrayValue?.map { $0["id"]?.stringValue } ?? []
        }

        #expect(try await search("workers") == [fixture.image.id.uuidString])
        let hit = try resultJSON(
            await runner.call(
                tool: "search_clips", arguments: .object(["query": .string("workers")]))
        )["clips"]?.arrayValue?.first
        expectIdentityOnly(hit, of: fixture.image)
        try await fixture.store.attachExtractedText(id: fixture.image.id, text: Self.replacement)
        #expect(try await search("payroll").isEmpty, "unreviewed text must not be searchable")
        #expect(try await search("workers").isEmpty)
    }

    @Test("Text re-recognized while a search runs is filtered from its results")
    func searchRechecksHitsAfterTheQuery() async throws {
        let fixture = try await makeFixture()
        let racing = RewritingSearchStore(
            base: fixture.store, imageID: fixture.image.id, replacement: Self.replacement)
        let result = await runner(fixture, store: racing).call(
            tool: "search_clips", arguments: .object(["query": .string("payroll")]))

        #expect(try resultJSON(result)["clips"]?.arrayValue?.isEmpty == true)
        #expect(
            try await fixture.store.search(ClipSearchQuery(text: "payroll"), limit: 5).map(\.id)
                == [fixture.image.id],
            "the rewrite landed before the query, so only the second check can filter it")
    }
}

/// Rewrites the image's recognized text after the runner's preliminary checks
/// and immediately before its search query, as a concurrent re-recognition would.
private struct RewritingSearchStore: MCPClipStore {
    let base: GRDBClipboardStore
    let imageID: UUID
    let replacement: String

    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        try await base.attachExtractedText(id: imageID, text: replacement)
        return try await base.search(query, limit: limit)
    }
    func readForMCP(
        id: UUID, grant: MCPClientGrant, requiresContextPack: Bool, now: Date
    ) async throws -> MCPClipReadResult {
        try await base.readForMCP(
            id: id, grant: grant, requiresContextPack: requiresContextPack, now: now)
    }
    func item(id: UUID) async throws -> ClipItem? { try await base.item(id: id) }
    func items(ids: [UUID]) async throws -> [ClipItem] { try await base.items(ids: ids) }
    func setPinned(id: UUID, _ pinned: Bool) async throws {
        try await base.setPinned(id: id, pinned)
    }
    func pinboards() async throws -> [Pinboard] { try await base.pinboards() }
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard {
        try await base.createPinboard(name: name, sfSymbol: sfSymbol)
    }
    func assign(clipID: UUID, toBoard boardID: UUID) async throws {
        try await base.assign(clipID: clipID, toBoard: boardID)
    }
}
