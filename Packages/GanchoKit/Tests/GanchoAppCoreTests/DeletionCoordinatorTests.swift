import Foundation
import Testing

@testable import GanchoAppCore

/// Ordered event log for the coordinator's two commit hooks, so a test asserts
/// not just that they ran but in what ORDER and how many times — the gate that
/// keeps the remove-before-didFinish contract non-vacuous. `@MainActor` because
/// the coordinator invokes its hooks on the main actor and the suite is too, so
/// no cross-actor hop is needed to read the log back.
@MainActor
private final class Recorder {
    private(set) var log: [String] = []

    func record(_ entry: String) { log.append(entry) }

    var performCount: Int { log.filter { $0.hasPrefix("perform") }.count }
    var finishCount: Int { log.filter { $0.hasPrefix("finish") }.count }
}

// Drives the undo-window deletion state machine deterministically: the grace is
// injected small so the commit fires promptly, and every wait is a BOUNDED poll
// on the observable state (never a fixed sleep sized to the grace, which would
// flake). The commit hooks are recorded so the tests pin ordering and counts,
// not merely "something happened".
// Serialized: these tests each spin an unstructured main-actor timer task, and
// under Swift Testing's default parallelism a post-`sleep` continuation can be
// starved past a poll window on a loaded CI runner. Serializing removes the
// intra-suite contention so the commit lands deterministically.
@Suite("Deletion coordinator — undo-window state machine", .serialized)
@MainActor
struct DeletionCoordinatorTests {
    /// Polls `condition` on the main actor until it holds or the deadline passes.
    /// Deterministic without a fixed grace-sized sleep: the loop simply observes
    /// the state the coordinator's async commit mutates, so it returns the moment
    /// the commit lands rather than after a guessed delay.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("beginDeletion marks the id pending immediately")
    func beginMarksPending() {
        let coordinator = DeletionCoordinator(grace: .seconds(60))
        let id = UUID()

        coordinator.beginDeletion(id, performDelete: { _ in }, didFinish: { _ in })

        #expect(coordinator.isPending(id))
        #expect(coordinator.hasPending)
    }

    @Test("After the grace: performDelete runs once THEN didFinish, and clears pending")
    func commitRunsInOrderAndClearsPending() async {
        // Zero grace: the commit becomes ready on the next executor turn instead
        // of after a wall-clock window that can be starved under load, so the poll
        // observes it deterministically. The ordering assertions are the point.
        let coordinator = DeletionCoordinator(grace: .zero)
        let recorder = Recorder()
        let id = UUID()

        coordinator.beginDeletion(
            id,
            performDelete: { _ in recorder.record("perform") },
            // Capture the pending state AT the didFinish call so the test proves
            // the remove happened BEFORE didFinish (a failed store delete relies
            // on the list re-deriving from the store with the hold already gone).
            // Weak to avoid a coordinator→task→closure→coordinator retain cycle.
            didFinish: { [weak coordinator] _ in
                recorder.record("finish-pending=\(coordinator?.isPending(id) ?? true)")
            })

        #expect(coordinator.isPending(id))

        await waitUntil({ recorder.finishCount == 1 }, timeout: .seconds(5))

        #expect(recorder.log == ["perform", "finish-pending=false"])
        #expect(recorder.performCount == 1)
        #expect(recorder.finishCount == 1)
        #expect(!coordinator.isPending(id))
        #expect(!coordinator.hasPending)
    }

    @Test("undo before the grace: performDelete never runs and pending clears")
    func undoBeforeGraceCancelsCommit() async {
        let coordinator = DeletionCoordinator(grace: .milliseconds(50))
        let recorder = Recorder()
        let id = UUID()

        coordinator.beginDeletion(
            id,
            performDelete: { _ in recorder.record("perform") },
            didFinish: { _ in recorder.record("finish") })
        #expect(coordinator.isPending(id))

        coordinator.undo(id) { _ in recorder.record("undo-then") }

        // The hold is cleared synchronously by undo; the `then` refresh is async.
        #expect(!coordinator.isPending(id))
        await waitUntil { recorder.log.contains("undo-then") }

        // Wait past the original window to prove the cancelled timer never fires.
        await waitUntil({ false }, timeout: .milliseconds(150))

        #expect(recorder.performCount == 0)
        #expect(recorder.finishCount == 0)
        #expect(recorder.log == ["undo-then"])
        #expect(!coordinator.isPending(id))
    }

    @Test("A second beginDeletion for the same id cancels the first timer — one commit")
    func repeatedBeginCommitsOnce() async {
        let coordinator = DeletionCoordinator(grace: .milliseconds(30))
        let recorder = Recorder()
        let id = UUID()

        coordinator.beginDeletion(
            id,
            performDelete: { _ in recorder.record("perform-first") },
            didFinish: { _ in recorder.record("finish-first") })
        // Restart the window before the first timer could fire; its task must be
        // cancelled so only the second commit ever runs.
        coordinator.beginDeletion(
            id,
            performDelete: { _ in recorder.record("perform-second") },
            didFinish: { _ in recorder.record("finish-second") })

        #expect(coordinator.isPending(id))

        await waitUntil { recorder.finishCount == 1 }
        // Give any erroneously-live first timer ample time to also fire.
        await waitUntil({ false }, timeout: .milliseconds(120))

        #expect(recorder.performCount == 1)
        #expect(recorder.finishCount == 1)
        #expect(recorder.log == ["perform-second", "finish-second"])
        #expect(!coordinator.isPending(id))
    }
}
