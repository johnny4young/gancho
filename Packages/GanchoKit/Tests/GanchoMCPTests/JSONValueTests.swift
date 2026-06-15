import Foundation
import Testing

@testable import GanchoMCP

@Suite("JSONValue — faithful JSON round-trips")
struct JSONValueTests {
    private func decode(_ raw: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    }

    private func encode(_ value: JSONValue) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }

    @Test("numbers keep Int vs Double identity")
    func numberIdentity() throws {
        #expect(try decode("1") == .int(1))
        #expect(try decode("1.5") == .double(1.5))
        #expect(try encode(.int(1)) == "1")
    }

    @Test("scalars decode to the right case")
    func scalars() throws {
        #expect(try decode("true") == .bool(true))
        #expect(try decode("\"hi\"") == .string("hi"))
        #expect(try decode("null") == .null)
    }

    @Test("objects and arrays nest")
    func nesting() throws {
        let value = try decode(#"{"a":[1,2],"b":{"c":"d"}}"#)
        #expect(value["a"]?.arrayValue?.count == 2)
        #expect(value["b"]?["c"]?.stringValue == "d")
    }

    @Test("bridges to and from Codable types")
    func codableBridge() throws {
        struct Point: Codable, Equatable {
            let x: Int
            let label: String
        }
        let value = try JSONValue(encoding: Point(x: 3, label: "p"))
        #expect(value["x"]?.intValue == 3)
        #expect(try value.decoded(as: Point.self) == Point(x: 3, label: "p"))
    }
}
