import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A recording fake enrichment store: it counts every write the service makes
/// and (via `noteTitleCallback`) every time the `onTitleWritten` hook fires, so
/// a test can assert not just that nothing wrote but exactly WHICH stages ran —
/// what makes these checks non-vacuous on CI. There the tiered annotator
/// degrades to the deterministic `HeuristicAnnotator` (so the title stage still
/// succeeds), while the embedder reports no on-device assets (so the embedding
/// stage writes nothing); the assertions below are chosen to hold either way.
private actor FakeEnriching: ClipEnriching {
    private(set) var updateTitleCalls = 0
    var allowsGeneratedTitleWrite = true
    private(set) var attachExtractedTextCalls = 0
    private(set) var updateClipTextCalls = 0
    private(set) var saveEmbeddingCalls = 0
    private(set) var titleCallbackCalls = 0

    // The `ClipEnriching` requirements, exact signatures from ClientContract.
    func updateTitle(id: UUID, title: String) async throws { updateTitleCalls += 1 }
    func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool {
        updateTitleCalls += 1
        return allowsGeneratedTitleWrite
    }
    func attachExtractedText(id: UUID, text: String) async throws { attachExtractedTextCalls += 1 }
    func updateClipText(id: UUID, text: String) async throws { updateClipTextCalls += 1 }
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws { saveEmbeddingCalls += 1 }

    /// Records an `onTitleWritten` invocation so the callback is observable.
    func noteTitleCallback() { titleCallbackCalls += 1 }

    func rejectGeneratedTitles() { allowsGeneratedTitleWrite = false }
}

@Suite("Enrichment service — plan and writeTitle gating")
struct EnrichmentServiceTests {
    private let item = ClipItem(title: "clip")

    /// A plan with no enrichable payload runs nothing; a text plan runs title +
    /// embedding — used to prove `writeTitle` overrides `plan.runs(.title)`.
    private func plan(_ content: EnrichableContent) -> EnrichmentPlan {
        EnrichmentPlan(
            content: content, isSensitive: false, isPro: true,
            preferences: IntelligencePreferences())
    }

    @Test("Empty plan with writeTitle:false makes no writes and skips the callback")
    func emptyPlanWritesNothing() async {
        let store = FakeEnriching()

        await EnrichmentService().enrich(
            item, content: .text("hello world"), plan: plan(.other),
            writeTitle: false, store: store
        ) {
            await store.noteTitleCallback()
        }

        #expect(await store.attachExtractedTextCalls == 0)
        #expect(await store.updateTitleCalls == 0)
        #expect(await store.updateClipTextCalls == 0)
        #expect(await store.saveEmbeddingCalls == 0)
        // The hook must fire ONLY after a title write; with none, it stays silent.
        #expect(await store.titleCallbackCalls == 0)
    }

    @Test("writeTitle:false suppresses the title even when the plan would run it")
    func writeTitleFalseSuppressesTitle() async {
        // This plan DOES include the title stage (text, no title, Pro), yet the
        // caller passes writeTitle:false — the service must honor the parameter,
        // not the plan, so no title is written and the hook never fires.
        let store = FakeEnriching()

        await EnrichmentService().enrich(
            item, content: .text("hello world"), plan: plan(.text(hasTitle: false)),
            writeTitle: false, store: store
        ) {
            await store.noteTitleCallback()
        }

        #expect(await store.updateTitleCalls == 0)
        #expect(await store.titleCallbackCalls == 0)
    }

    @Test("writeTitle:true on text writes exactly one title and fires the callback once")
    func writeTitleTrueWritesTitleAndFiresHook() async {
        // The tiered annotator falls back to the deterministic HeuristicAnnotator
        // on CI, so the title stage succeeds without on-device assets. An empty
        // plan isolates the title stage: OCR and embedding never run.
        let store = FakeEnriching()

        await EnrichmentService().enrich(
            item, content: .text("hello world"), plan: plan(.other),
            writeTitle: true, store: store
        ) {
            await store.noteTitleCallback()
        }

        #expect(await store.updateTitleCalls == 1)
        #expect(await store.titleCallbackCalls == 1)
        #expect(await store.attachExtractedTextCalls == 0)
        #expect(await store.saveEmbeddingCalls == 0)
    }

    @Test("A manual title saved during enrichment wins the guarded write race")
    func manualTitleWinsEnrichmentRace() async {
        let store = FakeEnriching()
        await store.rejectGeneratedTitles()

        await EnrichmentService().enrich(
            item, content: .text("hello world"), plan: plan(.other),
            writeTitle: true, store: store
        ) {
            await store.noteTitleCallback()
        }

        #expect(await store.updateTitleCalls == 1)
        #expect(await store.titleCallbackCalls == 0)
    }

    @Test("writeTitle:true with non-text content writes no title and skips the callback")
    func writeTitleTrueNonTextSkipsTitle() async {
        // The title stage is gated on `case .text` content; a binary payload must
        // not reach the annotator, so nothing is written and the hook stays silent.
        let store = FakeEnriching()
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        await EnrichmentService().enrich(
            item, content: .binary(data: png, typeIdentifier: "public.png"),
            plan: plan(.other), writeTitle: true, store: store
        ) {
            await store.noteTitleCallback()
        }

        #expect(await store.updateTitleCalls == 0)
        #expect(await store.titleCallbackCalls == 0)
    }
}
