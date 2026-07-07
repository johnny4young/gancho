#if os(macOS)
    import AppKit
    import Foundation
    import UniformTypeIdentifiers

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
            return Self.selectPayload(
                fileURLs: fileURLs,
                png: pasteboard.data(forType: .png),
                tiff: pasteboard.data(forType: .tiff),
                rtf: pasteboard.data(forType: .rtf),
                html: pasteboard.string(forType: .html),
                plain: pasteboard.string(forType: .string))
        }

        /// The fidelity-negotiation decision, pure so the ordering is unit-tested
        /// without touching `NSPasteboard.general`. `readPayload()` gathers the
        /// raw representations and defers the choice here — the order is a
        /// correctness contract (rich formats must carry their plain companion so
        /// nothing downstream parses RTF/HTML), so a reorder must fail a test.
        static func selectPayload(
            fileURLs: [URL], png: Data?, tiff: Data?, rtf: Data?, html: String?, plain: String?
        ) -> PasteboardCapture.Payload? {
            if !fileURLs.isEmpty {
                // A single image file under the ceiling is inlined as bytes so
                // it syncs and pastes as the real image cross-device; a path
                // reference is meaningless on another Mac/phone. Multiple files
                // or large/non-image files keep the reference.
                if fileURLs.count == 1, let inlined = Self.inlinedImage(from: fileURLs[0]) {
                    return inlined
                }
                return .fileReferences(fileURLs)
            }
            if let png {
                return .image(data: png, typeIdentifier: "public.png")
            }
            if let tiff {
                return .image(data: tiff, typeIdentifier: "public.tiff")
            }
            if let rtf {
                return .richText(rtf: rtf, plainText: plain)
            }
            if let html {
                return .html(source: html, plainText: plain)
            }
            if let plain, !plain.isEmpty {
                return .text(plain)
            }
            return nil
        }

        /// Bytes ceiling for inlining a copied image file: big enough for
        /// screenshots and photos, small enough to keep iCloud sync cheap.
        /// Larger files fall back to a path reference.
        static let maxInlineFileBytes = 20 * 1024 * 1024

        /// An image file under the ceiling, read as bytes so it travels and
        /// pastes as the real image. Returns `nil` for non-images, oversize
        /// files, or unreadable paths — the caller then keeps the reference.
        static func inlinedImage(
            from url: URL, maxBytes: Int = maxInlineFileBytes
        ) -> PasteboardCapture.Payload? {
            guard url.isFileURL,
                let type = UTType(filenameExtension: url.pathExtension),
                type.conforms(to: .image)
            else { return nil }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size > maxBytes
            {
                return nil
            }
            guard let data = try? Data(contentsOf: url), data.count <= maxBytes else {
                return nil
            }
            return .image(data: data, typeIdentifier: type.identifier)
        }
    }
#endif
