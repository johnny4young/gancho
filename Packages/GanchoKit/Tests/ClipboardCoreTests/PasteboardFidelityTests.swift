#if os(macOS)
    import Foundation
    import Testing

    @testable import ClipboardCore

    /// The format-negotiation order in `NSPasteboardReader.selectPayload` is a
    /// correctness contract: file refs > image (png > tiff) > RTF > HTML > text.
    /// A rich payload carries the pasteboard's plain string as-is — including
    /// `nil`/empty when none was offered; downstream reads that companion
    /// (never the RTF/HTML source), falling back to empty text. These pin both
    /// the order and the plain-companion pass-through so a regression fails here.
    @Suite("Pasteboard fidelity negotiation")
    struct PasteboardFidelityTests {
        private let png = Data([0x89, 0x50, 0x4E, 0x47])
        private let tiff = Data([0x49, 0x49, 0x2A])
        private let rtf = Data([0x7B, 0x5C])  // "{\"

        @Test("File references win over every other representation")
        func fileReferencesWin() {
            // A non-image path stays a reference; it must beat a co-present image.
            let url = URL(fileURLWithPath: "/tmp/doc.txt")
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [url], png: png, tiff: tiff, rtf: rtf, html: "<b>x</b>", plain: "x")
            #expect(payload == .fileReferences([url]))
        }

        @Test("PNG beats TIFF and every text form")
        func pngWins() {
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [], png: png, tiff: tiff, rtf: rtf, html: "<b>x</b>", plain: "x")
            #expect(payload == .image(data: png, typeIdentifier: "public.png"))
        }

        @Test("TIFF wins when there is no PNG")
        func tiffWins() {
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [], png: nil, tiff: tiff, rtf: rtf, html: "<b>x</b>", plain: "x")
            #expect(payload == .image(data: tiff, typeIdentifier: "public.tiff"))
        }

        @Test("RTF wins over HTML and text, and carries the plain companion")
        func rtfWinsWithPlain() {
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [], png: nil, tiff: nil, rtf: rtf, html: "<b>hi</b>", plain: "hi")
            #expect(payload == .richText(rtf: rtf, plainText: "hi"))
        }

        @Test("HTML wins over text, and carries the plain companion")
        func htmlWinsWithPlain() {
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [], png: nil, tiff: nil, rtf: nil, html: "<b>hi</b>", plain: "hi")
            #expect(payload == .html(source: "<b>hi</b>", plainText: "hi"))
        }

        @Test("A rich payload still wins with no plain companion — carried through as nil/empty")
        func richWithoutPlainCompanion() {
            // RTF/HTML present but the pasteboard offered no plain string, or an
            // empty one. The rich format still wins (it beats the absent text),
            // and the companion is passed through verbatim (nil stays nil, ""
            // stays "") — never synthesized by parsing the rich source.
            // Downstream (ClipItemFactory) reads `plainText ?? ""`, so nil and ""
            // are equivalent there; these pin that the reader doesn't drop or
            // fabricate the companion.
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: rtf, html: nil, plain: nil)
                    == .richText(rtf: rtf, plainText: nil))
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: rtf, html: nil, plain: "")
                    == .richText(rtf: rtf, plainText: ""))
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: nil, html: "<b>x</b>", plain: nil)
                    == .html(source: "<b>x</b>", plainText: nil))
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: nil, html: "<b>x</b>", plain: "")
                    == .html(source: "<b>x</b>", plainText: ""))
        }

        @Test("Plain text alone becomes a text payload")
        func plainTextAlone() {
            let payload = NSPasteboardReader.selectPayload(
                fileURLs: [], png: nil, tiff: nil, rtf: nil, html: nil, plain: "just text")
            #expect(payload == .text("just text"))
        }

        @Test("Nothing usable — empty plain and no rich forms — yields nil, not empty text")
        func emptyYieldsNil() {
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: nil, html: nil, plain: "") == nil)
            #expect(
                NSPasteboardReader.selectPayload(
                    fileURLs: [], png: nil, tiff: nil, rtf: nil, html: nil, plain: nil) == nil)
        }
    }
#endif
