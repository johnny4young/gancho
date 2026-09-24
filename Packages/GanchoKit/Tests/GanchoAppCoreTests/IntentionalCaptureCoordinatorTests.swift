import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor IntentionalStore: ClipIngesting {
    let fails: Bool
    let existing: ClipItem?
    init(fails: Bool = false, existing: ClipItem? = nil) {
        self.fails = fails
        self.existing = existing
    }
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        return existing ?? item
    }
}

@Suite("Intentional capture — durable outcomes")
struct IntentionalCaptureCoordinatorTests {
    private var configuration: ClipIngestionCoordinator.Configuration {
        .init(
            sensitiveLifetime: 120, tier: .free, intelligence: .init(),
            sourceDeviceName: "Synthetic device")
    }

    @Test(arguments: [
        PasteboardCapture.Payload.text("synthetic text"),
        .image(data: Data([1, 2]), typeIdentifier: "public.png")
    ])
    func failedInsertNeverSaysSaved(payload: PasteboardCapture.Payload) async {
        let outcome = await IntentionalCaptureCoordinator.save(
            .captured(PasteboardCapture(payload: payload), changeCount: 4),
            configuration: configuration, openStore: { IntentionalStore(fails: true) })
        guard case .saveFailed = outcome else {
            Issue.record("failed write must not report saved")
            return
        }
    }

    @Test("Opening failure differs from a failed write")
    func failedOpen() async {
        let outcome = await IntentionalCaptureCoordinator.save(
            .captured(PasteboardCapture(text: "synthetic"), changeCount: 4),
            configuration: configuration, openStore: { throw CocoaError(.fileReadNoPermission) })
        guard case .storeUnavailable = outcome else {
            Issue.record("expected unavailable store")
            return
        }
    }

    @Test(arguments: [IntentionalCaptureRead.Result.refused, .empty, .unavailable])
    func noCaptureNeverOpensStore(read: IntentionalCaptureRead.Result) async {
        let outcome = await IntentionalCaptureCoordinator.save(
            read, configuration: configuration,
            openStore: {
                Issue.record("must not open the store")
                return IntentionalStore()
            })
        switch (read, outcome) {
        case (.refused, .refused), (.empty, .empty), (.unavailable, .unavailable): break
        default: Issue.record("must preserve the reason")
        }
    }

    @Test("Success preserves the actual durable duplicate identity")
    func durableDuplicate() async {
        let existing = ClipItem(contentHash: "synthetic-existing")
        let outcome = await IntentionalCaptureCoordinator.save(
            .captured(PasteboardCapture(text: "synthetic"), changeCount: 4),
            configuration: configuration, openStore: { IntentionalStore(existing: existing) })
        guard case .saved(let saved) = outcome else {
            Issue.record("expected success")
            return
        }
        #expect(saved.item == existing)
        #expect(!saved.isNew)
    }

    @Test("Safe image/text payloads survive; configured sensitive lifetime is used")
    func realStoreAndPolicy() async throws {
        let store = InMemoryClipboardStore()
        let syntheticSecret = "api_key=sk_test_abcdefghijklmnopqrstuvwxyz0123456789"
        for payload in [
            PasteboardCapture.Payload.text(syntheticSecret),
            .image(data: Data([1, 2]), typeIdentifier: "public.png")
        ] {
            let outcome = await IntentionalCaptureCoordinator.save(
                .captured(PasteboardCapture(payload: payload), changeCount: 4),
                configuration: configuration, openStore: { store })
            guard case .saved(let saved) = outcome else {
                Issue.record("expected success")
                continue
            }
            #expect(saved.isNew)
            #expect(saved.item.sourceDeviceName == "Synthetic device")
            #expect(try await store.content(for: saved.item.id) == saved.content)
            if case .text = payload {
                #expect(saved.item.isSensitive)
                let expiry = try #require(saved.item.expiresAt)
                #expect(abs(expiry.timeIntervalSince(saved.item.createdAt) - 120) < 1)
            } else {
                #expect(saved.item.kind == .image)
            }
        }
    }
}
