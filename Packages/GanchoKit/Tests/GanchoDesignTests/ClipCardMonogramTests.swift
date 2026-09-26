import Testing

@testable import GanchoDesign

@Suite("ClipCard — link tile monogram")
struct ClipCardMonogramTests {
    @Test("Host initial, uppercased, without a leading www.")
    func hostInitial() {
        #expect(ClipCard.linkMonogram(for: "https://gancho.app/docs/ocr") == "G")
        #expect(ClipCard.linkMonogram(for: "https://www.example.com/path?q=1") == "E")
        #expect(ClipCard.linkMonogram(for: "  http://127.0.0.1:8080/  ") == "1")
        #expect(ClipCard.linkMonogram(for: "https://ñandú.com.ar/menu") == "Ñ")
    }

    @Test("No host, or a host that starts with punctuation, means no monogram")
    func noHost() {
        #expect(ClipCard.linkMonogram(for: "not a url") == nil)
        #expect(ClipCard.linkMonogram(for: "mailto:someone@example.com") == nil)
        #expect(ClipCard.linkMonogram(for: "https://-dash.example") == nil)
        #expect(ClipCard.linkMonogram(for: "") == nil)
    }
}
