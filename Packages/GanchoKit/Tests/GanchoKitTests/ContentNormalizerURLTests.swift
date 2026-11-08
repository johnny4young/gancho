import Foundation
import Testing

@testable import GanchoKit

@Suite("URL normalization — preserve functional query encoding")
struct ContentNormalizerURLTests {
    @Test(
        "Queries without tracking parameters remain byte-for-byte unchanged",
        arguments: [
            "https://example.invalid/search?q=C%2B%2B",
            "https://example.invalid/?a%2Bb=value",
            "https://example.invalid/?data=a%2fb%3dc%2bd",
            "https://example.invalid/?q=%2B&&empty=&flag&",
            "https://example.invalid/?raw=%FF&literal=%252B"
        ])
    func leavesFunctionalQueriesUnchanged(input: String) {
        #expect(ContentNormalizer.normalizeURL(input) == input)
    }

    @Test(
        "Removing tracking preserves retained names, values and escape spelling",
        arguments: [
            (
                "https://example.invalid/search?q=C%2B%2B&utm_source=fixture",
                "https://example.invalid/search?q=C%2B%2B"
            ),
            (
                "https://example.invalid/?a%2Bb=value&gclid=fixture",
                "https://example.invalid/?a%2Bb=value"
            ),
            (
                "https://example.invalid/?data=a%2fb%3dc%2bd&utm_medium=fixture",
                "https://example.invalid/?data=a%2fb%3dc%2bd"
            ),
            (
                "https://example.invalid/?raw=%FF&literal=%252B&utm_source=fixture",
                "https://example.invalid/?raw=%FF&literal=%252B"
            )
        ])
    func preservesRetainedEncoding(input: String, expected: String) {
        #expect(ContentNormalizer.normalizeURL(input) == expected)
    }

    @Test("Encoded and case-insensitive tracking names are still removed")
    func matchesDecodedTrackingNames() {
        #expect(
            ContentNormalizer.normalizeURL(
                "https://example.invalid/?UTM%5Fsource=fixture&q=%2B")
                == "https://example.invalid/?q=%2B")
    }

    @Test("Duplicate parameters, empty values and fragments keep their order")
    func preservesQueryStructure() {
        #expect(
            ContentNormalizer.normalizeURL(
                "https://example.invalid/?q=%2B&&empty=&flag&utm_source=x&q=+#part")
                == "https://example.invalid/?q=%2B&&empty=&flag&q=+#part")
    }

    @Test("Literal plus, form-space and encoded space stay distinct for deduplication")
    func doesNotCollapseDistinctURLs() {
        let literalPlus = "https://example.invalid/?q=%2B"
        let formSpace = "https://example.invalid/?q=+"
        let encodedSpace = "https://example.invalid/?q=%20"
        #expect(
            ContentNormalizer.canonicalText(literalPlus, kind: .url)
                != ContentNormalizer.canonicalText(formSpace, kind: .url))
        #expect(
            ContentNormalizer.canonicalText(literalPlus, kind: .url)
                != ContentNormalizer.canonicalText(encodedSpace, kind: .url))
    }

    @Test("Unicode query data and tracking-only controls retain their behavior")
    func unicodeAndTrackingOnly() {
        #expect(
            ContentNormalizer.normalizeURL(
                "https://example.invalid/ni%C3%B1o?q=%E4%B8%96%E7%95%8C&utm_source=x")
                == "https://example.invalid/ni%C3%B1o?q=%E4%B8%96%E7%95%8C")
        #expect(
            ContentNormalizer.normalizeURL("https://example.invalid/?gclid=x&utm_source=y")
                == "https://example.invalid/")
        let nonWeb = "custom://example.invalid/?q=%2B&utm_source=x"
        #expect(ContentNormalizer.normalizeURL(nonWeb) == nonWeb)
    }
}
