import Foundation
import Testing

@Suite("CI run grouping")
struct CIConcurrencyTests {
    @Test("Every non-PR run keeps its own group; pushes to one pull request share a group")
    func groups() throws {
        let (template, cancelInProgress) = try concurrency()
        func run(_ runID: Int) throws -> String {
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
        // A shared group keeps one pending run, so a later push, schedule or dispatch
        // would drop an earlier one.
        #expect(try run(101) != run(102))
        #expect(try pullRequest(7, 201) == pullRequest(7, 202))
        #expect(try pullRequest(7, 201) != pullRequest(8, 203))
        #expect(cancelInProgress == "true", "a newer push must supersede the PR's run")
    }

    private func concurrency() throws -> (group: String, cancelInProgress: String) {
        let source = try String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(
                ".github/workflows/ci.yml"),
            encoding: .utf8)
        let block = try #require(
            source.components(separatedBy: "\nconcurrency:\n").dropFirst().first)
        func value(_ key: String) throws -> String {
            let prefix = "  \(key): "
            let line = try #require(block.split(separator: "\n").first { $0.hasPrefix(prefix) })
            return String(line.dropFirst(prefix.count))
        }
        return try (value("group"), value("cancel-in-progress"))
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
                paths.allSatisfy {
                    !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0 == "." || $0 == "_" }
                },
                "Extend the renderer for: \(paths)")
            let value = paths.lazy.compactMap { context[$0] }.first ?? ""
            result.replaceSubrange(open.lowerBound..<close.upperBound, with: value)
        }
        return result
    }
}
