import Foundation
import GanchoAI
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
    /// Bounded: an unbounded spin makes a regression hang the whole package run
    /// instead of failing one test, which is exactly how a lost signal hides.
    func waitUntilStarted() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !started, ContinuousClock.now < deadline { await Task.yield() }
        return started
    }
    func release() {
        waiter?.resume(returning: "old result")
        waiter = nil
    }
}

/// Stands in for Vision failing on a readable image, as opposed to the source
/// clip having gone away (`ManualImageTextError.unavailable`).
private struct OCRRecognizerFailure: Error {}

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

@Suite("Manual OCR — transient, latest request wins", .timeLimit(.minutes(1))) @MainActor
struct ManualOCRSessionTests {
    @Test("Copies without any entitlement or automatic-enrichment preference")
    func copies() async {
        let session = ManualOCRSession()
        var copies: [String] = []
        let result = await withCheckedContinuation { continuation in
            session.start(
                recognize: { ManualOCRResult(text: "Hola\nGancho") }, isAllowed: { true },
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
            recognize: { (await latch.recognize()).map(ManualOCRResult.init(text:)) },
            isAllowed: { true },
            clipboardRevision: { clipboard.revision }, copy: { _ in copies += 1 },
            didFinish: { _ in })
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
        clipboard.revision = 2
        await latch.release()
        #expect(await settled(session), "the session never left .recognizing")
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
            recognize: { (await latch.recognize()).map(ManualOCRResult.init(text:)) },
            isAllowed: { true },
            clipboardRevision: { 0 }, copy: { _ in copies += 1 },
            didFinish: { _ in Issue.record("late result") })
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
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
            recognize: { (await latch.recognize()).map(ManualOCRResult.init(text:)) },
            isAllowed: { true },
            clipboardRevision: { 0 }, copy: { copies.append($0) },
            didFinish: { _ in Issue.record("old request") })
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { ManualOCRResult(text: "new") }, isAllowed: { true },
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
                recognize: { result.map(ManualOCRResult.init(text:)) }, isAllowed: { true },
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
            let forbiddenRead: @Sendable () async throws -> ManualOCRResult? = {
                Issue.record("unexpected read")
                return ManualOCRResult(text: "bad")
            }
            session.start(
                recognize: forbiddenRead, isAllowed: { false },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        #expect(session.state == .unavailable)
    }

    @Test("A source that vanished mid-read reports unavailable, not a read failure")
    func vanishedSourceIsUnavailable() async {
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { throw ManualImageTextError.unavailable }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        // .failed tells the user to try ANOTHER image; this image is simply gone.
        #expect(session.state == .unavailable)
        #expect(session.text.isEmpty)
    }

    @Test("Source protection during recognition prevents late delivery")
    func revokedDuringRecognition() async {
        let permission = OCRPermission()
        let latch = OCRLatch()
        let session = ManualOCRSession()
        session.start(
            recognize: { (await latch.recognize()).map(ManualOCRResult.init(text:)) },
            isAllowed: { await permission.read() },
            clipboardRevision: { 0 }, copy: { _ in Issue.record("protected copy") },
            didFinish: { _ in })
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
        await permission.revoke()
        await latch.release()
        #expect(await settled(session), "the session never left .recognizing")
        #expect(session.state == .unavailable)
        #expect(session.text.isEmpty)
    }

    @Test("Source protection after recognition prevents review actions")
    func revokedBeforeReview() async {
        let permission = OCRPermission()
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            session.start(
                recognize: { ManualOCRResult(text: "safe when requested") },
                isAllowed: { await permission.read() },
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
                recognize: { ManualOCRResult(text: "Synthetic OCR") },
                isAllowed: { await permission.read() },
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
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
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
                recognize: { ManualOCRResult(text: "Synthetic OCR") },
                isAllowed: { await permission.read() },
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
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
        session.cancel()
        await latch.release()
        #expect(await task.value == .unavailable)
        #expect(session.text.isEmpty)
    }

    @Test("Errors are content-free and do not overwrite the clipboard")
    func failure() async {
        let session = ManualOCRSession()
        await withCheckedContinuation { continuation in
            // A recognizer error, NOT a vanished source: those map to different
            // states because they need different advice from the user.
            session.start(
                recognize: { throw OCRRecognizerFailure() }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { _ in Issue.record("unexpected copy") },
                didFinish: { _ in continuation.resume() })
        }
        #expect(session.state == .failed)
        #expect(session.text.isEmpty)
    }

    @Test("A recognized secret is never copied automatically")
    func secretStaysOutOfTheClipboard() async {
        let session = ManualOCRSession()
        var copies = 0
        let result = await withCheckedContinuation { continuation in
            session.start(
                itemID: UUID(),
                recognize: { ManualOCRResult(text: "card 4242 4242 4242 4242") },
                isAllowed: { true }, isSensitive: { $0.contains("4242") },
                clipboardRevision: { 0 }, copy: { _ in copies += 1 },
                didFinish: { continuation.resume(returning: $0) })
        }
        #expect(result == .ready)
        #expect(session.isSensitive)
        #expect(copies == 0, "a flagged secret waits for an explicit copy")
        // An explicit copy after review is still the user's call.
        #expect(await session.reviewedText(session.text) == session.text)
    }

    @Test("The session remembers which clip it serves and forgets it on cancel")
    func itemIdentity() async {
        let session = ManualOCRSession()
        let id = UUID()
        let lines = [
            RecognizedTextLine(text: "a", box: CGRect(x: 0, y: 0, width: 0.5, height: 0.1)),
            RecognizedTextLine(text: "b")
        ]
        await withCheckedContinuation { continuation in
            session.start(
                itemID: id, recognize: { ManualOCRResult(lines: lines) }, isAllowed: { true },
                clipboardRevision: { 0 }, copy: { _ in }, didFinish: { _ in continuation.resume() })
        }
        #expect(session.itemID == id)
        #expect(session.lines == lines)
        #expect(session.text == "a\nb")
        session.cancel()
        #expect(session.itemID == nil)
        #expect(session.lines.isEmpty)
    }

    @Test("Cached text avoids OCR; binary input uses injected recognition")
    func cachedAndFresh() async throws {
        let service = ManualImageTextService()
        let cached = try await service.result(
            for: UUID(), store: ImageReaderStub(input: .cached("cached"))
        ) { _ in
            Issue.record("unexpected recognition")
            return []
        }
        #expect(cached?.text == "cached")
        let fresh = try await service.result(
            for: UUID(), store: ImageReaderStub(input: .image(Data([1])))
        ) { data in
            #expect(data == Data([1]))
            return [RecognizedTextLine(text: "fresh")]
        }
        #expect(fresh?.text == "fresh")
        await #expect(throws: ManualImageTextError.self) {
            try await service.result(for: UUID(), store: ImageReaderStub(input: nil))
        }
    }

    /// Bounded wait for a terminal state. Without the deadline a session that
    /// never finishes hangs the package run instead of failing this test.
    private func settled(_ session: ManualOCRSession) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while session.state == .recognizing, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return session.state != .recognizing
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

@Suite("Manual OCR storage cancellation", .timeLimit(.minutes(1)))
struct ManualOCRStorageCancellationTests {
    @Test("Cancel during the image read stops cached and fresh OCR", arguments: [true, false])
    func canceledRead(cached: Bool) async {
        let latch = OCRLatch()
        let reader = DelayedImageReader(
            latch: latch, input: cached ? .cached("synthetic") : .image(Data([1])))
        let task = Task {
            try await ManualImageTextService().result(for: UUID(), store: reader) { _ in
                Issue.record("Canceled storage read must not start recognition")
                return [RecognizedTextLine(text: "synthetic")]
            }
        }
        #expect(await latch.waitUntilStarted(), "the recognizer never started")
        task.cancel()
        await latch.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
