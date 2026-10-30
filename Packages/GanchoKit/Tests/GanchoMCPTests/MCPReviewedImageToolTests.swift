import CoreGraphics
import Foundation
import GanchoKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GanchoMCP

@Suite("MCP tools — reviewed images on the wire")
struct MCPReviewedImageToolTests {
    private static let recognizedText = "Queue sits between API and workers"

    private struct Fixture {
        let store: GRDBClipboardStore
        let image: ClipItem
        let derivative: ReviewedImageDerivative
    }

    private func makeFixture(saveDerivative: Bool = true) async throws -> Fixture {
        let store = try MCPTestStore.make()
        let context = CGContext(
            data: nil, width: 96, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        let source = output as Data

        let image = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), kind: .image, title: "Private roadmap",
            preview: "Image", contentHash: "wire-reviewed-image",
            sourceAppBundleID: "com.example.private")
        try await store.insert(image, content: .binary(data: source, typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: image.id, text: Self.recognizedText)
        let derivative = try ReviewedImageDerivative.make(from: source)
        if saveDerivative { try store.saveReviewedImage(derivative) }
        return Fixture(store: store, image: image, derivative: derivative)
    }

    private func runner(_ fixture: Fixture, _ shares: [MCPClipRepresentation]?) -> MCPToolRunner {
        let grant = MCPClientGrant(
            clientName: "Wire fixture", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: [fixture.image.id],
                clipRevisions: [fixture.image.id.uuidString: fixture.image.contextRevision],
                clipRepresentations: shares.map { [fixture.image.id.uuidString: $0] }))
        return MCPToolRunner(store: fixture.store, grantProvider: { .active(grant) }, log: { _ in })
    }

    private func imageOnly(_ fixture: Fixture) -> [MCPClipRepresentation] {
        [.reviewedImage(MCPReviewedImage(fixture.derivative))]
    }

    private func getClip(_ fixture: Fixture, with runner: MCPToolRunner) async -> MCPToolResult {
        await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(fixture.image.id.uuidString)]))
    }

    @Test("get_clip follows its JSON block with the reviewed bytes as an image block")
    func getClipReturnsImageBlock() async throws {
        let fixture = try await makeFixture()
        let result = await getClip(fixture, with: runner(fixture, imageOnly(fixture)))
        let json = try resultJSON(result)

        #expect(!result.isError)
        #expect(result.content.count == 2)
        #expect(result.content.last == .image(fixture.derivative.data, mimeType: "image/png"))
        #expect(json["image"]?["withheld"]?.boolValue == false)
        #expect(json["image"]?["width"] == .int(fixture.derivative.width))
        #expect(json["content"] == nil, "no text was shared")
        #expect(json["contentWithheld"]?.boolValue == true)
        #expect(json["summary"]?["title"] == nil)
        #expect(json["summary"]?["sourceApp"] == nil)
    }

    @Test("The image block is encoded as base64 with its MIME type")
    func imageBlockEncoding() throws {
        let block = try JSONValue(
            encoding: MCPToolResult.Content.image(Data([1, 2, 3]), mimeType: "image/png"))
        #expect(
            block
                == .object([
                    "type": .string("image"), "data": .string("AQID"),
                    "mimeType": .string("image/png")
                ]))
    }

    @Test("Text and pixels are both sent when both were reviewed")
    func bothSharesAreSent() async throws {
        let fixture = try await makeFixture()
        let shares = [.recognizedText(reviewing: Self.recognizedText)] + imageOnly(fixture)
        let result = await getClip(fixture, with: runner(fixture, shares))
        let json = try resultJSON(result)

        #expect(json["content"]?.stringValue == Self.recognizedText)
        #expect(json["representation"]?.stringValue == "recognizedText")
        #expect(result.content.last == .image(fixture.derivative.data, mimeType: "image/png"))
    }

    @Test("A missing derivative is reported as withheld and sends no image block")
    func missingDerivativeIsWithheld() async throws {
        let fixture = try await makeFixture(saveDerivative: false)
        let result = await getClip(fixture, with: runner(fixture, imageOnly(fixture)))

        #expect(result.content.count == 1)
        #expect(try resultJSON(result)["image"]?["withheld"]?.boolValue == true)
    }

    @Test(
        "Grants that never reviewed the pixels send no image block",
        arguments: [nil, [.recognizedText(reviewing: recognizedText)]] as [[MCPClipRepresentation]?]
    )
    func otherGrantsSendNoImage(shares: [MCPClipRepresentation]?) async throws {
        let fixture = try await makeFixture()
        let result = await getClip(fixture, with: runner(fixture, shares))

        #expect(result.content.count == 1)
        #expect(!result.content.contains { if case .image = $0 { true } else { false } })
        #expect(try resultJSON(result)["image"] == nil)
    }

    @Test("paste_stack skips an image whose only share is its pixels")
    func pasteStackSkipsImageOnlyShares() async throws {
        let fixture = try await makeFixture()
        let result = await runner(fixture, imageOnly(fixture)).call(
            tool: "paste_stack",
            arguments: .object(["ids": .array([.string(fixture.image.id.uuidString)])]))
        #expect(try resultJSON(result)["count"] == .int(0))
    }
}
