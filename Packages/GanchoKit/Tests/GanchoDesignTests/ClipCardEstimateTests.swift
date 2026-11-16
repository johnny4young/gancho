import CoreGraphics
import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("Library card height estimate — fixed per kind, images by proportion")
struct ClipCardEstimateTests {
    private func height(
        _ kind: ClipContentKind, _ preview: String, title: String = "", width: CGFloat = 210,
        sensitive: Bool = false, info: ClipImageInfo? = nil, hidden: Bool = false,
        boards: Bool = false
    ) -> CGFloat {
        ClipCardEstimate.height(
            of: ClipItem(
                kind: kind, title: title, preview: preview, isSensitive: sensitive,
                imageInfo: info),
            columnWidth: width, previewsHidden: hidden, hasBoards: boards)
    }

    @Test("A swatch, a link, a value and code have fixed specimens over their footer")
    func fixedKinds() {
        #expect(height(.color, "#FF6B4A") == CGFloat(112 + 35))
        #expect(height(.color, "#FF6B4A", title: "Launch coral") == CGFloat(112 + 56))
        #expect(height(.url, "https://gancho.app/launch/press-kit") == CGFloat(60 + 35))
        #expect(height(.url, "https://gancho.app") == CGFloat(36 + 35))
        #expect(height(.uuid, "123E4567-E89B-12D3-A456-426614174000") == CGFloat(32 + 35))
        #expect(height(.code, "let a = 1\nlet b = 2\nlet c = 3") == CGFloat(24 + 45 + 35))
        let long = Array(repeating: "x", count: 20).joined(separator: "\n")
        #expect(height(.code, long) == CGFloat(24 + 9 * 15 + 35))
    }

    @Test("An image follows its recorded proportions, within the card's limits")
    func images() {
        #expect(ClipCardEstimate.imageHeight(for: .init(width: 2400, height: 1350)) == 118.125)
        #expect(ClipCardEstimate.imageHeight(for: .init(width: 100, height: 4000)) == 260)
        #expect(ClipCardEstimate.imageHeight(for: .init(width: 4000, height: 100)) == 96)
        #expect(ClipCardEstimate.imageHeight(for: nil) == 140)
        #expect(ClipCardEstimate.imageHeight(for: .init(width: 0, height: 10)) == 140)
        let info = ClipImageInfo(width: 2400, height: 1350)
        #expect(height(.image, "Image (1.8 MB)", info: info) == CGFloat(118.125 + 56))
        // The height never follows the column, so a scroller cannot change it.
        #expect(height(.image, "", width: 480, info: info) == height(.image, "", info: info))
    }

    @Test("Prose wraps: a narrower column is taller, and both sizes stop at their line limit")
    func prose() {
        #expect(height(.text, "Hello") == CGFloat(12 + 25 + 35))
        let eighty = String(repeating: "a", count: 80)
        #expect(height(.text, eighty) == CGFloat(12 + 5 * 25 + 35))
        #expect(height(.text, eighty, width: 400) == CGFloat(12 + 3 * 25 + 35))
        let hundredTwenty = String(repeating: "a", count: 120)
        #expect(height(.text, hundredTwenty) == CGFloat(12 + 5 * 17 + 35))
        #expect(height(.text, String(repeating: "a\n", count: 30)) == CGFloat(12 + 8 * 17 + 35))
        #expect(height(.richText, "Hello", title: "Greeting") == CGFloat(12 + 25 + 56))
    }

    @Test("A protected clip and Private Mode never size by content; boards add a row")
    func maskedAndBoards() {
        let secret = height(.secret, "●●●● 4Q2v")
        #expect(secret == CGFloat(32 + 56))
        #expect(height(.text, String(repeating: "a", count: 120), sensitive: true) == secret)
        #expect(
            height(.image, "", info: .init(width: 10, height: 900), hidden: true)
                == CGFloat(37 + 37))
        #expect(height(.color, "#FF6B4A", boards: true) == CGFloat(112 + 35 + 22))
    }
}
