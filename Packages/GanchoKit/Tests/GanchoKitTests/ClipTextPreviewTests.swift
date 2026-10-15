import GanchoKit
import Testing

@Suite("Bounded clip text previews")
struct ClipTextPreviewTests {
    @Test("Short and exact-length previews are unchanged")
    func unchangedText() {
        #expect(ClipTextPreview.truncated("", limit: 0).isEmpty)
        #expect(ClipTextPreview.truncated("Synthetic", limit: 20) == "Synthetic")
        #expect(ClipTextPreview.truncated("Synthetic", limit: 9) == "Synthetic")
    }

    @Test("Truncation preserves composed characters and leaves stored text intact")
    func unicodeBoundary() {
        let text = "👨‍👩‍👧‍👦e\u{301}🇨🇴tail"
        #expect(ClipTextPreview.truncated(text, limit: 3) == "👨‍👩‍👧‍👦e\u{301}🇨🇴\n…")
        #expect(ClipTextPreview.truncated(text, limit: 0) == "\n…")
        #expect(text.hasSuffix("tail"))
    }

    @Test("Large documents produce a bounded preview")
    func largeDocument() {
        let text = String(repeating: "Synthetic document. ", count: 100_000)
        let preview = ClipTextPreview.truncated(text, limit: 4_000)
        #expect(preview.count == 4_002)
        #expect(preview.hasSuffix("\n…"))
    }
}
