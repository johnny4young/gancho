#if os(iOS)
    import GanchoKit
    import UIKit

    /// iOS capture is INTENT-ONLY: the user taps a capture button, pastes
    /// via `UIPasteControl`, or shares through the extension. There is no
    /// background polling on iOS — by platform rule and by product promise
    /// (the App Review notes state it explicitly).
    @MainActor
    public final class IntentionalPasteboardSource {
        /// Metadata-only pasteboard facts — none of these read content, so
        /// none of them show the iOS paste banner or permission alert. The
        /// UI uses them to decide whether offering a capture is worth it
        /// BEFORE the user consents to a read.
        public struct ContentHints: Sendable, Equatable {
            /// Something is on the pasteboard (`hasStrings`/`hasURLs`/
            /// `hasImages` — flags, not content).
            public var hasContent: Bool
            /// detect-API verdicts (pattern present, value never exposed).
            public var probableWebURL: Bool
            public var probableWebSearch: Bool
            public var number: Bool
            /// The pasteboard's change counter — a metadata Int (no content
            /// read, no banner). Lets the UI tell "already saved this copy" from
            /// "a fresh copy" by comparing against the last captured count.
            public var changeCount: Int

            public init(
                hasContent: Bool = false, probableWebURL: Bool = false,
                probableWebSearch: Bool = false, number: Bool = false, changeCount: Int = 0
            ) {
                self.hasContent = hasContent
                self.probableWebURL = probableWebURL
                self.probableWebSearch = probableWebSearch
                self.number = number
                self.changeCount = changeCount
            }
        }

        public init() {}

        /// Detect-before-read, iOS edition: `has*` flags + `detectedPatterns`
        /// key paths. Safe to call on every foreground activation.
        public func hints() async -> ContentHints {
            let pasteboard = UIPasteboard.general
            var hints = ContentHints(
                hasContent: pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages,
                changeCount: pasteboard.changeCount)
            guard hints.hasContent else { return hints }

            let patterns = try? await pasteboard.detectedPatterns(for: [
                \.probableWebURL, \.probableWebSearch, \.number,
            ])
            hints.probableWebURL = patterns?.contains(\.probableWebURL) ?? false
            hints.probableWebSearch = patterns?.contains(\.probableWebSearch) ?? false
            hints.number = patterns?.contains(\.number) ?? false
            return hints
        }

        /// The intentional content read. iOS shows its paste transparency UI
        /// for this call (banner, or a one-time permission alert depending on
        /// the user's per-app "Paste from Other Apps" setting) — that is the
        /// honest contract of a user-initiated capture button. `UIPasteControl`
        /// is the no-alert path because the system itself mediates the tap.
        public func captureNow() -> PasteboardCapture? {
            let pasteboard = UIPasteboard.general
            if let image = pasteboard.image, let png = image.pngData() {
                return PasteboardCapture(payload: .image(data: png, typeIdentifier: "public.png"))
            }
            if let url = pasteboard.url {
                return PasteboardCapture(payload: .text(url.absoluteString))
            }
            if let string = pasteboard.string, !string.isEmpty {
                return PasteboardCapture(payload: .text(string))
            }
            return nil
        }
    }
#endif
