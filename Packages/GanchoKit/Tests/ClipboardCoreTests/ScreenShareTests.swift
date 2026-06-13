#if os(macOS)
    import Foundation
    import Testing

    @testable import ClipboardCore

    @Suite("Screen-share auto-pause")
    @MainActor
    struct ScreenShareTests {
        @Test("Detector flags known share helpers, ignores idle conferencing apps")
        func detectorHeuristics() {
            let sharing = ScreenShareDetector(runningProcessNames: {
                ["Finder", "zoom.us", "CptHost"]
            })
            #expect(sharing.isScreenSharePresumed())

            let idle = ScreenShareDetector(runningProcessNames: {
                ["Finder", "zoom.us", "Microsoft Teams"]
            })
            #expect(!idle.isScreenSharePresumed(), "an OPEN conferencing app is not a share")
        }

        @Test("Share pause stops capture and never backfills on resume")
        func sharePauseNoBackfill() async {
            let pasteboard = FakePasteboard()
            let monitor = MacPasteboardMonitor(
                reader: pasteboard, activity: FakeActivity(), frontmostApp: { nil })
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            monitor.pausedForScreenShare = true
            _ = monitor.tick()
            #expect(monitor.status == .pausedByScreenShare)

            pasteboard.write(.text("visible to the meeting"), types: ["public.utf8-plain-text"])
            _ = monitor.tick()
            try? await Task.sleep(for: .milliseconds(60))
            #expect(captures.isEmpty)
            #expect(pasteboard.readCalls == 0)

            monitor.pausedForScreenShare = false
            _ = monitor.tick()
            try? await Task.sleep(for: .milliseconds(80))
            #expect(captures.isEmpty, "share-time copies must never backfill")
            #expect(monitor.status == .running)
        }
    }
#endif
