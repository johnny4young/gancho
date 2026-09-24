import Foundation
import Testing

@testable import ClipboardCore

@Suite("Intentional capture — metadata authorization")
@MainActor
struct IntentionalCaptureReadTests {
    @Test(arguments: Array(SensitivePasteboardTypes.captureVeto))
    func reservedTypesNeverRead(type: String) async {
        var reads = 0
        let result = await IntentionalCaptureRead.read(
            metadata: { .init(types: [type], changeCount: 4, hasContent: true) },
            payload: {
                reads += 1
                return .text("synthetic")
            })
        #expect(result == .refused)
        #expect(reads == 0)
    }

    @Test("Empty metadata avoids payload reads; advertised but unreadable is unavailable")
    func emptyAndUnavailable() async {
        var reads = 0
        let empty = await IntentionalCaptureRead.read(
            metadata: { .init(types: [], changeCount: 4, hasContent: false) },
            payload: {
                reads += 1
                return nil
            })
        #expect(empty == .empty)
        #expect(reads == 0)
        let unavailable = await IntentionalCaptureRead.read(
            metadata: { .init(types: ["public.text"], changeCount: 4, hasContent: true) },
            payload: { nil })
        #expect(unavailable == .unavailable)
    }

    @Test("Replaced or newly protected content is never delivered")
    func changedRead() async {
        for protected in [false, true] {
            var changed = false
            let result = await IntentionalCaptureRead.read(
                metadata: {
                    .init(
                        types: changed && protected ? [SensitivePasteboardTypes.concealed] : [],
                        changeCount: changed ? 5 : 4, hasContent: true)
                },
                payload: {
                    changed = true
                    return .text("synthetic")
                })
            #expect(result == (protected ? .refused : .unavailable))
        }
    }

    @Test(arguments: [
        PasteboardCapture.Payload.text("synthetic text"),
        .image(data: Data([1, 2]), typeIdentifier: "public.png")
    ])
    func preservesPayload(payload: PasteboardCapture.Payload) async throws {
        let result = await IntentionalCaptureRead.read(
            metadata: {
                .init(
                    types: [SensitivePasteboardTypes.remoteClipboard], changeCount: 4,
                    hasContent: true)
            },
            payload: { payload })
        guard case .captured(let capture, let count) = result else {
            Issue.record("expected capture")
            return
        }
        #expect(capture.payload == payload)
        #expect(capture.isFromUniversalClipboard)
        #expect(count == 4)
    }

    @Test("Read errors remain unavailable and content-free")
    func failedRead() async {
        let result = await IntentionalCaptureRead.read(
            metadata: { .init(types: [], changeCount: 4, hasContent: true) },
            payload: { throw CocoaError(.fileReadNoPermission) })
        #expect(result == .unavailable)
    }

    @Test("Cancellation after a read never authorizes persistence")
    func cancelledRead() async {
        let task = Task {
            await IntentionalCaptureRead.read(
                metadata: { .init(types: [], changeCount: 4, hasContent: true) },
                payload: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .text("synthetic")
                })
        }
        #expect(await task.value == .unavailable)
    }

    @Test("Types appearing while data materialises do not reject an unchanged copy")
    func typesGrowWithSameChangeCount() async {
        var materialised = false
        let result = await IntentionalCaptureRead.read(
            metadata: {
                .init(
                    types: materialised ? ["public.text", "public.rtf"] : ["public.text"],
                    changeCount: 4, hasContent: true)
            },
            payload: {
                materialised = true
                return .text("synthetic")
            })
        guard case .captured = result else {
            Issue.record("an unchanged copy must be captured")
            return
        }
    }

    @Test("A marker on any provider refuses the batch before any load")
    func batchSiblingMarker() async {
        var loads = 0
        let results = await IntentionalCaptureRead.readBatch(
            count: 2,
            metadata: {
                .init(
                    types: ["public.text", SensitivePasteboardTypes.transient], changeCount: 4,
                    hasContent: true)
            },
            isSupported: { _ in true },
            payload: { _ in
                loads += 1
                return .text("synthetic")
            })
        #expect(results == [.refused])
        #expect(loads == 0)
    }

    @Test("Unsupported items are skipped and a failed load keeps its siblings")
    func batchKeepsReadableItems() async {
        let results = await IntentionalCaptureRead.readBatch(
            count: 3,
            metadata: { .init(types: ["public.text"], changeCount: 4, hasContent: true) },
            isSupported: { $0 != 1 },
            payload: { $0 == 0 ? .text("synthetic") : nil })
        #expect(results.count == 2)
        guard case .captured(let capture, _) = results.first else {
            Issue.record("the readable item must survive")
            return
        }
        #expect(capture.payload == .text("synthetic"))
        #expect(results.last == .unavailable)
    }

    @Test("A batch of only unsupported items is unavailable, not empty")
    func batchAllUnsupported() async {
        let results = await IntentionalCaptureRead.readBatch(
            count: 2,
            metadata: { .init(types: ["com.adobe.pdf"], changeCount: 4, hasContent: true) },
            isSupported: { _ in false },
            payload: { _ in
                Issue.record("unsupported items must not load")
                return nil
            })
        #expect(results == [.unavailable])
    }

    @Test("A replaced or newly protected clipboard discards earlier items")
    func batchChangedMidway() async {
        for protected in [false, true] {
            var changed = false
            let results = await IntentionalCaptureRead.readBatch(
                count: 2,
                metadata: {
                    .init(
                        types: changed && protected ? [SensitivePasteboardTypes.concealed] : [],
                        changeCount: changed ? 5 : 4, hasContent: true)
                },
                isSupported: { _ in true },
                payload: { index in
                    if index == 1 { changed = true }
                    return .text("synthetic \(index)")
                })
            #expect(results == [protected ? .refused : .unavailable])
        }
    }

    @Test("An empty batch is empty")
    func batchEmpty() async {
        let results = await IntentionalCaptureRead.readBatch(
            count: 0,
            metadata: { .init(types: [], changeCount: 4, hasContent: false) },
            isSupported: { _ in true },
            payload: { _ in nil })
        #expect(results == [.empty])
    }
}
