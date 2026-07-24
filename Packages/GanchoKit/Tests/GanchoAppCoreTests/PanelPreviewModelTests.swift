import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor PanelPreviewContentProbe {
    private(set) var requestedIDs: [UUID] = []
    var content: ClipContent?

    init(content: ClipContent?) {
        self.content = content
    }

    func load(_ id: UUID) -> ClipContent? {
        requestedIDs.append(id)
        return content
    }
}

private actor SuspendedPanelPreviewContent {
    private var continuation: CheckedContinuation<ClipContent?, Never>?
    private var started = false

    func load() async -> ClipContent? {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func resume(returning content: ClipContent?) {
        continuation?.resume(returning: content)
        continuation = nil
    }
}

@MainActor
@Suite("Panel preview model")
struct PanelPreviewModelTests {
    @Test("Sensitive clips stay masked without reading durable content")
    func sensitiveClipFailsClosed() async {
        let item = ClipItem(
            kind: .secret,
            preview: "must not render",
            contentHash: "secret",
            isSensitive: true)
        let probe = PanelPreviewContentProbe(content: .text("must not load"))
        let model = PanelPreviewModel()

        await model.load(item) { id in await probe.load(id) }

        let presentation = model.presentation(for: item)
        #expect(presentation.text == ClipSafePresentation.masked)
        #expect(!presentation.isTextEditable)
        #expect(await probe.requestedIDs.isEmpty)
    }

    @Test(
        "Image and file selections use cheap metadata without reading blobs",
        arguments: [
            ClipContentKind.image,
            .fileReference
        ])
    func binarySelectionsSkipContent(kind: ClipContentKind) async {
        let item = ClipItem(kind: kind, preview: "metadata", contentHash: kind.rawValue)
        let probe = PanelPreviewContentProbe(content: .text("unexpected"))
        let model = PanelPreviewModel()

        await model.load(item) { id in await probe.load(id) }

        #expect(model.presentation(for: item).text == "metadata")
        #expect(await probe.requestedIDs.isEmpty)
    }

    @Test("Loaded text becomes editable only for an eligible clip kind")
    func textEditability() async {
        let editable = ClipItem(kind: .text, preview: "preview", contentHash: "text")
        let structured = ClipItem(kind: .color, preview: "#FF0000", contentHash: "color")
        let model = PanelPreviewModel()

        await model.load(editable) { _ in .text("full text") }
        let editablePresentation = model.presentation(for: editable)
        #expect(editablePresentation.text == "full text")
        #expect(editablePresentation.isTextEditable)

        await model.load(structured) { _ in .text("#FF0000") }
        let structuredPresentation = model.presentation(for: structured)
        #expect(structuredPresentation.text == "#FF0000")
        #expect(!structuredPresentation.isTextEditable)
    }

    @Test("Unavailable content keeps the metadata fallback read-only")
    func unavailableContentFallsBack() async {
        let item = ClipItem(kind: .text, preview: "metadata", contentHash: "missing")
        let model = PanelPreviewModel()

        await model.load(item) { _ in nil }

        let presentation = model.presentation(for: item)
        #expect(presentation.text == "metadata")
        #expect(!presentation.isTextEditable)
    }

    @Test("A new selection is metadata-only before its debounced load begins")
    func selectionMismatchNeverShowsPreviousText() async {
        let first = ClipItem(kind: .text, preview: "first preview", contentHash: "first")
        let second = ClipItem(kind: .text, preview: "second preview", contentHash: "second")
        let model = PanelPreviewModel()

        await model.load(first) { _ in .text("first full text") }

        let presentation = model.presentation(for: second)
        #expect(presentation.text == "second preview")
        #expect(!presentation.isTextEditable)
    }

    @Test("A stale load cannot overwrite the newly selected clip")
    func staleResultIsRejected() async {
        let first = ClipItem(kind: .text, preview: "first preview", contentHash: "first")
        let second = ClipItem(kind: .text, preview: "second preview", contentHash: "second")
        let suspended = SuspendedPanelPreviewContent()
        let model = PanelPreviewModel()

        let firstTask = Task { @MainActor in
            await model.load(first) { _ in await suspended.load() }
        }
        await suspended.waitUntilStarted()

        await model.load(second) { _ in .text("second full text") }
        await suspended.resume(returning: .text("stale first text"))
        await firstTask.value

        #expect(model.presentation(for: second).text == "second full text")
        #expect(model.presentation(for: first).text == "first preview")
    }

    @Test("A cancelled load leaves its metadata fallback intact")
    func cancelledResultIsRejected() async {
        let item = ClipItem(kind: .text, preview: "safe preview", contentHash: "cancelled")
        let suspended = SuspendedPanelPreviewContent()
        let model = PanelPreviewModel()

        let task = Task { @MainActor in
            await model.load(item) { _ in await suspended.load() }
        }
        await suspended.waitUntilStarted()
        task.cancel()
        await suspended.resume(returning: .text("late full text"))
        await task.value

        let presentation = model.presentation(for: item)
        #expect(presentation.text == "safe preview")
        #expect(!presentation.isTextEditable)
    }
}
