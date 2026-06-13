#if os(macOS)
    import AppKit
    import Foundation
    import GanchoKit
    import Sauce

    /// How a paste-back attempt ended — the UI picks the toast from this.
    public enum PasteBackOutcome: Sendable, Equatable {
        /// Content written AND the synthetic ⌘V was posted.
        case pasted
        /// Content written, but Accessibility permission is missing — the
        /// user pastes manually ("copied, paste with ⌘V").
        case copiedOnly
    }

    /// Seams injected for tests: writing the pasteboard, posting the key
    /// event, resolving the layout-aware keycode, and the permission check.
    public protocol PasteboardWriting: Sendable {
        /// Writes content WITH Gancho's self-write marker (anti re-capture).
        func write(_ content: ClipContent, asPlainText: Bool)
        /// Snapshot of the current general-pasteboard text for restoration.
        func currentText() -> String?
    }

    public protocol KeyEventPosting: Sendable {
        /// Posts ⌘+keyCode down/up to the session event tap.
        func postCommandKey(keyCode: CGKeyCode)
    }

    /// Pastes a stored clip into the frontmost app: write to the pasteboard
    /// (marked as ours) and synthesize ⌘V. Requires Accessibility; degrades
    /// to copy-only with a clear outcome when the permission is missing.
    ///
    /// Privacy-spike note: the synthetic ⌘V makes the TARGET app read the
    /// pasteboard; under future OS enforcement that read is governed by the
    /// target's own permission. The copy-only fallback is therefore also the
    /// long-term safety net, not just the no-permission path.
    @MainActor
    public final class PasteBackService {
        private let writer: any PasteboardWriting
        private let poster: any KeyEventPosting
        private let keyCodeForV: () -> CGKeyCode
        private let isAccessibilityTrusted: () -> Bool

        public init(
            writer: any PasteboardWriting = SystemPasteboardWriter(),
            poster: any KeyEventPosting = SessionTapKeyEventPoster(),
            keyCodeForV: @escaping () -> CGKeyCode = {
                // Layout-aware: "V" is not at the QWERTY position on Dvorak;
                // Sauce resolves the CURRENT layout (Dvorak-QWERTY⌘ case).
                Sauce.shared.keyCode(for: .v)
            },
            isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
        ) {
            self.writer = writer
            self.poster = poster
            self.keyCodeForV = keyCodeForV
            self.isAccessibilityTrusted = isAccessibilityTrusted
        }

        /// Writes the clip and pastes it into the frontmost app.
        /// - Parameters:
        ///   - asPlainText: ⌥Enter path — strips rich representations.
        ///   - restorePrevious: restore what was on the pasteboard before,
        ///     after the target app had time to read (user-opt-in setting).
        @discardableResult
        public func paste(
            _ content: ClipContent,
            asPlainText: Bool = false,
            restorePrevious: Bool = false
        ) -> PasteBackOutcome {
            let previous = restorePrevious ? writer.currentText() : nil
            writer.write(content, asPlainText: asPlainText)

            guard isAccessibilityTrusted() else {
                return .copiedOnly
            }
            poster.postCommandKey(keyCode: keyCodeForV())

            if let previous {
                // Give the target app one beat to consume the paste before
                // restoring (300ms covers slow electron apps comfortably).
                let writer = self.writer
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    writer.write(.text(previous), asPlainText: true)
                }
            }
            return .pasted
        }
    }

    /// Real pasteboard writer. Every write carries the self-write marker so
    /// the capture monitor never re-captures Gancho's own paste-backs.
    public struct SystemPasteboardWriter: PasteboardWriting {
        public init() {}

        public func write(_ content: ClipContent, asPlainText: Bool) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("1", forType: MacPasteboardMonitor.selfWriteMarker)
            switch content {
            case .text(let text):
                pasteboard.setString(text, forType: .string)
            case .binary(let data, let typeIdentifier):
                if asPlainText {
                    // Rich → plain on request: RTF/HTML degrade via their
                    // string; raw images have no plain form and paste as-is.
                    if let string = String(data: data, encoding: .utf8) {
                        pasteboard.setString(string, forType: .string)
                        return
                    }
                }
                pasteboard.setData(
                    data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            case .fileReferences(let paths):
                // writeObjects is what makes multi-file paste work in Finder.
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
                pasteboard.setString("1", forType: MacPasteboardMonitor.selfWriteMarker)
            }
        }

        public func currentText() -> String? {
            NSPasteboard.general.string(forType: .string)
        }
    }

    /// Posts to `.cgSessionEventTap` — the level that reaches sandboxed and
    /// secure-input-aware targets (Mac App Store compatible; prior art:
    /// Paste, PastePal).
    public struct SessionTapKeyEventPoster: KeyEventPosting {
        public init() {}

        public func postCommandKey(keyCode: CGKeyCode) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cgSessionEventTap)
            up?.post(tap: .cgSessionEventTap)
        }
    }
#endif
