import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("ClipCard — sensitive content masking")
@MainActor
struct ClipCardPrivacyTests {
    @Test(
        "Sensitive rows hide titles, previews and thumbnails",
        arguments: [ClipContentKind.image, .text, .color])
    func sensitive(_ kind: ClipContentKind) {
        let item = ClipItem(
            kind: kind, title: "Synthetic private title", contentHash: "private", isSensitive: true)
        #expect(ClipCard(item: item).previewsHidden)
    }

    @Test("Secret kinds stay masked when a legacy sensitivity flag is missing")
    func secret() {
        let item = ClipItem(kind: .secret, contentHash: "legacy")
        #expect(ClipCard(item: item).previewsHidden)
    }

    @Test("Ordinary rows follow explicit private mode", arguments: [false, true])
    func ordinary(_ hidden: Bool) {
        let item = ClipItem(kind: .image, contentHash: "ordinary")
        #expect(ClipCard(item: item, previewsHidden: hidden).previewsHidden == hidden)
    }
}
