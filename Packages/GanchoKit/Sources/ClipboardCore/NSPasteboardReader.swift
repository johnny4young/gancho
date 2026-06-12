#if os(macOS)
    import AppKit
    import Foundation

    /// `PasteboardReading` over `NSPasteboard.general`.
    ///
    /// Stateless by design: every call re-resolves the general pasteboard, so
    /// the struct is safely `Sendable` and `readPayload()` can run off the
    /// main thread — required because a full read may block for seconds under
    /// the pasteboard-privacy "Ask" permission. Metadata calls (`changeCount`,
    /// `types`) never enter that flow.
    public struct NSPasteboardReader: PasteboardReading {
        public init() {}

        public func currentChangeCount() -> Int {
            NSPasteboard.general.changeCount
        }

        public func currentTypes() -> Set<String> {
            Set((NSPasteboard.general.types ?? []).map(\.rawValue))
        }

        /// Reads by descending fidelity: file references > image > RTF >
        /// HTML > plain text. Rich-text payloads carry the plain companion
        /// so classification and search never parse the rich format.
        public func readPayload() -> PasteboardCapture.Payload? {
            let pasteboard = NSPasteboard.general

            let fileURLs = (pasteboard.pasteboardItems ?? []).compactMap { item -> URL? in
                guard let raw = item.string(forType: .fileURL) else { return nil }
                return URL(string: raw)
            }
            if !fileURLs.isEmpty {
                return .fileReferences(fileURLs)
            }

            if let png = pasteboard.data(forType: .png) {
                return .image(data: png, typeIdentifier: "public.png")
            }
            if let tiff = pasteboard.data(forType: .tiff) {
                return .image(data: tiff, typeIdentifier: "public.tiff")
            }

            let plain = pasteboard.string(forType: .string)
            if let rtf = pasteboard.data(forType: .rtf) {
                return .richText(rtf: rtf, plainText: plain)
            }
            if let html = pasteboard.string(forType: .html) {
                return .html(source: html, plainText: plain)
            }
            if let plain, !plain.isEmpty {
                return .text(plain)
            }
            return nil
        }
    }
#endif
