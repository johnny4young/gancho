import Foundation
import Testing

/// The static half of the signpost policy: intervals are content-free BY
/// CONSTRUCTION (the `Signpost` enum API takes no strings or values), and
/// this gate keeps it that way — no signpost API use outside the two
/// `Signposts.swift` helpers, no signposts in engine modules at all, and no
/// dynamic names or extra arguments inside the helpers themselves.
@Suite("Signpost hygiene — content-free by construction")
struct SignpostHygieneTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GanchoKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // GanchoKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
    }

    private static func swiftFiles(under folder: String) throws -> [URL] {
        let root = repositoryRoot.appendingPathComponent(folder)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("Signpost APIs appear only inside the two app-target helpers")
    func signpostsStayInTheHelpers() throws {
        for folder in ["Apps", "Packages/GanchoKit/Sources"] {
            for file in try Self.swiftFiles(under: folder) {
                let source = try String(contentsOf: file, encoding: .utf8)
                guard
                    source.contains("OSSignposter") || source.contains("os_signpost")
                        || source.contains("OSSignpostID")
                else { continue }
                #expect(
                    file.lastPathComponent == "Signposts.swift"
                        && file.path.contains("/Apps/"),
                    "signpost APIs are confined to the app-target Signposts.swift helpers; found in \(file.path)"
                )
            }
        }
    }

    @Test("The helpers carry no dynamic names and no value arguments")
    func helpersStayContentFree() throws {
        let helpers = try Self.swiftFiles(under: "Apps").filter {
            $0.lastPathComponent == "Signposts.swift"
        }
        #expect(helpers.count == 2, "one helper per app target (macOS + iOS)")
        for helper in helpers {
            let source = try String(contentsOf: helper, encoding: .utf8)
            // Every begin/end names its interval with a quoted literal on the
            // same call — never a variable — and passes no message payload.
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("beginInterval") || trimmed.contains("endInterval") {
                    #expect(
                        trimmed.contains("(\"") || trimmed.contains(", state)"),
                        "interval names must be string literals: \(trimmed)")
                    #expect(
                        !trimmed.contains("\\("),
                        "no interpolation may reach a signpost: \(trimmed)")
                }
            }
            #expect(
                !source.contains("String("),
                "the helper must not build strings at all")
        }
    }
}
