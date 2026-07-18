import Foundation
import GanchoAppCore
import GanchoKit
import Testing

@Suite("Clip migration coordinator")
struct ClipMigrationCoordinatorTests {
    @Test("Dry run reports destination and source duplicates without writing")
    func previewCounts() async throws {
        let store = InMemoryClipboardStore()
        let existing = ClipItem(
            preview: "existing",
            contentHash: ClipItem.hash(of: "existing", kind: .text))
        _ = try await store.insert(existing, content: .text("existing"))
        let document = ClipImporter.Document(
            candidates: [
                .init(text: "existing"),
                .init(text: "fresh", title: "Fresh title", isPinned: true),
                .init(text: "fresh"),
                .init(text: "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456")
            ],
            unsupportedCount: 2)

        let plan = try await ClipMigrationCoordinator().preview(
            document,
            sourceName: "migration.csv",
            configuration: .init(sensitiveLifetime: 60),
            store: store)

        #expect(
            plan.preview
                == .init(
                    sourceName: "migration.csv",
                    totalCount: 6,
                    readyCount: 2,
                    duplicateCount: 2,
                    unsupportedCount: 2,
                    protectedCount: 1))
        #expect(try await store.count() == 1)
        #expect(try await store.itemForTest(existing.id)?.lastUsedAt == nil)
    }

    @Test("Approved import is atomic, syncs new rows, and applies secret policy")
    func execute() async throws {
        let store = InMemoryClipboardStore()
        let sync = ImportSyncSpy()
        let document = ClipImporter.Document(candidates: [
            .init(text: "ordinary text", title: "Reference", isPinned: true),
            .init(text: "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456", isPinned: true)
        ])
        let coordinator = ClipMigrationCoordinator()
        let plan = try await coordinator.preview(
            document,
            sourceName: "migration.csv",
            configuration: .init(sensitiveLifetime: 90),
            store: store)

        let summary = try await coordinator.execute(plan, store: store, syncEngine: sync)

        #expect(
            summary
                == .init(
                    importedCount: 2,
                    skippedDuplicates: 0,
                    unsupportedCount: 0,
                    protectedCount: 1))
        #expect(await sync.enqueuedCount == 2)
        let items = try await store.items()
        let ordinary = try #require(items.first { !$0.isSensitive })
        #expect(ordinary.title == "Reference")
        #expect(ordinary.isPinned)
        let secret = try #require(items.first { $0.isSensitive })
        #expect(secret.kind == .secret)
        #expect(!secret.isPinned)
        #expect(secret.title.isEmpty)
        #expect(secret.expiresAt != nil)
        #expect(!secret.preview.contains("sk-"))
    }

    @Test("Protected accounting follows the duplicate row that is actually approved")
    func protectedDuplicateAccounting() async throws {
        let store = InMemoryClipboardStore()
        let coordinator = ClipMigrationCoordinator()
        let document = ClipImporter.Document(candidates: [
            .init(text: "shared text", title: "Reference", isPinned: true),
            .init(
                text: "shared text",
                title: "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456",
                isPinned: true)
        ])

        let plan = try await coordinator.preview(
            document,
            sourceName: "migration.csv",
            configuration: .init(sensitiveLifetime: 90),
            store: store)

        #expect(plan.preview.readyCount == 1)
        #expect(plan.preview.duplicateCount == 1)
        #expect(plan.preview.protectedCount == 0)

        let summary = try await coordinator.execute(
            plan,
            store: store,
            syncEngine: ImportSyncSpy())
        #expect(summary.protectedCount == 0)
        let imported = try #require(await store.items().first)
        #expect(imported.title == "Reference")
        #expect(imported.isPinned)
        #expect(!imported.isSensitive)
    }

    @Test("A secret in source metadata does not shorten ordinary content retention")
    func sensitiveTitleProtectsMetadataOnly() async throws {
        let store = InMemoryClipboardStore()
        let coordinator = ClipMigrationCoordinator()
        let document = ClipImporter.Document(candidates: [
            .init(
                text: "ordinary text",
                title: "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456",
                isPinned: true)
        ])

        let plan = try await coordinator.preview(
            document,
            sourceName: "migration.csv",
            configuration: .init(sensitiveLifetime: 90),
            store: store)

        #expect(plan.preview.protectedCount == 1)
        let summary = try await coordinator.execute(
            plan,
            store: store,
            syncEngine: ImportSyncSpy())
        #expect(summary.protectedCount == 1)
        let imported = try #require(await store.items().first)
        #expect(imported.title.isEmpty)
        #expect(!imported.isPinned)
        #expect(!imported.isSensitive)
        #expect(imported.kind == .text)
        #expect(imported.expiresAt == nil)
        #expect(imported.preview == "ordinary text")
    }

    @Test("A cancelled batch leaves the destination unchanged")
    func cancellationRollsBack() async throws {
        let store = InMemoryClipboardStore()
        let gate = MigrationCancellationGate()
        let record = ClipImportBatchItem(
            item: ClipItem(
                preview: "candidate",
                contentHash: ClipItem.hash(of: "candidate", kind: .text)),
            text: "candidate")
        let task = Task {
            await gate.wait()
            return try await store.importTextBatch([record])
        }
        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(try await store.count() == 0)
    }

    @Test("Cancelling a CSV load stops before decoding")
    func csvLoadCancellation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancelled-\(UUID().uuidString).csv")
        try Data("text\nnot imported".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = MigrationCancellationGate()
        let task = Task {
            await gate.wait()
            return try await ClipMigrationCoordinator().load(.csv(url))
        }
        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}

private actor ImportSyncSpy: SyncEngine {
    private(set) var enqueuedCount = 0

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueuedCount += items.count }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

private actor MigrationCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        blockedContinuation?.resume()
        blockedContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { blockedContinuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

extension InMemoryClipboardStore {
    fileprivate func itemForTest(_ id: UUID) async throws -> ClipItem? {
        try await items().first { $0.id == id }
    }
}
