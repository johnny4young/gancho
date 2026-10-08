import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

private struct RaceEmbedder: TextEmbedding {
    let dimension = 2
    func vector(for text: String) throws -> [Float] { [1, 0] }
}

/// Holds the exact await between computation and guarded persistence. No timing
/// assumptions or on-device model assets are involved in either caller test.
private actor EmbeddingRaceStore: ClipEnriching, EmbeddingRefreshSource,
    ContentBoundEmbeddingStoring
{
    let id = UUID()
    private var text = "original"
    private var pendingWrite: CheckedContinuation<Void, Never>?
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var saved = false
    private(set) var unsafeWrites = 0
    private(set) var observedText: String?

    func content(for id: UUID) async throws -> ClipContent? { .text(text) }
    func staleEmbeddingClipIDs(limit: Int) async throws -> [UUID] { saved ? [] : [id] }
    func updateTitle(id: UUID, title: String) async throws {}
    func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool { false }
    func attachExtractedText(id: UUID, text: String) async throws {}
    func updateClipText(id: UUID, text: String) async throws { self.text = text }
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        unsafeWrites += 1
        await pauseWrite()
        saved = true
    }

    func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool {
        observedText = expectedText
        await pauseWrite()
        guard expectedText == text else { return false }
        saved = true
        return true
    }

    private func pauseWrite() async {
        await withCheckedContinuation { continuation in
            pendingWrite = continuation
            for waiter in writeWaiters { waiter.resume() }
            writeWaiters.removeAll()
        }
    }

    func waitUntilWriteIsPending() async {
        if pendingWrite != nil { return }
        await withCheckedContinuation { writeWaiters.append($0) }
    }

    func resumeWrite(withCurrentText text: String) {
        self.text = text
        let continuation = pendingWrite
        pendingWrite = nil
        continuation?.resume()
    }
}

@Suite("Background embedding write races", .timeLimit(.minutes(1)))
struct EmbeddingWriteRaceTests {
    @Test func captureEnrichmentRejectsAChangedBody() async {
        let store = EmbeddingRaceStore()
        let item = ClipItem(id: store.id, preview: "original")
        let plan = EnrichmentPlan(
            content: .text(hasTitle: true), isSensitive: false, isPro: true,
            preferences: IntelligencePreferences())
        let service = EnrichmentService(makeEmbedder: { RaceEmbedder() })
        let task = Task {
            await service.enrich(
                item, content: .text("original"), plan: plan, writeTitle: false, store: store,
                onTitleWritten: {})
        }
        await store.waitUntilWriteIsPending()
        await store.resumeWrite(withCurrentText: "edited")
        await task.value
        #expect(await store.observedText == "original")
        #expect(await store.unsafeWrites == 0)
        #expect(await store.saved == false)
    }

    @Test func refreshRejectsChangedBodyWithoutReportingProgressOrSpinning() async {
        let store = EmbeddingRaceStore()
        let service = EmbeddingRefreshService(
            makeEmbedder: { RaceEmbedder() }, isEnvironmentSuitable: { true })
        let task = Task { await service.run(store: store) }
        await store.waitUntilWriteIsPending()
        await store.resumeWrite(withCurrentText: "edited")
        #expect(await task.value == 0)
        #expect(await store.observedText == "original")
        #expect(await store.unsafeWrites == 0)
        #expect(await store.saved == false)
    }

    @Test func refreshAcceptsUnchangedBodyAsPositiveControl() async {
        let store = EmbeddingRaceStore()
        let service = EmbeddingRefreshService(
            makeEmbedder: { RaceEmbedder() }, isEnvironmentSuitable: { true })
        let task = Task { await service.run(store: store) }
        await store.waitUntilWriteIsPending()
        await store.resumeWrite(withCurrentText: "original")
        #expect(await task.value == 1)
        #expect(await store.saved)
        #expect(await store.unsafeWrites == 0)
    }
}
