#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import GanchoAI

    @Suite("On-device OCR")
    struct ImageTextExtractorTests {
        /// Renders text into a bitmap so the OCR has something REAL to read.
        @MainActor
        private func renderImage(text: String) -> Data {
            let size = NSSize(width: 400, height: 80)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            (text as NSString).draw(
                at: NSPoint(x: 20, y: 24),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black,
                ])
            image.unlockFocus()
            let tiff = image.tiffRepresentation!
            return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        }

        @Test("Reads rendered text; empty images yield nil")
        @MainActor
        func ocrRoundTrip() async throws {
            let extractor = ImageTextExtractor()
            let withText = renderImage(text: "GANCHO OCR 2026")
            let result = try await extractor.extractText(from: withText)
            #expect(result?.contains("GANCHO") == true, "got: \(result ?? "nil")")

            let blank = renderImage(text: "")
            #expect(try await extractor.extractText(from: blank) == nil)
        }
    }
#endif
