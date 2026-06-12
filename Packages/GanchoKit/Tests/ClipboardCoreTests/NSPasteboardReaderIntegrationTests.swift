#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import ClipboardCore

    /// Integration round-trips against the REAL general pasteboard.
    ///
    /// Opt-in only (`GANCHO_PASTEBOARD_INTEGRATION=1 make test`): it
    /// overwrites the user's clipboard and depends on a logged-in session,
    /// so it must never run in the default suite or on CI runners.
    @Suite(
        "NSPasteboardReader — real pasteboard integration",
        .enabled(if: ProcessInfo.processInfo.environment["GANCHO_PASTEBOARD_INTEGRATION"] == "1"),
        .serialized)
    @MainActor
    struct NSPasteboardReaderIntegrationTests {
        let reader = NSPasteboardReader()

        @Test("Plain text round-trips")
        func text() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("integration text", forType: .string)

            #expect(reader.currentTypes().contains("public.utf8-plain-text"))
            #expect(reader.readPayload() == .text("integration text"))
        }

        @Test("PNG data round-trips as an image payload")
        func image() throws {
            // 1×1 transparent PNG.
            let png = try #require(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
                ))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)

            #expect(reader.readPayload() == .image(data: png, typeIdentifier: "public.png"))
        }

        @Test("File URLs round-trip as file references")
        func fileReferences() throws {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gancho-integration.txt")
            try Data("payload".utf8).write(to: url)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])

            guard case .fileReferences(let urls)? = reader.readPayload() else {
                Issue.record("expected fileReferences payload")
                return
            }
            #expect(urls.map(\.standardizedFileURL.path) == [url.standardizedFileURL.path])
        }

        @Test("RTF rides with its plain-text companion")
        func richText() throws {
            let rtf = try #require(
                NSAttributedString(string: "rich").rtf(
                    from: NSRange(location: 0, length: 4)))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(rtf, forType: .rtf)
            pasteboard.setString("rich", forType: .string)

            #expect(reader.readPayload() == .richText(rtf: rtf, plainText: "rich"))
        }

        @Test("Concealed marker is visible to the veto without reading content")
        func concealedTypeVisible() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.declareTypes(
                [.string, NSPasteboard.PasteboardType(SensitivePasteboardTypes.concealed)],
                owner: nil)
            pasteboard.setString("secret", forType: .string)

            #expect(reader.currentTypes().contains(SensitivePasteboardTypes.concealed))
            #expect(
                !SensitivePasteboardTypes.captureVeto.isDisjoint(with: reader.currentTypes()),
                "the monitor's veto would fire on this snapshot")
        }
    }
#endif
