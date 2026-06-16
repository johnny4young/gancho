import Foundation
import Testing

@testable import GanchoKit

@Suite("Widget entries — masking + deep links")
struct WidgetClipsTests {
    @Test("a sensitive clip is masked — no title, no preview, never the secret")
    func sensitiveIsMasked() {
        let secret = ClipItem(
            kind: .secret, title: "AWS key", preview: "AKIAIOSFODNN7EXAMPLE",
            contentHash: "h", isSensitive: true)
        let entry = WidgetClips.entries(from: [secret]).first

        #expect(entry?.displayText == WidgetClips.masked)
        #expect(entry?.title == "")
        #expect(entry?.isSensitive == true)
        // The raw secret must not leak through any field.
        #expect(entry?.displayText.contains("AKIA") == false)
    }

    @Test("a normal clip shows its preview")
    func normalShowsPreview() {
        let clip = ClipItem(
            kind: .text, title: "Note", preview: "hello world", contentHash: "h2")
        let entry = WidgetClips.entries(from: [clip]).first
        #expect(entry?.displayText == "hello world")
        #expect(entry?.title == "Note")
    }

    @Test("entries are capped at the limit")
    func respectsLimit() {
        let clips = (0..<10).map { ClipItem(preview: "c\($0)", contentHash: "h\($0)") }
        #expect(WidgetClips.entries(from: clips, limit: 3).count == 3)
    }

    @Test("deep link round-trips through the gancho://clip scheme")
    func deepLinkRoundTrip() throws {
        let id = UUID()
        let entry = WidgetClipEntry(
            id: id, title: "t", displayText: "d", kind: .text, isSensitive: false)
        let url = try #require(entry.deepLinkURL)
        #expect(url.absoluteString == "gancho://clip/\(id.uuidString)")
        #expect(WidgetClips.clipID(fromDeepLink: url) == id)
    }

    @Test("foreign or malformed URLs are rejected")
    func rejectsForeignURLs() throws {
        #expect(
            WidgetClips.clipID(fromDeepLink: try #require(URL(string: "https://evil.com/clip/x")))
                == nil)
        #expect(
            WidgetClips.clipID(fromDeepLink: try #require(URL(string: "gancho://settings")))
                == nil)
    }
}
