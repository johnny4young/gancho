import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Scriptable refresh source: `stale` drains as saves land, exactly like the
/// real store (a refreshed row stops being stale), so batch-loop convergence
/// is exercised honestly.
private actor FakeRefreshStore: EmbeddingRefreshSource, ContentBoundEmbeddingStoring {
    private var stale: [UUID]
    private let texts: [UUID: String]
    private(set) var saved: [UUID: [Float]] = [:]

    init(stale: [UUID], texts: [UUID: String]) {
        self.stale = stale
        self.texts = texts
    }

    func staleEmbeddingClipIDs(limit: Int) async throws -> [UUID] {
        Array(stale.prefix(limit))
    }
    func content(for id: UUID) async throws -> ClipContent? {
        texts[id].map(ClipContent.text)
    }
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        saved[clipID] = vector
        stale.removeAll { $0 == clipID }
    }
    func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool {
        guard texts[clipID] == expectedText else { return false }
        try await saveEmbedding(clipID: clipID, vector: vector)
        return true
    }
}

/// Clips with no vector, in rowid order like the real store; a save removes one.
private actor FakeBackfillStore: EmbeddingBackfillSource, ContentBoundEmbeddingStoring {
    private var missing: [UnembeddedClip]
    private let texts: [UUID: String]
    private(set) var saved: Set<UUID> = []

    init(missing: [UnembeddedClip], texts: [UUID: String]) {
        self.missing = missing
        self.texts = texts
    }

    func unembeddedClips(limit: Int, beforeRowID: Int64?) async throws -> [UnembeddedClip] {
        Array(missing.filter { $0.rowID < (beforeRowID ?? .max) }.prefix(limit))
    }
    func staleEmbeddingClipIDs(limit: Int) async throws -> [UUID] { [] }
    func content(for id: UUID) async throws -> ClipContent? { texts[id].map(ClipContent.text) }
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        saved.insert(clipID)
        missing.removeAll { $0.id == clipID }
    }
    func saveEmbeddingIfCurrent(
        clipID: UUID, vector: [Float], expectedText: String
    ) async throws -> Bool {
        guard texts[clipID] == expectedText else { return false }
        try await saveEmbedding(clipID: clipID, vector: vector)
        return true
    }
}

/// Deterministic embedder — no model assets, no Accelerate.
private struct FixedEmbedder: TextEmbedding {
    let dimension = 3
    func vector(for text: String) throws -> [Float] { [Float(text.count), 1, 0] }
}

private struct FailingEmbedder: TextEmbedding {
    let dimension = 3
    func vector(for text: String) throws -> [Float] { throw EmbeddingError.noVectors }
}

@Suite("Embedding refresh — background re-embed pass")
struct EmbeddingRefreshServiceTests {
    private func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    @Test("Backfill embeds every clip without a vector and passes over one it can't read")
    func backfill() async throws {
        let clips = (0..<40).map { UnembeddedClip(id: UUID(), rowID: Int64(1_000 - $0)) }
        var texts = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, "text \($0.rowID)") })
        // No readable text: a pass that stopped here would never reach the rest.
        texts[clips[0].id] = nil
        let store = FakeBackfillStore(missing: clips, texts: texts)
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { true })
        #expect(await service.backfill(store: store) == clips.count - 1)
        #expect(await store.saved == Set(clips.dropFirst().map(\.id)))
        #expect(await service.backfill(store: store) == 0, "nothing left but the unreadable one")
    }

    @Test("Backfill stops when the environment turns hostile")
    func backfillRespectsEnvironment() async throws {
        let clips = (0..<5).map { UnembeddedClip(id: UUID(), rowID: Int64(10 - $0)) }
        let store = FakeBackfillStore(
            missing: clips, texts: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, "t") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { false })
        #expect(await service.backfill(store: store) == 0)
    }

    @Test("Refreshes every stale clip across batch boundaries")
    func refreshesAllBatches() async throws {
        // 40 stale ids forces three 16-row batches through the loop.
        let stale = ids(40)
        let store = FakeRefreshStore(
            stale: stale,
            texts: Dictionary(uniqueKeysWithValues: stale.map { ($0, "clip text") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { true })

        let refreshed = await service.run(store: store)
        #expect(refreshed == 40)
        #expect(await store.saved.count == 40)
        #expect(try await store.staleEmbeddingClipIDs(limit: 100).isEmpty)
    }

    @Test("Rows the embedder cannot refresh stop the pass instead of spinning it")
    func zeroProgressBatchTerminates() async throws {
        let stale = ids(3)
        let store = FakeRefreshStore(
            stale: stale,
            texts: Dictionary(uniqueKeysWithValues: stale.map { ($0, "clip text") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { FailingEmbedder() }, isEnvironmentSuitable: { true })

        // Every row fails → the pass must terminate with nothing refreshed
        // (this test finishing at all proves the loop cannot spin forever).
        let refreshed = await service.run(store: store)
        #expect(refreshed == 0)
        #expect(await store.saved.isEmpty)
    }

    @Test("Rows without text are skipped; the rest still converge")
    func skipsMissingContent() async throws {
        let stale = ids(3)
        // Only the middle id has text — the other two can never refresh.
        let store = FakeRefreshStore(stale: stale, texts: [stale[1]: "hello"])
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { true })

        let refreshed = await service.run(store: store)
        #expect(refreshed == 1)
        #expect(await store.saved.keys.contains(stale[1]))
    }

    @Test("A hostile environment (thermal/Low Power) refreshes nothing")
    func hostileEnvironmentStopsBeforeWork() async throws {
        let stale = ids(2)
        let store = FakeRefreshStore(
            stale: stale,
            texts: Dictionary(uniqueKeysWithValues: stale.map { ($0, "clip text") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { false })

        let refreshed = await service.run(store: store)
        #expect(refreshed == 0)
        #expect(await store.saved.isEmpty)
    }

    @Test("Missing model assets skip the pass entirely")
    func missingAssetsSkip() async throws {
        let stale = ids(2)
        let store = FakeRefreshStore(
            stale: stale,
            texts: Dictionary(uniqueKeysWithValues: stale.map { ($0, "clip text") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { nil }, isEnvironmentSuitable: { true })

        let refreshed = await service.run(store: store)
        #expect(refreshed == 0)
        #expect(await store.saved.isEmpty)
    }

    @Test("Cancellation is honored between items and progress survives")
    func cancellationStopsMidPass() async throws {
        let stale = ids(30)
        let store = FakeRefreshStore(
            stale: stale,
            texts: Dictionary(uniqueKeysWithValues: stale.map { ($0, "clip text") }))
        let service = EmbeddingRefreshService(
            makeEmbedder: { FixedEmbedder() }, isEnvironmentSuitable: { true })

        let task = Task { await service.run(store: store) }
        task.cancel()
        let refreshed = await task.value

        // However far it got, the invariant holds: refreshed rows left the
        // stale queue, unrefreshed rows are still there for the next launch.
        let remaining = try await store.staleEmbeddingClipIDs(limit: 100).count
        #expect(refreshed + remaining == 30)
    }
}
