import Foundation
import Testing

@Suite("CI run grouping")
struct CIConcurrencyTests {
    @Test("Every main push keeps its own run; pushes to one pull request share a group")
    func groups() throws {
        let template = try groupTemplate()
        func push(_ runID: Int) throws -> String {
            try render(template, ["github.ref": "refs/heads/main", "github.run_id": "\(runID)"])
        }
        func pullRequest(_ number: Int, _ runID: Int) throws -> String {
            try render(
                template,
                [
                    "github.ref": "refs/pull/\(number)/merge", "github.run_id": "\(runID)",
                    "github.event.pull_request.number": "\(number)"
                ])
        }
        // A shared group keeps one pending run, so a later merge would drop an earlier one.
        #expect(try push(101) != push(102))
        #expect(try pullRequest(7, 201) == pullRequest(7, 202))
        #expect(try pullRequest(7, 201) != pullRequest(8, 203))
    }

    private func groupTemplate() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        let block = try #require(
            source.components(separatedBy: "\nconcurrency:\n").dropFirst().first)
        let line = try #require(block.split(separator: "\n").first { $0.hasPrefix("  group: ") })
        return String(line.dropFirst("  group: ".count))
    }

    /// Renders `${{ a || b }}` chains of context paths; anything else fails the test.
    private func render(_ template: String, _ context: [String: String]) throws -> String {
        var result = template
        while let open = result.range(of: "${{"),
            let close = result.range(of: "}}", range: open.upperBound..<result.endIndex)
        {
            let paths = result[open.upperBound..<close.lowerBound]
                .components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
            try #require(
                paths.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "." || $0 == "_" } },
                "Extend the renderer for: \(paths)")
            let value = paths.lazy.compactMap { context[$0] }.first ?? ""
            result.replaceSubrange(open.lowerBound..<close.upperBound, with: value)
        }
        return result
    }
}
