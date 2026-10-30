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
            updatedAt: reviewedAt, kind: .image, title: "Diagram", preview: "Image",
            contentHash: "wire-image")
        try await store.insert(
            image,
            content: .binary(data: Data([0x89, 0x50, 0x4E, 0x47]), typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: image.id, text: Self.reviewedText)
        let note = ClipItem(
            updatedAt: reviewedAt, preview: "Deploy note", contentHash: "wire-note")
        try await store.insert(note, content: .text("Deploy note body"))
        return Fixture(store: store, image: image, note: note)
    }

    private func runner(
        _ fixture: Fixture, approvesImageText: Bool = true
    ) -> MCPToolRunner {
        let items = [fixture.image, fixture.note]
        let grant = MCPClientGrant(
            clientName: "Wire fixture", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: Set(items.map(\.id)),
                clipRevisions: Dictionary(
                    uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.contextRevision) }),
                clipRepresentations: approvesImageText
                    ? [fixture.image.id.uuidString: .recognizedText(reviewing: Self.reviewedText)]
                    : nil))
        return MCPToolRunner(store: fixture.store, grantProvider: { .active(grant) }, log: { _ in })
    }

    private func getClip(_ id: UUID, with runner: MCPToolRunner) async -> MCPToolResult {
        await runner.call(tool: "get_clip", arguments: .object(["id": .string(id.uuidString)]))
    }

    private func wireText(_ result: MCPToolResult) -> String {
        result.content.map(\.text).joined()
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
    }

    @Test("get_clip of an ordinary text clip carries no representation label")
    func textClipHasNoRepresentation() async throws {
        let fixture = try await makeFixture()
        let json = try resultJSON(await getClip(fixture.note.id, with: runner(fixture)))
        #expect(json["content"]?.stringValue == "Deploy note body")
        #expect(json["representation"] == nil)
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
        try await fixture.store.attachExtractedText(id: fixture.image.id, text: Self.replacement)
        #expect(try await search("payroll").isEmpty, "unreviewed text must not be searchable")
        #expect(try await search("workers").isEmpty)
    }
}
