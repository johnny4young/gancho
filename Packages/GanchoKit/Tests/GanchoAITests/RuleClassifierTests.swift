import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

@Suite("RuleClassifier — tier 0")
struct RuleClassifierTests {
    let classifier = RuleClassifier()

    // {"alg":"HS256","typ":"JWT"} . {"sub":"123"} . fake signature
    private let sampleJWT =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl"

    @Test("Detects a JWT by structure and decodable header")
    func detectsJWT() {
        #expect(classifier.classify(sampleJWT) == .jwt)
    }

    @Test("A version string with two dots is not a JWT")
    func versionStringIsNotJWT() {
        #expect(classifier.classify("1.2.3") == .text)
    }

    @Test("Detects UUIDs")
    func detectsUUID() {
        #expect(classifier.classify("123E4567-E89B-12D3-A456-426614174000") == .uuid)
    }

    @Test("Detects hex colors with and without the leading hash")
    func detectsHexColor() {
        #expect(classifier.classify("#FF8800") == .color)
        // Bare hex runs are hashes/words more often than colors — '#' required.
        #expect(classifier.classify("ffcc00aa") == .text)
        #expect(classifier.classify("#abc") == .color)
    }

    @Test("Plain words that happen to be short are not colors")
    func wordsAreNotColors() {
        #expect(classifier.classify("hold") == .text)
    }

    @Test("Detects JSON objects and arrays")
    func detectsJSON() {
        #expect(classifier.classify(#"{"name":"Gancho","pro":true}"#) == .json)
        #expect(classifier.classify("[1, 2, 3]") == .json)
    }

    @Test("Detects full-string URLs but not links inside sentences")
    func detectsURL() {
        #expect(classifier.classify("https://gancho.app/pricing") == .url)
        #expect(classifier.classify("check out https://gancho.app today") == .text)
    }

    @Test("Detects emails as email, not generic links")
    func detectsEmail() {
        #expect(classifier.classify("ana@example.com") == .email)
    }

    @Test("Empty and whitespace input is plain text")
    func emptyIsText() {
        #expect(classifier.classify("   ") == .text)
    }
}
