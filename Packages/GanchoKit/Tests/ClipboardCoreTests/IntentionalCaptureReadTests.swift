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
}
