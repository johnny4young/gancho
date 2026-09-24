import Foundation
import Synchronization
import Testing

@testable import GanchoKit

private actor DeliveryReader {
    enum Failure: Error { case unavailable }
    var snapshots: [ClipItem?]
    let body: ClipContent?
    let fails: Bool
    private(set) var payloadReads = 0

    init(
        _ snapshots: [ClipItem?], body: ClipContent? = .text("synthetic-full-content"),
        fails: Bool = false
    ) {
        self.snapshots = snapshots
        self.body = body
        self.fails = fails
    }

    func metadata(_ id: UUID) throws -> ClipItem? {
        guard !snapshots.isEmpty else { return nil }
        return snapshots.removeFirst()
    }

    func content(_ id: UUID) throws -> ClipContent? {
        payloadReads += 1
        if fails { throw Failure.unavailable }
        return body
    }
}

private actor SuspendedDelivery {
    let item = ClipItem()
    private var pending: CheckedContinuation<ClipContent?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func metadata(_ id: UUID) -> ClipItem? { item }
    func content(_ id: UUID) async -> ClipContent? {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilReading() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() {
        pending?.resume(returning: .text("synthetic-cancelled"))
        pending = nil
    }
}

@Suite(
    "Safe lazy delivery — authorization around asynchronous content reads", .timeLimit(.minutes(1)))
struct ClipSafeDeliveryTests {
    @Test(arguments: [ClipContentKind.jwt, .creditCard, .secret, .text])
    func protectedRowsNeverReadPayload(kind: ClipContentKind) async {
        let item = ClipItem(kind: kind, isSensitive: kind == .text)
        let reader = DeliveryReader([item])
        let payload = await ClipSafeDelivery.load(
            id: item.id, metadata: { try await reader.metadata($0) },
            content: { try await reader.content($0) })
        #expect(payload == nil)
        #expect(await reader.payloadReads == 0)
    }

    @Test(arguments: [
        ClipContent.text(String(repeating: "synthetic full text\n", count: 100)),
        .fileReferences(["/synthetic/one", "/synthetic/two"]),
        .binary(data: Data([1, 2, 3]), typeIdentifier: "public.png")
    ])
    func unchangedSafeContentIsNotTruncated(body: ClipContent) async throws {
        let item = ClipItem(preview: "short preview")
        let reader = DeliveryReader([item, item], body: body)
        let payload = try #require(
            await ClipSafeDelivery.load(
                id: item.id, metadata: { try await reader.metadata($0) },
                content: { try await reader.content($0) }))
        #expect(payload.item == item)
        #expect(payload.content == body)
    }

    @Test("Deletion, reclassification, protection and revision changes reject loaded bytes")
    func changedMetadataRefusesPayload() async {
        let before = ClipItem(contentHash: "before")
        var sensitive = before
        sensitive.isSensitive = true
        var intrinsic = before
        intrinsic.kind = .jwt
        var edited = before
        edited.contentHash = "after"
        var revision = before
        revision.updatedAt += 1
        for after in [nil, sensitive, intrinsic, edited, revision] {
            let reader = DeliveryReader([before, after])
            let payload = await ClipSafeDelivery.load(
                id: before.id, metadata: { try await reader.metadata($0) },
                content: { try await reader.content($0) })
            #expect(payload == nil)
            #expect(await reader.payloadReads == 1)
        }
    }

    @Test("A usage bump during the read (another drop representation) still delivers")
    func usageBumpKeepsPayload() async throws {
        let before = ClipItem(contentHash: "stable")
        var after = before
        after.lastUsedAt = .now
        after.uses += 1
        let reader = DeliveryReader([before, after])
        let payload = try #require(
            await ClipSafeDelivery.load(
                id: before.id, metadata: { try await reader.metadata($0) },
                content: { try await reader.content($0) }))
        #expect(payload.item == after)
    }

    @Test("Missing metadata, missing content and read failures return unavailable")
    func unavailableInputs() async {
        let item = ClipItem()
        for reader in [
            DeliveryReader([nil]), DeliveryReader([item], body: nil),
            DeliveryReader([item], fails: true)
        ] {
            let payload = await ClipSafeDelivery.load(
                id: item.id, metadata: { try await reader.metadata($0) },
                content: { try await reader.content($0) })
            #expect(payload == nil)
        }
        let payload = await ClipSafeDelivery.load(
            id: item.id,
            metadata: { _ in throw DeliveryReader.Failure.unavailable },
            content: { _ in
                Issue.record("Failed metadata must not load content")
                return nil
            })
        #expect(payload == nil)
    }

    @Test("Expiry is checked before and after the payload read")
    func expiry() async {
        let start = Date(timeIntervalSince1970: 100)
        let item = ClipItem(expiresAt: start + 1)
        let expired = DeliveryReader([item])
        #expect(
            await ClipSafeDelivery.load(
                id: item.id, metadata: { try await expired.metadata($0) },
                content: { try await expired.content($0) },
                now: { start + 1 }) == nil)
        #expect(await expired.payloadReads == 0)

        let clock = Mutex(start)
        let reader = DeliveryReader([item, item])
        let payload = await ClipSafeDelivery.load(
            id: item.id, metadata: { try await reader.metadata($0) },
            content: { id in
                clock.withLock { $0 = start + 1 }
                return try await reader.content(id)
            }, now: { clock.withLock { $0 } })
        #expect(payload == nil)
        #expect(await reader.payloadReads == 1)
    }

    @Test("Cancellation during a suspended read cannot deliver its result")
    func cancelledRead() async {
        let reader = SuspendedDelivery()
        let id = reader.item.id
        let task = Task {
            await ClipSafeDelivery.load(
                id: id, metadata: { await reader.metadata($0) },
                content: { await reader.content($0) })
        }
        await reader.waitUntilReading()
        task.cancel()
        await reader.finish()
        #expect(await task.value == nil)
    }

    @Test("Private mode and intrinsic kinds share the passive masking contract")
    func passivePreview() {
        let safe = ClipItem(title: "synthetic title", preview: "synthetic preview")
        let originalSignature: (ClipItem) -> String = ClipSafePresentation.displayText
        #expect(originalSignature(safe) == safe.preview)
        #expect(ClipSafePresentation.displayText(for: safe) == safe.preview)
        #expect(
            ClipSafePresentation.displayText(for: safe, privateMode: true)
                == ClipSafePresentation.masked)
        for kind in ClipContentKind.allCases where kind.prefersMaskedPreview {
            var item = safe
            item.kind = kind
            #expect(ClipSafePresentation.displayText(for: item) == ClipSafePresentation.masked)
        }
    }
}
