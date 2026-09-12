import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor OCRLatch {
    private var waiter: CheckedContinuation<String?, Never>?
    private var started = false
    func recognize() async -> String? {
        started = true
        return await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilStarted() async { while !started { await Task.yield() } }
    func release() {
        waiter?.resume(returning: "old result")
        waiter = nil
    }
}

private struct ImageReaderStub: ImageTextReading {
    let input: ImageTextInput?
    func imageTextInput(id: UUID, now: Date) async throws -> ImageTextInput? { input }
    func permitsImageText(id: UUID, now: Date) async throws -> Bool { input != nil }
}

@MainActor private final class OCRClipboardProbe {
    var revision = 1
}

private actor OCRPermission {
    private var allowed = true
    private var nextRead: OCRLatch?
    func delayNextRead(_ latch: OCRLatch) { nextRead = latch }
    func read() async -> Bool {
        if let latch = nextRead {
            nextRead = nil
            _ = await latch.recognize()
        }
        return allowed
    }
    func revoke() { allowed = false }
}

@Suite("Manual OCR — transient, latest request wins") @MainActor
struct ManualOCRSessionTests {
    @Test("Copies without any entitlement or automatic-enrichment preference")
    func copies() async {
        let session = ManualOCRSession()
        var copies: [String] = []
        let result = await withCheckedContinuation { continuation in
            session.start(
                recognize: { "Hola\nGancho" }, isAllowed: { true },
                clipboardRevision: { 1 }, copy: { copies.append($0) },
                didFinish: { continuation.resume(returning: $0) })
        }
        #expect(result == .copied)
        #expect(copies == ["Hola\nGancho"])
        #expect(await session.reviewedText("edited") == "edited")
        #expect(await session.reviewedText("  ") == nil)
        session.cancel()
        #expect(session.text.isEmpty)
        #expect(await session.reviewedText("edited") == nil)
    }

    @Test("New clipboard content wins over delayed recognition")
    func preservesNewClipboard() async {
        let session = ManualOCRSession()
        let latch = OCRLatch()
        let clipboard = OCRClipboardProbe()
        var copies = 0
        session.start(
            recognize: { await latch.recognize() }, isAllowed: { true },
            clipboardRevision: { clipboard.revision }, copy: { _ in copies += 1 },
            didFinish: { _ in })
        await latch.waitUntilStarted()
        clipboard.revision = 2
        await latch.release()
        while session.state == .recognizing { await Task.yield() }
        #expect(session.state == .ready)
        #expect(copies == 0)
        #expect(session.text == "old result")
    }

    @Test("Uncooperative canceled work never copies or publishes a result")
    func cancellation() async {
        let session = ManualOCRSession()
        let latch = OCRLatch()
        var copies = 0
        session.start(
            recognize: { await latch.recognize() }, isAllowed: { true },
            clipboardRevision: { 0 }, copy: { _ in copies += 1 },
            didFinish: { _ in Issue.record("late result") })
        await latch.waitUntilStarted()
        session.cancel()
        await latch.release()
        #expect(session.state == .idle)
        #expect(session.text.isEmpty)
        #expect(copies == 0)
    }

    @Test("Supersession keeps only the newest result")
    func supersession() async {
        let session = ManualOCRSession()
        let latch = OCRLatch()
        var copies: [String] = []
        session.start(
            recognize: { await latch.recognize() }, isAllowed: { true },
            clipboardRevision: { 0 }, copy: { copies.append($0) },
            didFinish: { _ in Issue.record("old request") })
        await latch.waitUntilStarted()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { "new" }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { copies.append($0) },
                didFinish: { _ in continuation.resume() })
        }
        await latch.release()
        #expect(copies == ["new"])
        #expect(session.text == "new")
    }

    @Test("Empty recognition never writes", arguments: [nil, "", " \n"] as [String?])
    func empty(_ result: String?) async {
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { result }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        #expect(session.state == .noText)
        #expect(session.text.isEmpty)
    }

    @Test("Denied source is not read")
    func denied() async {
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            let forbiddenRead: @Sendable () async throws -> String? = {
                Issue.record("unexpected read")
                return "bad"
            }
            session.start(
                recognize: forbiddenRead, isAllowed: { false },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        #expect(session.state == .unavailable)
    }

    @Test("Source protection during recognition prevents late delivery")
    func revokedDuringRecognition() async {
        let permission = OCRPermission()
        let latch = OCRLatch()
        let session = ManualOCRSession()
        session.start(
            recognize: { await latch.recognize() }, isAllowed: { await permission.read() },
            clipboardRevision: { 0 }, copy: { _ in Issue.record("protected copy") },
            didFinish: { _ in })
        await latch.waitUntilStarted()
        await permission.revoke()
        await latch.release()
        while session.state == .recognizing { await Task.yield() }
        #expect(session.state == .unavailable)
        #expect(session.text.isEmpty)
    }

    @Test("Source protection after recognition prevents review actions")
    func revokedBeforeReview() async {
        let permission = OCRPermission()
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { "safe when requested" }, isAllowed: { await permission.read() },
                clipboardRevision: { 0 }, copy: { _ in },
                didFinish: { _ in continuation.resume() })
        }
        await permission.revoke()
        #expect(await session.reviewedText("edited") == nil)
        session.cancel()
        #expect(session.text.isEmpty)
    }

    @Test("Reviewed copy preserves newer clipboard content and retains a retryable draft")
    func reviewClipboardRace() async {
        let session = ManualOCRSession()
        let permission = OCRPermission()
        let clipboard = OCRClipboardProbe()
        var copied: [String] = []
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { "Synthetic OCR" }, isAllowed: { await permission.read() },
                clipboardRevision: { clipboard.revision }, copy: { _ in },
                didFinish: { _ in continuation.resume() })
        }
        let latch = OCRLatch()
        await permission.delayNextRead(latch)
        let task = Task {
            await session.copyReviewedText(
                "Edited draft", clipboardRevision: { clipboard.revision },
                copy: { copied.append($0) })
        }
        await latch.waitUntilStarted()
        clipboard.revision += 1
        await latch.release()
        #expect(await task.value == .clipboardChanged)
        #expect(copied.isEmpty)
        #expect(!session.text.isEmpty)
        #expect(
            await session.copyReviewedText(
                "Edited draft", clipboardRevision: { clipboard.revision },
                copy: { copied.append($0) }) == .copied)
        #expect(copied == ["Edited draft"])
    }

    @Test("Closing review during validation never copies its delayed result")
    func canceledReviewCopy() async {
        let session = ManualOCRSession()
        let permission = OCRPermission()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { "Synthetic OCR" }, isAllowed: { await permission.read() },
                clipboardRevision: { 0 }, copy: { _ in },
                didFinish: { _ in continuation.resume() })
        }
        let latch = OCRLatch()
        await permission.delayNextRead(latch)
        let task = Task {
            await session.copyReviewedText(
                "Edited draft", clipboardRevision: { 0 },
                copy: { _ in Issue.record("Canceled review must not copy") })
        }
        await latch.waitUntilStarted()
        session.cancel()
        await latch.release()
        #expect(await task.value == .unavailable)
        #expect(session.text.isEmpty)
    }

    @Test("Errors are content-free and do not overwrite the clipboard")
    func failure() async {
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { throw ManualImageTextError.unavailable }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        #expect(session.state == .failed)
        #expect(session.text.isEmpty)
    }

    @Test("Cached text avoids OCR; binary input uses injected recognition")
    func cachedAndFresh() async throws {
        let service = ManualImageTextService()
        let cached = try await service.text(
            for: UUID(), store: ImageReaderStub(input: .cached("cached"))
        ) { _ in
            Issue.record("unexpected recognition")
            return nil
        }
        #expect(cached == "cached")
        let fresh = try await service.text(
            for: UUID(), store: ImageReaderStub(input: .image(Data([1])))
        ) { data in
            #expect(data == Data([1]))
            return "fresh"
        }
        #expect(fresh == "fresh")
        await #expect(throws: ManualImageTextError.self) {
            try await service.text(for: UUID(), store: ImageReaderStub(input: nil))
        }
    }
}

private struct DelayedImageReader: ImageTextReading {
    let latch: OCRLatch
    let input: ImageTextInput
    func imageTextInput(id: UUID, now: Date) async throws -> ImageTextInput? {
        _ = await latch.recognize()
        return input
    }
    func permitsImageText(id: UUID, now: Date) async throws -> Bool { true }
}

@Suite("Manual OCR storage cancellation")
struct ManualOCRStorageCancellationTests {
    @Test("Cancel during the image read stops cached and fresh OCR", arguments: [true, false])
    func canceledRead(cached: Bool) async {
        let latch = OCRLatch()
        let reader = DelayedImageReader(
            latch: latch, input: cached ? .cached("synthetic") : .image(Data([1])))
        let task = Task {
            try await ManualImageTextService().text(for: UUID(), store: reader) { _ in
                Issue.record("Canceled storage read must not start recognition")
                return "synthetic"
            }
        }
        await latch.waitUntilStarted()
        task.cancel()
        await latch.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
