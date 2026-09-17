#if os(macOS)
    import AppKit
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers
    import Testing

    @testable import GanchoAI

    @Suite("On-device OCR")
    struct ImageTextExtractorTests {
        /// Renders text into a bitmap so the OCR has something REAL to read.
        @MainActor
        private func renderImage(text: String) -> Data {
            let size = NSSize(width: 800, height: 160)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            (text as NSString).draw(
                in: NSRect(x: 20, y: 24, width: 760, height: 120),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black
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
        @Test("Reads accents and multiple lines without an Apple Intelligence model")
        @MainActor func multilingual() async throws {
            let text = try await ImageTextExtractor().extractText(
                from: renderImage(text: "Información útil\nHello Gancho"))
            #expect(text?.contains("Información") == true)
            #expect(text?.contains("Hello Gancho") == true)
        }

        @Test("Invalid bytes are distinguishable from a valid blank image")
        func invalidImage() async {
            await #expect(throws: ImageTextExtractionError.self) {
                try await ImageTextExtractor().extractText(from: Data([0, 1, 2]))
            }
        }

        @Test("Lines carry top-left normalized regions in reading order")
        @MainActor func regions() async throws {
            let lines = try await ImageTextExtractor().recognizeLines(
                in: renderImage(text: "Primera línea arriba\nSegunda línea abajo"))
            #expect(lines.count >= 2, "got: \(lines.map(\.text))")
            for line in lines {
                let box = try #require(line.box)
                #expect(box.minX >= 0 && box.maxX <= 1 && box.minY >= 0 && box.maxY <= 1)
                #expect(box.width > 0 && box.height > 0)
            }
            let first = try #require(lines.first?.box)
            let last = try #require(lines.last?.box)
            #expect(first.minY < last.minY, "top-left origin: the first line sits higher")
        }

        @Test("Reading order sorts rows top-down and columns left-right")
        func readingOrder() {
            let lines = [
                RecognizedTextLine(
                    text: "right-top", box: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.1)),
                RecognizedTextLine(
                    text: "bottom", box: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1)),
                RecognizedTextLine(
                    text: "left-top", box: CGRect(x: 0.1, y: 0.12, width: 0.3, height: 0.1)),
                RecognizedTextLine(text: "stored", box: nil)
            ]
            #expect(
                ImageTextExtractor.readingOrder(lines).map(\.text)
                    == ["left-top", "right-top", "bottom", "stored"])
        }

        @Test("Honors upside-down EXIF image orientation")
        @MainActor func orientation() async throws {
            let data = renderImage(text: "GANCHO ORIENTATION")
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let original = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let context = try #require(
                CGContext(
                    data: nil, width: original.width, height: original.height,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: CGFloat(original.width), y: CGFloat(original.height))
            context.rotate(by: .pi)
            context.draw(
                original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
            let flipped = try #require(context.makeImage())
            let output = NSMutableData()
            let destination = try #require(
                CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, 1, nil)
            )
            CGImageDestinationAddImage(
                destination, flipped, [kCGImagePropertyOrientation: 3] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            let text = try await ImageTextExtractor().extractText(from: output as Data)
            #expect(text?.contains("GANCHO ORIENTATION") == true)
        }
    }
#endif
