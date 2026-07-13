import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum IngestionStoreError: Error {
    case unavailable
}

private actor IngestionStoreSpy: ClipIngesting, ClipEnriching {
    var returnedItem: ClipItem?
    var failsInsert = false
    private(set) var insertedItem: ClipItem?
    private(set) var insertedContent: ClipContent?
    private(set) var titleWrites = 0
    private(set) var extractedTextWrites = 0
    private(set) var embeddingWrites = 0

    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        guard !failsInsert else { throw IngestionStoreError.unavailable }
        insertedItem = item
        insertedContent = content
        return returnedItem ?? item
    }

    func updateTitle(id: UUID, title: String) async throws { titleWrites += 1 }
    func attachExtractedText(id: UUID, text: String) async throws {
        extractedTextWrites += 1
    }
    func updateClipText(id: UUID, text: String) async throws {}
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        embeddingWrites += 1
    }
}

private actor IngestionSyncSpy: SyncEngine {
    private(set) var enqueuedItems: [[ClipItem]] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueuedItems.append(items) }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

@Suite("ClipIngestionCoordinator — shared capture workflow")
struct ClipIngestionCoordinatorTests {
    private let coordinator = ClipIngestionCoordinator()

    private func configuration(
        tier: UserTier = .free,
        precomputedKind: ClipContentKind? = nil,
        allowsFreeTitle: Bool = false,
        intelligence: IntelligencePreferences = .init()
    ) -> ClipIngestionCoordinator.Configuration {
        .init(
            sensitiveLifetime: 600,
            precomputedKind: precomputedKind,
            tier: tier,
            intelligence: intelligence,
            allowsFreeTitle: allowsFreeTitle)
    }

    @Test("New capture maps, persists, enqueues, and exposes only a size metric")
    func newCapture() async throws {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()
        let raw = "https://example.com/path?utm_source=mail&q=1"

        let outcome = try await coordinator.ingest(
            PasteboardCapture(text: raw),
            configuration: configuration(allowsFreeTitle: true),
            store: store,
            syncEngine: sync)

        #expect(outcome.isNew)
        #expect(outcome.item.kind == .url)
        #expect(outcome.content == .text("https://example.com/path?q=1"))
        #expect(outcome.contentLength == "https://example.com/path?q=1".count)
        #expect(outcome.enrichment.writesTitle)
        #expect(outcome.enrichment.usesFreeTitle)
        #expect(await store.insertedContent == outcome.content)
        #expect(await sync.enqueuedItems == [[outcome.item]])
    }

    @Test("Preclassified shared-inbox kind overrides local reclassification")
    func precomputedKind() async throws {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()

        let outcome = try await coordinator.ingest(
            PasteboardCapture(text: "plain words"),
            configuration: configuration(precomputedKind: .code),
            store: store,
            syncEngine: sync)

        #expect(outcome.item.kind == .code)
        #expect(outcome.content == .text("plain words"))
    }

    @Test("Deduplication uses and enqueues the durable row, not the proposed ID")
    func deduplicatedCapture() async throws {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()
        var existing = ClipItem(kind: .text, preview: "existing", contentHash: "same")
        existing.title = "Existing title"
        await store.setReturnedItem(existing)
        let preferences = IntelligencePreferences(
            intelligentTitles: true,
            semanticSearch: true,
            searchableScreenshots: false)

        let outcome = try await coordinator.ingest(
            PasteboardCapture(text: "same"),
            configuration: configuration(tier: .pro, intelligence: preferences),
            store: store,
            syncEngine: sync)

        #expect(!outcome.isNew)
        #expect(outcome.item.id == existing.id)
        #expect(!outcome.enrichment.plan.runs(.title))
        #expect(outcome.enrichment.plan.runs(.embedding))
        #expect(await sync.enqueuedItems == [[existing]])
    }

    @Test("A failed write propagates and never enqueues a phantom clip")
    func failedWrite() async {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()
        await store.setFailsInsert(true)

        await #expect(throws: IngestionStoreError.self) {
            _ = try await coordinator.ingest(
                PasteboardCapture(text: "not stored"),
                configuration: configuration(),
                store: store,
                syncEngine: sync)
        }
        #expect(await sync.enqueuedItems.isEmpty)
    }

    @Test("Sensitive captures veto Pro and free-title enrichment")
    func sensitiveVeto() async throws {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()
        let token = "ghp_abcdefghijklmno" + "pqrstuvwxyz0123456789"

        let outcome = try await coordinator.ingest(
            PasteboardCapture(text: token),
            configuration: configuration(tier: .pro, allowsFreeTitle: true),
            store: store,
            syncEngine: sync)

        #expect(outcome.item.isSensitive)
        #expect(outcome.enrichment.isEmpty)
        #expect(!outcome.enrichment.usesFreeTitle)
    }

    @Test("Enrichment completion enqueues once more only when sync is enabled")
    func enrichmentSync() async throws {
        let store = IngestionStoreSpy()
        let sync = IngestionSyncSpy()
        let preferences = IntelligencePreferences(
            intelligentTitles: false,
            semanticSearch: false,
            searchableScreenshots: true)
        let outcome = try await coordinator.ingest(
            PasteboardCapture(
                payload: .image(data: Data([0x00]), typeIdentifier: "public.png")),
            configuration: configuration(tier: .pro, intelligence: preferences),
            store: store,
            syncEngine: sync)

        await coordinator.enrich(
            outcome,
            store: store,
            syncEngine: nil,
            onTitleWritten: {})
        #expect(await sync.enqueuedItems.count == 1)

        await coordinator.enrich(
            outcome,
            store: store,
            syncEngine: sync,
            onTitleWritten: {})

        #expect(await sync.enqueuedItems.count == 2)
        #expect(await sync.enqueuedItems.last == [outcome.item])
    }
}

extension IngestionStoreSpy {
    fileprivate func setReturnedItem(_ item: ClipItem) { returnedItem = item }
    fileprivate func setFailsInsert(_ fails: Bool) { failsInsert = fails }
}
