import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor ContextDeliveryReader: ClipReading {
    enum Mutation: Sendable { case none, removed, protected, expired, edited }
    private var current: ClipItem? = ClipItem(contentHash: "context-synthetic")
    let mutation: Mutation
    let beforeContent: @Sendable () async -> Void

    init(mutation: Mutation = .none, beforeContent: @escaping @Sendable () async -> Void = {}) {
        self.mutation = mutation
        self.beforeContent = beforeContent
    }
    func items(ids: [UUID]) async throws -> [ClipItem] {
        current.map { ids.contains($0.id) ? [$0] : [] } ?? []
    }
    func item(id: UUID) async throws -> ClipItem? { current?.id == id ? current : nil }
    func content(for id: UUID) async throws -> ClipContent? {
        await beforeContent()
        guard current?.id == id else { return nil }
        switch mutation {
        case .none: break
        case .removed: current = nil
        case .protected: current?.isSensitive = true
        case .expired: current?.expiresAt = .distantPast
        case .edited: current?.updatedAt = Date.now.addingTimeInterval(1)
        }
        return .text("Synthetic selected context")
    }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] { current.map { [$0] } ?? [] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] {
        current.map { [$0] } ?? []
    }
    func count() async throws -> Int { current == nil ? 0 : 1 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }
}

@MainActor private final class ContextDeliveryProbe {
    var allowed = true
    var revision = 1
    var delivered: [PreparedSelectedContext] = []
}

@Suite("Selected context delivery races") @MainActor
struct SelectedContextDeliveryTests {
    @Test func stableSelectionDeliveredOnce() async throws {
        let reader = ContextDeliveryReader()
        let probe = ContextDeliveryProbe()
        let expected = try await expectedParts(reader)
        let outcome = try await perform(expected, reader, probe)
        #expect(outcome == .delivered)
        #expect(probe.delivered.count == 1)
        #expect(probe.delivered.first?.manifest.orderedIDs == expected.map(\.id))
        let prepared = try #require(probe.delivered.first)
        let reviewed = try #require(try await reader.item(id: expected[0].id))
        #expect(prepared.revisions == [expected[0].id: reviewed.contextRevision])
        let grant = try SelectedContextDelivery.grant(for: prepared, clientName: "Client")
        #expect(
            grant.contextPack?.clipRevisions == [
                expected[0].id.uuidString: reviewed.contextRevision
            ])
    }

    @Test(arguments: [ContextDeliveryReader.Mutation.removed, .protected, .expired, .edited])
    fileprivate func selectionChanged(_ mutation: ContextDeliveryReader.Mutation) async throws {
        let reader = ContextDeliveryReader(mutation: mutation)
        let probe = ContextDeliveryProbe()
        let expected = try await expectedParts(reader)
        let outcome = try await perform(expected, reader, probe)
        #expect(outcome != .delivered)
        #expect(probe.delivered.isEmpty)
    }

    @Test func clipboardChangeDuringReadCannotOverwriteNewWork() async throws {
        let probe = ContextDeliveryProbe()
        let reader = ContextDeliveryReader(beforeContent: {
            await MainActor.run { probe.revision += 1 }
        })
        let expected = try await expectedParts(reader)
        #expect(try await perform(expected, reader, probe) == .changed(expected))
        #expect(probe.delivered.isEmpty)
    }

    @Test func privateModeDuringReadBlocksBothCopyAndGrant() async throws {
        let probe = ContextDeliveryProbe()
        let reader = ContextDeliveryReader(beforeContent: {
            await MainActor.run { probe.allowed = false }
        })
        let expected = try await expectedParts(reader)
        #expect(try await perform(expected, reader, probe) == .blocked)
        #expect(probe.delivered.isEmpty)
    }

    @Test func cancellationDuringReadHasNoEffects() async throws {
        let probe = ContextDeliveryProbe()
        let reader = ContextDeliveryReader(beforeContent: { withUnsafeCurrentTask { $0?.cancel() } }
        )
        let expected = try await expectedParts(reader)
        let result = await Task { try await perform(expected, reader, probe) }.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(probe.delivered.isEmpty)
    }

    private func expectedParts(_ reader: ContextDeliveryReader) async throws -> [CombinedTextPart] {
        let id = try #require(try await reader.items(offset: 0, limit: 1).first?.id)
        return [CombinedTextPart(id: id, content: .text("Synthetic selected context"))]
    }

    private func perform(
        _ expected: [CombinedTextPart], _ reader: ContextDeliveryReader,
        _ probe: ContextDeliveryProbe
    ) async throws -> SelectedContextDelivery.Outcome {
        try await SelectedContextDelivery.perform(
            expected: expected, from: reader, isAllowed: { probe.allowed },
            destinationUnchanged: { probe.revision == 1 }, deliver: { probe.delivered.append($0) })
    }
}
