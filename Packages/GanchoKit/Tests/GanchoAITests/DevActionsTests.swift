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
}
