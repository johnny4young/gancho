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
        #expect(entry?.title.isEmpty == true)
        #expect(entry?.isSensitive == true)
        // The raw secret must not leak through any field.
        #expect(entry?.displayText.contains("AKIA") == false)
    }

    @Test("an inherently secret kind is masked even if its flag is missing")
    func secretKindIsMaskedDefensively() {
        let secret = ClipItem(
            kind: .secret, title: "AWS key", preview: "AKIAIOSFODNN7EXAMPLE",
            contentHash: "legacy", isSensitive: false)
        let entry = WidgetClips.entries(from: [secret]).first

        #expect(entry?.displayText == WidgetClips.masked)
        #expect(entry?.title.isEmpty == true)
        #expect(entry?.isSensitive == true)
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

    @Test("keyboard list puts pins first and de-dupes them out of recent")
    func keyboardOrdering() {
        let pinned = ClipItem(kind: .text, preview: "pinned one", contentHash: "p1", isPinned: true)
        let alsoRecent = pinned  // the pinned clip is also in the recent feed
        let fresh = ClipItem(kind: .text, preview: "fresh two", contentHash: "r2")

        let entries = KeyboardClips.ordered(pinned: [pinned], recent: [alsoRecent, fresh])
        #expect(entries.map(\.id) == [pinned.id, fresh.id])  // pin first, no duplicate
    }

    @Test("keyboard list excludes sensitive clips entirely")
    func keyboardExcludesSensitive() {
        let secret = ClipItem(
            kind: .secret, preview: "AKIA-secret", contentHash: "s", isSensitive: true)
        let normal = ClipItem(kind: .text, preview: "ok to paste", contentHash: "n")
        let entries = KeyboardClips.ordered(pinned: [], recent: [secret, normal])
        #expect(entries.map(\.id) == [normal.id])  // the secret is not offered
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
