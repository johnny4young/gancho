import Testing

@testable import GanchoDesign

@Suite("ClipLinkParts — local host and path for link heroes")
struct ClipLinkPartsTests {
    @Test("Host without www., path with its query")
    func hostAndPath() {
        let parts = ClipLinkParts(text: "https://www.example.com/docs/ocr?lang=es")
        #expect(parts?.host == "example.com")
        #expect(parts?.path == "/docs/ocr?lang=es")
    }

    @Test("A bare origin has an empty path, whether or not it ends in a slash")
    func bareOrigin() {
        #expect(ClipLinkParts(text: "https://gancho.app")?.path.isEmpty == true)
        #expect(ClipLinkParts(text: "https://gancho.app/")?.path.isEmpty == true)
        #expect(ClipLinkParts(text: "  https://gancho.app  ")?.host == "gancho.app")
    }

    @Test("Text that is not a URL with a host yields nothing")
    func noHost() {
        #expect(ClipLinkParts(text: "not a url") == nil)
        #expect(ClipLinkParts(text: "mailto:someone@example.com") == nil)
        #expect(ClipLinkParts(text: "") == nil)
    }
}
