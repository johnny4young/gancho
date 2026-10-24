import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor InvalidatedPreviewRead {
    private var result: CheckedContinuation<ClipContent?, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func load() async -> ClipContent? {
        await withCheckedContinuation { continuation in
            result = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() {
        result?.resume(returning: .text("synthetic old body"))
        result = nil
    }
}

@MainActor @Suite("Panel preview invalidation", .timeLimit(.minutes(1)))
struct PanelPreviewInvalidationTests {
    @Test("A mutation invalidates an already-started preview read")
    func invalidationDropsPendingRead() async {
        let item = ClipItem(preview: "synthetic metadata", contentHash: "synthetic-preview")
        let preview = PanelPreviewModel()
        let suspended = InvalidatedPreviewRead()
        let task = Task { await preview.load(item) { _ in await suspended.load() } }
        await suspended.waitUntilStarted()
        preview.invalidate()
        await suspended.finish()
        await task.value
        #expect(preview.presentation(for: item).text == item.preview)
        #expect(!preview.presentation(for: item).isTextEditable)
    }

    @Test("An unchanged selection gets a new preview request after a store mutation")
    func unchangedSelectionCanReload() async {
        let item = ClipItem(preview: "synthetic metadata", contentHash: "synthetic-preview")
        let oldRequest = PanelPreviewRequestKey(item: item, storeRevision: 0)
        let newRequest = PanelPreviewRequestKey(item: item, storeRevision: 1)
        #expect(oldRequest != newRequest)
        let preview = PanelPreviewModel()
        await preview.load(item) { _ in .text("synthetic current body") }
        preview.invalidate()
        #expect(preview.presentation(for: item).text == item.preview)
        await preview.load(item) { _ in .text("synthetic current body") }
        #expect(preview.presentation(for: item).text == "synthetic current body")
        #expect(preview.presentation(for: item).isTextEditable)
    }
}
