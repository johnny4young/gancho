import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

@Suite("Dev actions — offline transforms")
struct DevActionsTests {
    @Test("JWT decode prints header, claims, and readable expiry")
    func jwtDecode() throws {
        // {"alg":"HS256"} . {"sub":"1","exp":1500000000} . sig — exp in 2017.
        let jwt =
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwiZXhwIjoxNTAwMDAwMDAwfQ.c2ln"
        let output = try DevActions.run(.decodeJWT, on: jwt)
        #expect(output.contains("HS256"))
        #expect(output.contains("\"sub\" : \"1\""))
        #expect(output.contains("2017"))
        #expect(output.contains("EXPIRED"))
    }

    @Test("Invalid JWT throws notApplicable, never garbage")
    func jwtInvalid() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.decodeJWT, on: "1.2.3")
        }
    }

    @Test("JSON pretty and minify round-trip")
    func jsonRoundTrip() throws {
        let minified = #"{"b":2,"a":[1,2]}"#
        let pretty = try DevActions.run(.jsonPretty, on: minified)
        #expect(pretty.contains("\n"))
        let back = try DevActions.run(.jsonMinify, on: pretty)
        #expect(back == #"{"a":[1,2],"b":2}"#)
    }

    @Test("Base64 encode/decode round-trip, invalid input throws")
    func base64() throws {
        let encoded = try DevActions.run(.base64Encode, on: "gancho ñ 🪝")
        #expect(try DevActions.run(.base64Decode, on: encoded) == "gancho ñ 🪝")
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.base64Decode, on: "!!! not base64 !!!")
        }
    }

    @Test("URL parse tabulates query parameters")
    func urlParse() throws {
        let output = try DevActions.run(
            .parseURL, on: "https://example.com:8080/path?a=1&b=two#frag")
        #expect(output.contains("host: example.com"))
        #expect(output.contains("port: 8080"))
        #expect(output.contains("a = 1"))
        #expect(output.contains("b = two"))
        #expect(output.contains("fragment: frag"))
    }

    @Test(
        "Color conversion emits all three forms from any input form",
        arguments: ["#FF6B35", "rgb(255, 107, 53)", "hsl(16, 100%, 60%)"])
    func colorConvert(input: String) throws {
        let output = try DevActions.run(.convertColor, on: input)
        #expect(output.contains("hex: #"))
        #expect(output.contains("rgb: rgb("))
        #expect(output.contains("hsl: hsl("))
    }

    @Test("Hex→RGB→HSL specific values stay exact")
    func colorExactness() throws {
        let output = try DevActions.run(.convertColor, on: "#FF0000")
        #expect(output.contains("rgb: rgb(255, 0, 0)"))
        #expect(output.contains("hsl: hsl(0, 100%, 50%)"))
    }

    @Test("UUID formats: upper, lower, compact")
    func uuidFormats() throws {
        let output = try DevActions.run(
            .uuidFormats, on: "550e8400-e29b-41d4-a716-446655440000")
        #expect(output.contains("upper: 550E8400-E29B-41D4-A716-446655440000"))
        #expect(output.contains("lower: 550e8400-e29b-41d4-a716-446655440000"))
        #expect(output.contains("compact: 550e8400e29b41d4a716446655440000"))
    }

    @Test("The right actions surface per kind, none for binary kinds")
    func catalogByKind() {
        #expect(DevActions.actions(for: .jwt).map(\.id) == [.decodeJWT])
        #expect(DevActions.actions(for: .json).map(\.id).contains(.jsonPretty))
        #expect(DevActions.actions(for: .url).map(\.id).contains(.parseURL))
        #expect(DevActions.actions(for: .color).map(\.id) == [.convertColor])
        #expect(DevActions.actions(for: .uuid).map(\.id) == [.uuidFormats])
        #expect(DevActions.actions(for: .image).isEmpty)
        #expect(DevActions.actions(for: .secret).isEmpty)
    }

    @Test("Hash actions emit the canonical test vectors")
    func hashVectors() throws {
        #expect(
            try DevActions.run(.sha256Hex, on: "abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            try DevActions.run(.sha1Hex, on: "abc")
                == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(try DevActions.run(.md5Hex, on: "abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test("Hashing the empty string yields the canonical empty digest")
    func hashEmptyString() throws {
        #expect(try DevActions.run(.md5Hex, on: "") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(
            try DevActions.run(.sha256Hex, on: "")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("URL encode escapes reserved characters and round-trips")
    func urlEncodeDecode() throws {
        let encoded = try DevActions.run(.urlEncode, on: "a b&c=d/ñ")
        #expect(encoded == "a%20b%26c%3Dd%2F%C3%B1")
        #expect(try DevActions.run(.urlDecode, on: encoded) == "a b&c=d/ñ")
    }

    @Test("URL decode throws on percent-escapes that are not valid UTF-8")
    func urlDecodeInvalid() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.urlDecode, on: "broken %C3%28 escape")
        }
    }

    @Test("Case convert emits all six labeled forms")
    func caseConvertForms() throws {
        let output = try DevActions.run(.caseConvert, on: "FooBar baz_qux-v2")
        #expect(output.contains("camel: fooBarBazQuxV2"))
        #expect(output.contains("snake: foo_bar_baz_qux_v2"))
        #expect(output.contains("kebab: foo-bar-baz-qux-v2"))
        #expect(output.contains("title: Foo Bar Baz Qux V2"))
        #expect(output.contains("upper: FOO BAR BAZ QUX V2"))
        #expect(output.contains("lower: foo bar baz qux v2"))
    }

    @Test("Case convert with no words throws notApplicable")
    func caseConvertNoWords() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.caseConvert, on: "!!! *** ---")
        }
    }

    @Test("Epoch seconds and milliseconds both print ISO-8601 UTC")
    func epochToDate() throws {
        let seconds = try DevActions.run(.epochToDate, on: "1500000000")
        #expect(seconds.contains("utc: 2017-07-14T02:40:00Z"))
        let millis = try DevActions.run(.epochToDate, on: "1500000000000")
        #expect(millis.contains("utc: 2017-07-14T02:40:00Z"))
    }

    @Test("Non-numeric or implausible input is not an epoch")
    func epochInvalid() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.epochToDate, on: "yesterday")
        }
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.epochToDate, on: "-5")
        }
    }

    @Test("ISO-8601 date converts to epoch seconds and milliseconds")
    func dateToEpoch() throws {
        let output = try DevActions.run(.dateToEpoch, on: "2017-07-14T02:40:00Z")
        #expect(output == "seconds: 1500000000\nmilliseconds: 1500000000000")
        let fractional = try DevActions.run(.dateToEpoch, on: "2017-07-14T02:40:00.500Z")
        #expect(fractional.contains("milliseconds: 1500000000500"))
    }

    @Test("Non-ISO date input throws notApplicable")
    func dateToEpochInvalid() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.dateToEpoch, on: "July 14th, 2017")
        }
    }

    @Test("Line ops: sort, stable dedupe, reverse")
    func lineOps() throws {
        let input = "b\na\nb\nc"
        #expect(try DevActions.run(.sortLines, on: input) == "a\nb\nb\nc")
        #expect(try DevActions.run(.dedupeLines, on: input) == "b\na\nc")
        #expect(try DevActions.run(.reverseLines, on: input) == "c\nb\na\nb")
    }

    @Test("Line ops need more than one line")
    func lineOpsSingleLine() {
        for id in [DevActions.ActionID.sortLines, .dedupeLines, .reverseLines] {
            #expect(throws: DevActions.ActionError.self) {
                _ = try DevActions.run(id, on: "only one line")
            }
        }
    }

    @Test("Count stats reports lines, words, characters, and bytes")
    func countStats() throws {
        let output = try DevActions.run(.countStats, on: "one two\nthree ñ")
        #expect(output.contains("lines: 2"))
        #expect(output.contains("words: 4"))
        #expect(output.contains("characters: 15"))
        #expect(output.contains("bytes: 16"))
        let empty = try DevActions.run(.countStats, on: "")
        #expect(empty.contains("lines: 0"))
        #expect(empty.contains("bytes: 0"))
    }

    @Test("HTML entity encode/decode round-trips, numeric entities decode")
    func htmlEntities() throws {
        let raw = #"<a href="x">Tom & Jerry's</a>"#
        let encoded = try DevActions.run(.htmlEntityEncode, on: raw)
        #expect(encoded == "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;")
        #expect(try DevActions.run(.htmlEntityDecode, on: encoded) == raw)
        #expect(try DevActions.run(.htmlEntityDecode, on: "&#65;&#x42;!") == "AB!")
    }

    @Test("Stray ampersands survive entity decoding untouched")
    func htmlDecodeStrayAmpersand() throws {
        let input = "fish & chips; &nope;"
        #expect(try DevActions.run(.htmlEntityDecode, on: input) == input)
    }

    @Test("Slugify lowercases, hyphenates, strips accents and repeats")
    func slugify() throws {
        let slug = try DevActions.run(.slugify, on: "  Héllo,  Wörld — Foo_bar!  ")
        #expect(slug == "hello-world-foo-bar")
    }

    @Test("Slugify with nothing slug-able throws notApplicable")
    func slugifyEmpty() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.slugify, on: "!!! ###")
        }
    }

    @Test(
        "Number base convert accepts dec, hex, bin, and oct spellings",
        arguments: ["255", "0xFF", "0b11111111", "0o377"])
    func numberBases(input: String) throws {
        let output = try DevActions.run(.numberBaseConvert, on: input)
        #expect(output.contains("dec: 255"))
        #expect(output.contains("hex: 0xff"))
        #expect(output.contains("bin: 0b11111111"))
        #expect(output.contains("oct: 0o377"))
    }

    @Test("Number base convert keeps the sign and rejects non-numbers")
    func numberBaseEdges() throws {
        let output = try DevActions.run(.numberBaseConvert, on: "-10")
        #expect(output.contains("dec: -10"))
        #expect(output.contains("hex: -0xa"))
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.numberBaseConvert, on: "not a number")
        }
    }

    @Test("JSON escape produces a string literal; unescape round-trips it")
    func jsonStringLiteral() throws {
        let raw = "line one\nline \"two\" \\ end"
        let escaped = try DevActions.run(.jsonEscape, on: raw)
        #expect(escaped.hasPrefix("\""))
        #expect(escaped.hasSuffix("\""))
        #expect(escaped.contains("\\n"))
        #expect(try DevActions.run(.jsonUnescape, on: escaped) == raw)
    }

    @Test("JSON unescape rejects text that is not one string literal")
    func jsonUnescapeInvalid() {
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.jsonUnescape, on: "no quotes")
        }
        #expect(throws: DevActions.ActionError.self) {
            _ = try DevActions.run(.jsonUnescape, on: #""a" "b""#)
        }
    }

    @Test("New actions surface on sensible kinds")
    func newActionsCatalog() {
        #expect(DevActions.actions(for: .date).map(\.id) == [.dateToEpoch])
        #expect(DevActions.actions(for: .text).map(\.id).contains(.caseConvert))
        #expect(DevActions.actions(for: .text).map(\.id).contains(.slugify))
        #expect(DevActions.actions(for: .url).map(\.id).contains(.urlEncode))
        #expect(DevActions.actions(for: .code).map(\.id).contains(.jsonEscape))
        #expect(DevActions.actions(for: .code).map(\.id).contains(.md5Hex))
    }
}
