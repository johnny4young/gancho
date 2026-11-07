import Testing

@testable import GanchoAppCore

@MainActor
private final class SaveRecorder {
    var pausesStarted = 0
    var saved: [String] = []
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    /// A save that marks itself started, then holds until `release()`.
    func blockingSave(_ name: String) async {
        hasStarted = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        if !isOpen { await withCheckedContinuation { waiters.append($0) } }
        saved.append(name)
    }

    func waitUntilStarted() async {
        if !hasStarted { await withCheckedContinuation { startWaiters.append($0) } }
    }

    func release() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

@Suite("Capture save queue — a pause drops saves that have not started", .timeLimit(.minutes(1)))
@MainActor
struct CaptureSaveQueueTests {
    @Test("Saves run in the order they were enqueued")
    func savesRunInOrder() async {
        let recorder = SaveRecorder()
        let queue = CaptureSaveQueue(pausesStarted: { recorder.pausesStarted })

        queue.enqueue(afterPrevious: true) { await recorder.blockingSave("first") }
        let second = queue.enqueue(afterPrevious: true) { recorder.saved.append("second") }
        await recorder.waitUntilStarted()
        recorder.release()
        await second.value

        #expect(recorder.saved == ["first", "second"])
    }

    @Test("A save waiting behind another is dropped when a pause starts")
    func pauseDropsQueuedSave() async {
        let recorder = SaveRecorder()
        let queue = CaptureSaveQueue(pausesStarted: { recorder.pausesStarted })

        queue.enqueue(afterPrevious: true) { await recorder.blockingSave("before the pause") }
        let queued = queue.enqueue(afterPrevious: true) { recorder.saved.append("queued") }
        await recorder.waitUntilStarted()
        recorder.pausesStarted += 1
        recorder.release()
        await queued.value

        #expect(recorder.saved == ["before the pause"])
    }

    @Test("A save that has not started is dropped even with nothing ahead of it")
    func pauseDropsUnchainedSave() async {
        let recorder = SaveRecorder()
        let queue = CaptureSaveQueue(pausesStarted: { recorder.pausesStarted })

        let save = queue.enqueue(afterPrevious: false) { recorder.saved.append("copied") }
        recorder.pausesStarted += 1
        await save.value

        #expect(recorder.saved.isEmpty)
    }

    @Test("Only a pause that starts after the save was enqueued drops it")
    func earlierPauseKeepsSave() async {
        let recorder = SaveRecorder()
        recorder.pausesStarted = 1
        let queue = CaptureSaveQueue(pausesStarted: { recorder.pausesStarted })

        await queue.enqueue(afterPrevious: true) { recorder.saved.append("after") }.value

        #expect(recorder.saved == ["after"])
    }
}
