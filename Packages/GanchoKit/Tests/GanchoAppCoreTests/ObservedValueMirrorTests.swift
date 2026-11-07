import Observation
import Testing

@testable import GanchoAppCore

@Observable
@MainActor
private final class MirrorSource {
    var status = "paused"
    var waiting = 0
    var unrelated = 0

    var summary: String { waiting == 0 ? status : "\(status) (\(waiting))" }
}

@MainActor
private final class WriteLog {
    var values: [String] = []
}

@Suite("Observed value mirror — writes on change, never on a timer")
@MainActor
struct ObservedValueMirrorTests {
    private func makeMirror(_ source: MirrorSource, _ log: WriteLog) -> ObservedValueMirror<String>
    {
        ObservedValueMirror(read: { source.summary }, write: { log.values.append($0) })
    }

    /// Main-actor turns only: no wall-clock time passes, so no timer can fire.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("Start writes the current value once")
    func startWritesTheCurrentValue() async {
        let source = MirrorSource()
        let log = WriteLog()
        let mirror = makeMirror(source, log)
        mirror.start()
        await settle()
        #expect(log.values == ["paused"])
    }

    @Test("Each change is written within main-actor turns")
    func changesAreWrittenWithoutATimer() async {
        let source = MirrorSource()
        let log = WriteLog()
        let mirror = makeMirror(source, log)
        mirror.start()

        source.status = "capturing"
        await settle()
        source.waiting = 2
        await settle()

        #expect(log.values == ["paused", "capturing", "capturing (2)"])
    }

    @Test("A change that leaves the value equal writes nothing")
    func equalValuesAreNotRewritten() async {
        let source = MirrorSource()
        let log = WriteLog()
        let mirror = makeMirror(source, log)
        mirror.start()

        source.status = "paused"
        await settle()
        source.unrelated += 1
        await settle()

        #expect(log.values == ["paused"])
    }

    @Test("Refresh writes only a value that changed")
    func refreshWritesOnlyChanges() {
        var external = "none"
        let log = WriteLog()
        let mirror = ObservedValueMirror(read: { external }, write: { log.values.append($0) })
        mirror.start()
        mirror.refresh()
        external = "⇧⌘V"
        mirror.refresh()
        mirror.refresh()

        #expect(log.values == ["none", "⇧⌘V"])
    }

    @Test("Stop ends writes, and a second start does not double them")
    func stopEndsWrites() async {
        let source = MirrorSource()
        let log = WriteLog()
        let mirror = makeMirror(source, log)
        mirror.start()
        mirror.start()
        source.status = "capturing"
        await settle()
        #expect(log.values == ["paused", "capturing"])

        mirror.stop()
        source.status = "sharing"
        await settle()
        #expect(log.values == ["paused", "capturing"])
    }
}
