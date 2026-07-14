import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor PreviewContentProbe {
    enum Failure: Error { case unavailable }

    var content: ClipContent?
    var shouldFail = false
    private(set) var requestedIDs: [UUID] = []

    init(content: ClipContent?) {
        self.content = content
    }

    func load(_ id: UUID) throws -> ClipContent? {
        requestedIDs.append(id)
        if shouldFail { throw Failure.unavailable }
        return content
    }

    func fail() { shouldFail = true }
}

@Suite("Large preview loading — lazy and privacy-safe")
struct ClipPreviewLoaderTests {
    private let loader = ClipPreviewLoader()

    @Test("Sensitive metadata never loads the durable payload")
    func sensitiveClipsFailClosedBeforeLoading() async {
        let item = ClipItem(
            kind: .secret, preview: "•••• 1234", contentHash: "secret", isSensitive: true)
        let probe = PreviewContentProbe(content: .text("must never load"))

        let payload = await loader.load(item) { id in try await probe.load(id) }

        #expect(payload == .masked("•••• 1234"))
        #expect(await probe.requestedIDs.isEmpty)
    }

    @Test("Intrinsically masked kinds fail closed even if metadata is inconsistent")
    func maskedKindFailsClosed() async {
        let item = ClipItem(kind: .jwt, preview: "•••• token", contentHash: "jwt")
        let probe = PreviewContentProbe(content: .text("header.payload.signature"))

        let payload = await loader.load(item) { id in try await probe.load(id) }

        #expect(payload == .masked("•••• token"))
        #expect(await probe.requestedIDs.isEmpty)
    }

    @Test("Explicit previews preserve each non-sensitive content representation")
    func contentRepresentationsArePreserved() async {
        let item = ClipItem(preview: "body", contentHash: "body")
        let textProbe = PreviewContentProbe(content: .text("full\nbody"))
        let binaryProbe = PreviewContentProbe(
            content: .binary(data: Data([1, 2, 3]), typeIdentifier: "public.data"))
        let filesProbe = PreviewContentProbe(
            content: .fileReferences(["/tmp/one.txt", "/tmp/two.txt"]))

        let text = await loader.load(item) { id in try await textProbe.load(id) }
        let binary = await loader.load(item) { id in try await binaryProbe.load(id) }
        let files = await loader.load(item) { id in try await filesProbe.load(id) }

        #expect(text == .text("full\nbody"))
        #expect(binary == .binary(data: Data([1, 2, 3]), typeIdentifier: "public.data"))
        #expect(files == .fileReferences(["/tmp/one.txt", "/tmp/two.txt"]))
        #expect(await textProbe.requestedIDs == [item.id])
        #expect(await binaryProbe.requestedIDs == [item.id])
        #expect(await filesProbe.requestedIDs == [item.id])
    }

    @Test("Missing or failed content becomes an unavailable preview")
    func unavailableContentFailsSoftly() async {
        let item = ClipItem(preview: "metadata", contentHash: "missing")
        let missingProbe = PreviewContentProbe(content: nil)
        let failingProbe = PreviewContentProbe(content: .text("ignored"))
        await failingProbe.fail()

        let missing = await loader.load(item) { id in try await missingProbe.load(id) }
        let failed = await loader.load(item) { id in try await failingProbe.load(id) }

        #expect(missing == .unavailable)
        #expect(failed == .unavailable)
    }
}
