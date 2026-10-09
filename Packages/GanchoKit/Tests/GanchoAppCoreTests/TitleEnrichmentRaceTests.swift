import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor PausingTitleAnnotator: ClipAnnotating {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var source: String?

    func annotate(_ text: String) async throws -> ClipAnnotation {
        source = text
        await withCheckedContinuation { continuation in
            pending = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
        return ClipAnnotation(title: "Original topic", kind: .text)
    }

    func waitUntilAnnotationIsPending() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

private actor TitleRaceStore: ClipEnriching, ContentBoundTitleStoring {
    private var text = "original"
    private(set) var title = ""
    private(set) var callbacks = 0
    private(set) var unsafeWrites = 0

    func updateTitle(id: UUID, title: String) async throws { self.title = title }
    func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool {
        unsafeWrites += 1
        guard self.title.isEmpty else { return false }
        self.title = title
        return true
    }
    func updateTitleIfEmptyAndCurrent(
        id: UUID, title: String, expectedText: String
    ) async throws -> Bool {
        guard self.title.isEmpty, text == expectedText else { return false }
        self.title = title
        return true
    }
    func attachExtractedText(id: UUID, text: String) async throws {}
    func updateClipText(id: UUID, text: String) async throws { self.text = text }
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {}
    func noteCallback() { callbacks += 1 }
}

@Suite("Title enrichment body races")
struct TitleEnrichmentRaceTests {
    @Test(arguments: [false, true])
    func titleCommitsOnlyForTheStillCurrentBody(changeBody: Bool) async throws {
        let store = TitleRaceStore()
        let annotator = PausingTitleAnnotator()
        let item = ClipItem(preview: "original")
        let service = EnrichmentService(makeEmbedder: { nil }, annotator: annotator)
        let plan = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: false, isPro: true,
            preferences: IntelligencePreferences(semanticSearch: false))
        let task = Task {
            await service.enrich(
                item, content: .text("original"), plan: plan, writeTitle: true, store: store,
                onTitleWritten: { await store.noteCallback() })
        }
        await annotator.waitUntilAnnotationIsPending()
        if changeBody { try await store.updateClipText(id: item.id, text: "edited") }
        await annotator.finish()
        await task.value

        #expect(await annotator.source == "original")
        #expect(await store.title == (changeBody ? "" : "Original topic"))
        #expect(await store.callbacks == (changeBody ? 0 : 1))
        #expect(await store.unsafeWrites == 0)
    }
}
