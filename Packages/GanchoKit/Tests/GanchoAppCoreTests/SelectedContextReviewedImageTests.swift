import CoreGraphics
import Foundation
import GRDB
@_spi(GanchoInternal) import GanchoKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GanchoAppCore

@Suite("Selected context — reviewed images")
struct SelectedContextReviewedImageTests {
    private static let recognizedText = "Queue sits between API and workers"

    private static let png: Data = {
        let context = CGContext(
            data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }()

    private let derivative: ReviewedImageDerivative

    init() throws {
        derivative = try ReviewedImageDerivative.make(from: Self.png)
    }

    @Test("An image shared only as pixels is labelled and makes the context grant-only")
    func imageOnlyShare() throws {
        let image = CombinedTextPart(id: UUID(), content: .image)
        let prepared = try SelectedContextFormatter.format(
            [image], reviewedImages: [image.id: derivative])

        #expect(prepared.markdown.hasSuffix("## Clip 1 (image shared only through MCP)"))
        #expect(!prepared.isCopyable)
        #expect(prepared.reviewedImages[image.id] == derivative)
        #expect(
            prepared.representations[image.id]
                == [.reviewedImage(MCPReviewedImage(derivative))])
    }

    @Test("Text and pixels chosen together produce both shares in that order")
    func textAndImageShare() throws {
        let image = CombinedTextPart(id: UUID(), content: .recognizedText(Self.recognizedText))
        let prepared = try SelectedContextFormatter.format(
            [image], approvedRecognizedText: [image.id],
            reviewedImages: [image.id: derivative])

        #expect(
            prepared.markdown.contains(
                "## Clip 1 (text recognized from an image; the image is shared only through MCP)"))
        #expect(prepared.markdown.contains(Self.recognizedText))
        #expect(
            prepared.representations[image.id] == [
                .recognizedText(reviewing: Self.recognizedText),
                .reviewedImage(MCPReviewedImage(derivative))
            ])
    }

    @Test("Choosing the pixels never adds the recognized text, and the reverse")
    func sharesAreIndependent() throws {
        let image = CombinedTextPart(id: UUID(), content: .recognizedText(Self.recognizedText))
        let pixelsOnly = try SelectedContextFormatter.format(
            [image], reviewedImages: [image.id: derivative])
        let textOnly = try SelectedContextFormatter.format(
            [image], approvedRecognizedText: [image.id])

        #expect(!pixelsOnly.markdown.contains(Self.recognizedText))
        #expect(pixelsOnly.representations[image.id]?.count == 1)
        #expect(textOnly.reviewedImages.isEmpty)
        #expect(textOnly.isCopyable)
    }

    @Test("Pixels offered for a text clip are ignored; the text clip shares its text")
    func textClipIgnoresPixels() throws {
        let note = CombinedTextPart(id: UUID(), content: .text("Deploy note"))
        let prepared = try SelectedContextFormatter.format(
            [note], reviewedImages: [note.id: derivative])
        #expect(prepared.reviewedImages.isEmpty)
        #expect(prepared.representations.isEmpty)
    }

    @Test("Reviewed pixels survive a reload only for unchanged image parts")
    @MainActor
    func retainedImages() {
        let kept = UUID()
        let changed = UUID()
        let reviewed = [
            CombinedTextPart(id: kept, content: .image),
            CombinedTextPart(id: changed, content: .recognizedText("before"))
        ]
        let current = [
            CombinedTextPart(id: kept, content: .image),
            CombinedTextPart(id: changed, content: .recognizedText("after"))
        ]
        let images = [kept: derivative, changed: derivative]
        #expect(
            Set(
                SelectedContextDelivery.retainedImages(
                    images, reviewed: reviewed, current: current
                ).keys) == [kept])
    }

    @Test("The reviewed derivative is built from a visible image and refused otherwise")
    func preparation() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "reviewed-preparation-\(UUID())")))
        try store.migrate()
        let image = ClipItem(kind: .image, contentHash: "preparation-image")
        let sensitive = ClipItem(
            kind: .image, contentHash: "preparation-sensitive", isSensitive: true)
        let note = ClipItem(preview: "note", contentHash: "preparation-note")
        for item in [image, sensitive] {
            try await store.insert(
                item, content: .binary(data: Self.png, typeIdentifier: "public.png"))
        }
        try await store.insert(note, content: .text("note"))

        #expect(
            try await ReviewedImagePreparation.derivative(for: image.id, from: store)
                == derivative)
        for refused in [sensitive.id, note.id, UUID()] {
            await #expect(throws: ReviewedImageDerivative.Failure.unreadable) {
                try await ReviewedImagePreparation.derivative(for: refused, from: store)
            }
        }
    }
}
