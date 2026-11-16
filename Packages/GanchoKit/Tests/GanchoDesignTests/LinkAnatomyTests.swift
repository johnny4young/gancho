import Testing

@testable import GanchoDesign

@Suite("LinkAnatomy — a link's parts, in place")
struct LinkAnatomyTests {
    private func parts(_ url: String) -> [String]? {
        LinkAnatomy(text: url)?.segments.map { "\($0.part.rawValue)=\($0.text)" }
    }

    @Test("Every part is found with its delimiters")
    func fullLink() throws {
        let url = "https://gancho.app/launch/press-kit?ref=newsletter&v=1.0#downloads"
        let anatomy = try #require(LinkAnatomy(text: url))
        #expect(
            parts(url) == [
                "scheme=https://", "host=gancho.app", "path=/launch/press-kit",
                "query=?ref=newsletter&v=1.0", "fragment=#downloads"
            ])
        #expect(
            anatomy.parameters == [
                .init(name: "ref", value: "newsletter"), .init(name: "v", value: "1.0")
            ])
        #expect(anatomy.fragment == "downloads")
        #expect(anatomy.path == "/launch/press-kit")
    }

    @Test(
        "The segments tile the trimmed original, whatever it holds",
        arguments: [
            "https://www.example.com:8443/a%2Fb?q=a%26b#section-2",
            "https://user:secret@example.com:8080/private", "http://[2001:db8::1]:8080/index.html",
            "https://example.com", "https://example.com/", "https://example.com?",
            "HTTPS://Example.com/#",
            "https://example.com/?a=1&&b", "https://example.com/שלום/عربى?q=שלום#סוף",
            "https://example.com/a?next=https://other.example/b?c=d#e",
            "ftp://files.example.com/a.zip",
            "https://example.com/" + String(repeating: "a/", count: 1_500)
        ])
    func tiles(_ url: String) throws {
        let anatomy = try #require(LinkAnatomy(text: "  \(url)\n"))
        #expect(anatomy.text == url)
        #expect(anatomy.segments.map(\.text).joined() == url)
        #expect(
            anatomy.segments.map { String(anatomy.text[$0.range]) } == anatomy.segments.map(\.text))
        let order = anatomy.segments.compactMap {
            LinkAnatomy.Part.allCases.firstIndex(of: $0.part)
        }
        #expect(order == order.sorted())
        #expect(Set(order).count == order.count)
    }

    @Test("The authority keeps user, port and an IPv6 literal in the host part")
    func authority() {
        #expect(
            parts("https://user:secret@example.com:8080/private") == [
                "scheme=https://", "host=user:secret@example.com:8080", "path=/private"
            ])
        #expect(
            parts("http://[2001:db8::1]:8080/index.html") == [
                "scheme=http://", "host=[2001:db8::1]:8080", "path=/index.html"
            ])
    }

    @Test("Absent parts are absent; empty ones keep their delimiter and decode to nothing")
    func sparse() throws {
        #expect(parts("https://example.com") == ["scheme=https://", "host=example.com"])
        #expect(
            parts("https://example.com#top") == [
                "scheme=https://", "host=example.com", "fragment=#top"
            ])
        let empty = try #require(LinkAnatomy(text: "https://example.com/?#"))
        #expect(empty.segments.map(\.part) == [.scheme, .host, .path, .query, .fragment])
        #expect(empty.parameters.isEmpty)
        #expect(empty.fragment == nil)
        #expect(empty.path == nil)
    }

    @Test("Parameters and the fragment decode; the segments stay as copied")
    func decoding() throws {
        let url = "https://example.com/a%2Fb?q=a%26b&caf%C3%A9=s%C3%AD&flag&e=1=2&bad=%ZZ#se%20c"
        let anatomy = try #require(LinkAnatomy(text: url))
        #expect(
            anatomy.parameters == [
                .init(name: "q", value: "a&b"), .init(name: "café", value: "sí"),
                .init(name: "flag", value: ""), .init(name: "e", value: "1=2"),
                .init(name: "bad", value: "%ZZ")
            ])
        #expect(anatomy.fragment == "se c")
        #expect(anatomy.path == "/a/b")
        #expect(anatomy.segments.first { $0.part == .path }?.text == "/a%2Fb")
    }

    @Test("A `?` or `#` inside a later part does not start a new one")
    func nestedDelimiters() {
        #expect(
            parts("https://example.com/a?next=https://other.example/b?c=d#e/f?g") == [
                "scheme=https://", "host=example.com", "path=/a",
                "query=?next=https://other.example/b?c=d", "fragment=#e/f?g"
            ])
    }

    @Test(
        "Text without an authority, or past the preview bound, has no anatomy",
        arguments: [
            "mailto:someone@example.com", "tel:+15551234567", "not a url", "", "https://",
            "example.com/path", "https:example.com",
            "https://example.com/" + String(repeating: "a", count: 4_000)
        ])
    func none(_ text: String) {
        #expect(LinkAnatomy(text: text) == nil)
    }

    @Test("Identifiers are stable kebab-case names")
    func identifiers() {
        #expect(
            LinkAnatomy.Part.allCases.map(\.accessibilityIdentifier) == [
                "peek-link-part-scheme", "peek-link-part-host", "peek-link-part-path",
                "peek-link-part-query", "peek-link-part-fragment"
            ])
        #expect(
            LinkAnatomy.Parameter(name: "ref", value: "x").accessibilityIdentifier
                == "peek-link-param-ref")
    }
}
