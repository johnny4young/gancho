#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import Testing

    @testable import ClipboardCore
    @testable import GanchoKit

    /// Records writes; thread-safe because restore happens from a Task.
    private final class SpyWriter: PasteboardWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var _writes: [(content: ClipContent, plain: Bool)] = []
        var current: String?

        var writes: [(content: ClipContent, plain: Bool)] {
            lock.withLock { _writes }
        }

        func write(_ content: ClipContent, asPlainText: Bool) {
            lock.withLock { _writes.append((content, asPlainText)) }
        }

        func currentText() -> String? {
            lock.withLock { current }
        }
    }

    private final class SpyPoster: KeyEventPosting, @unchecked Sendable {
        private let lock = NSLock()
        private var _posted: [CGKeyCode] = []

        var posted: [CGKeyCode] {
            lock.withLock { _posted }
        }

        func postCommandKey(keyCode: CGKeyCode) {
            lock.withLock { _posted.append(keyCode) }
        }
    }

    @MainActor
    private func makeService(
        writer: SpyWriter, poster: SpyPoster, trusted: Bool, keyCode: CGKeyCode = 9
    ) -> PasteBackService {
        PasteBackService(
            writer: writer, poster: poster,
            keyCodeForV: { keyCode },
            isAccessibilityTrusted: { trusted })
    }

    @Suite("PasteBackService — synthetic ⌘V")
    @MainActor
    struct PasteBackServiceTests {

        @Test("Writes the clip and posts ⌘V with the layout-resolved keycode")
        func pastesWithLayoutKeycode() {
            let writer = SpyWriter()
            let poster = SpyPoster()
            // Dvorak-QWERTY⌘ resolves V to a non-QWERTY code — inject 47.
            let service = makeService(
                writer: writer, poster: poster, trusted: true, keyCode: 47)

            let outcome = service.paste(.text("hello"))

            #expect(outcome == .pasted)
            #expect(writer.writes.map(\.content) == [.text("hello")])
            #expect(poster.posted == [47])
        }

        @Test("Missing Accessibility degrades to copied-only, no event posted")
        func accessibilityFallback() {
            let writer = SpyWriter()
            let poster = SpyPoster()
            let service = makeService(writer: writer, poster: poster, trusted: false)

            let outcome = service.paste(.text("hello"))

            #expect(outcome == .copiedOnly)
            #expect(writer.writes.count == 1, "content must still be on the pasteboard")
            #expect(poster.posted.isEmpty)
        }

        @Test("Plain-text path forwards the flag to the writer (⌥Enter)")
        func plainTextFlag() {
            let writer = SpyWriter()
            let poster = SpyPoster()
            let service = makeService(writer: writer, poster: poster, trusted: true)

            service.paste(.text("rich"), asPlainText: true)

            #expect(writer.writes.first?.plain == true)
        }

        @Test("Restore-previous re-writes the prior clipboard after the paste")
        func restorePrevious() async {
            let writer = SpyWriter()
            writer.current = "what was there before"
            let poster = SpyPoster()
            let service = makeService(writer: writer, poster: poster, trusted: true)

            service.paste(.text("new content"), restorePrevious: true)

            // The restoration write lands after ~300ms.
            for _ in 0..<200 where writer.writes.count < 2 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(
                writer.writes.map(\.content) == [
                    .text("new content"), .text("what was there before")
                ])
        }

        @Test("File references go through as file content for writeObjects")
        func fileReferences() {
            let writer = SpyWriter()
            let poster = SpyPoster()
            let service = makeService(writer: writer, poster: poster, trusted: true)

            let outcome = service.paste(.fileReferences(["/tmp/a.txt", "/tmp/b.txt"]))

            #expect(outcome == .pasted)
            #expect(
                writer.writes.map(\.content) == [.fileReferences(["/tmp/a.txt", "/tmp/b.txt"])])
        }
    }

    /// Real-pasteboard marker check — opt-in only: it overwrites the user's
    /// clipboard, which does not belong in the default suite.
    @Suite(
        "SystemPasteboardWriter — marker discipline",
        .enabled(
            if: ProcessInfo.processInfo.environment["GANCHO_PASTEBOARD_INTEGRATION"] == "1"))
    @MainActor
    struct SystemPasteboardWriterTests {
        @Test("Every write carries the self-write marker (no re-capture loops)")
        func markerAlwaysPresent() {
            let writer = SystemPasteboardWriter()
            writer.write(.text("gancho paste-back probe"), asPlainText: false)

            let types = NSPasteboard.general.types ?? []
            #expect(types.contains(MacPasteboardMonitor.selfWriteMarker))
            #expect(NSPasteboard.general.string(forType: .string) == "gancho paste-back probe")
        }
    }
#endif
