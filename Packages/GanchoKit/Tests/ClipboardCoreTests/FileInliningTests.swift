#if os(macOS)
    import Foundation
    import Testing

    @testable import ClipboardCore

    /// A copied image file should travel as real bytes (so it syncs and pastes
    /// as the image cross-device), while other files stay path references.
    @Suite("File inlining — image files become real bytes")
    struct FileInliningTests {
        /// 1×1 transparent PNG.
        private let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        )!

        private func tempFile(_ name: String, _ data: Data) throws -> URL {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("gancho-inline-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        @Test("a small image file is inlined as image bytes")
        func inlinesImage() throws {
            let url = try tempFile("shot.png", png)
            guard case .image(let data, let type)? = NSPasteboardReader.inlinedImage(from: url)
            else {
                Issue.record("expected an image payload")
                return
            }
            #expect(data == png)
            #expect(type == "public.png")
        }

        @Test("a non-image file stays a reference (nil)")
        func keepsNonImage() throws {
            let url = try tempFile("notes.txt", Data("hello".utf8))
            #expect(NSPasteboardReader.inlinedImage(from: url) == nil)
        }

        @Test("an image over the ceiling falls back to a reference (nil)")
        func rejectsOversize() throws {
            let url = try tempFile("shot.png", png)
            #expect(NSPasteboardReader.inlinedImage(from: url, maxBytes: 1) == nil)
        }
    }
#endif
