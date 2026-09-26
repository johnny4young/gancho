import Testing

@testable import GanchoDesign

@Suite("ClipLinkParts — lossless local link presentation")
struct ClipLinkPartsTests {
    @Test(
        "The decorative host does not replace the original URL",
        arguments: [
            "https://www.example.com/docs/ocr?lang=es",
            "http://www.example.com:8080/a%2Fb?q=a%26b#section-2",
            "https://gancho.app/", "https://gancho.app", "https://example.com/#",
            "https://example.com/?", "https://example.com/caf%C3%A9"
        ])
    func preservesURL(_ url: String) throws {
        let parts = try #require(ClipLinkParts(text: "  \(url)\n"))
        #expect(parts.text == url)
        #expect(!parts.host.hasPrefix("www."))
    }

    @Test("Host prefixes are case insensitive")
    func host() {
        #expect(ClipLinkParts(text: "https://WWW.example.com")?.host == "example.com")
    }

    @Test(
        "Invalid or oversized input uses the bounded plain-text fallback",
        arguments: [
            "not a url", "mailto:someone@example.com", "", "https://www.",
            "https://example.com/" + String(repeating: "a", count: 4_000)
        ])
    func fallback(_ text: String) {
        #expect(ClipLinkParts(text: text) == nil)
    }
}
