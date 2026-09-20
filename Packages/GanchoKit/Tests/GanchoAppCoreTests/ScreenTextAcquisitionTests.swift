import CoreGraphics
import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Screen OCR acquisition privacy", .timeLimit(.minutes(1)))
@MainActor struct ScreenTextAcquisitionTests {
    @Test func allowedSelectionCapturesOnlyItsRegion() async throws {
        let probe = Probe()
        let result = try await ScreenTextAcquisition.image(
            select: { probe.region }, isAllowed: { true }, settle: {},
            capture: { await probe.capture($0) })
        #expect(result == Data([1]))
        #expect(probe.regions == [probe.region])
    }

    @Test func privateModeBeforeSelectionDoesNotOpenSelector() async {
        let probe = Probe()
        await #expect(throws: CancellationError.self) {
            try await ScreenTextAcquisition.image(
                select: {
                    probe.selected = true
                    return probe.region
                },
                isAllowed: { false },
                settle: {},
                capture: { await probe.capture($0) })
        }
        #expect(!probe.selected)
        #expect(probe.regions.isEmpty)
    }

    @Test func privateModeDuringSelectionPreventsCaptureWithoutRelyingOnCancellation()
        async throws
    {
        let probe = Probe()
        let task = probe.start()
        try await probe.waitForSelection()
        probe.allowed = false
        probe.finishSelection()
        await expectCancelled(task)
        #expect(probe.regions.isEmpty)
    }

    @Test func cancellingOnPrivateModeCannotBeUndoneByResumingCapture() async throws {
        let probe = Probe()
        let task = probe.start()
        try await probe.waitForSelection()
        probe.allowed = false
        task.cancel()
        probe.allowed = true
        // Model an uncooperative selector that still returns the old region.
        probe.finishSelection()
        await expectCancelled(task)
        #expect(probe.regions.isEmpty)
    }

    @Test func privateModeDuringCompositorWaitPreventsCapture() async {
        let probe = Probe()
        await #expect(throws: CancellationError.self) {
            try await ScreenTextAcquisition.image(
                select: { probe.region }, isAllowed: { probe.allowed },
                settle: { probe.allowed = false }, capture: { await probe.capture($0) })
        }
        #expect(probe.regions.isEmpty)
    }

    @Test func emptySelectionDoesNotCapture() async {
        let probe = Probe()
        await #expect(throws: CancellationError.self) {
            try await ScreenTextAcquisition.image(
                select: { nil }, isAllowed: { true }, settle: {},
                capture: { await probe.capture($0) })
        }
        #expect(probe.regions.isEmpty)
    }

    @Test func privateModeDuringCaptureDiscardsTheImage() async {
        let probe = Probe()
        await #expect(throws: CancellationError.self) {
            try await ScreenTextAcquisition.image(
                select: { probe.region }, isAllowed: { probe.allowed }, settle: {},
                capture: { region in
                    await MainActor.run {
                        probe.allowed = false
                        return probe.capture(region)
                    }
                })
        }
        #expect(probe.regions.count == 1)
    }

    private func expectCancelled(_ task: Task<Data, any Error>) async {
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @MainActor private final class Probe {
        let region = CGRect(x: -200, y: 50, width: 100, height: 60)
        var allowed = true
        var selected = false
        var regions: [CGRect] = []
        var selection: CheckedContinuation<CGRect?, Never>?

        func start() -> Task<Data, any Error> {
            Task {
                try await ScreenTextAcquisition.image(
                    select: { await withCheckedContinuation { self.selection = $0 } },
                    isAllowed: { self.allowed }, settle: {},
                    capture: { await self.capture($0) })
            }
        }

        /// Bounded on purpose. An unbounded spin turns a regression that
        /// stops the selector from ever being reached — an eligibility check
        /// moved ahead of `select()`, say — into a test that hangs the main
        /// actor instead of reporting it.
        func waitForSelection() async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while selection == nil {
                guard ContinuousClock.now < deadline else { throw SelectorNeverReached() }
                await Task.yield()
            }
        }

        func finishSelection() {
            selection?.resume(returning: region)
            selection = nil
        }

        func capture(_ region: CGRect) -> Data {
            regions.append(region)
            return Data([1])
        }
    }

    private struct SelectorNeverReached: Error {}
}
