import Foundation
import Testing

@testable import GanchoKit

@Suite("Link URL — what a dragged or shared link becomes")
struct LinkURLTests {
    @Test("A whole absolute URL passes through, trimmed")
    func absolute() {
        let text = "  https://www.example.com:8443/a%2Fb?q=a%26b#section-2 \n"
        #expect(
            LinkURL.resolve(text)?.absoluteString
                == "https://www.example.com:8443/a%2Fb?q=a%26b#section-2")
    }

    @Test("A link captured without a scheme gets the detector's")
    func schemeless() {
        let url = LinkURL.resolve("www.example.com/docs")
        #expect(url?.host() == "www.example.com")
        #expect(url?.scheme != nil)
    }

    @Test("Text that is not one whole web link resolves to nothing")
    func notALink() {
        #expect(LinkURL.resolve("see https://example.com") == nil)
        #expect(LinkURL.resolve("mailto:someone@example.com") == nil)
        #expect(LinkURL.resolve("") == nil)
        #expect(LinkURL.resolve("just words") == nil)
    }
}
