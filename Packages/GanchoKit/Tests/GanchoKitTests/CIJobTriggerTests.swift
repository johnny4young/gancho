import Foundation
import Testing

@Suite("CI job triggers")
struct CIJobTriggerTests {
    private static let events = ["push", "pull_request", "schedule", "workflow_dispatch"]

    @Test("The iOS simulator check holds a macOS runner only on the schedule or by hand")
    func iOSCheckSkipsPushesAndPullRequests() throws {
        let condition = try jobCondition("ios-ui")
        let runs = try Self.events.filter {
            try evaluate(condition, ["github.event_name": $0, "needs.changes.outputs.app": "true"])
        }
        #expect(runs == ["schedule", "workflow_dispatch"], "if: \(condition)")
    }

    private func jobCondition(_ job: String) throws -> String {
        let source = try String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(
                ".github/workflows/ci.yml"),
            encoding: .utf8)
        let block = try #require(source.components(separatedBy: "\n  \(job):\n").dropFirst().first)
        let lines = block.split(separator: "\n").prefix { $0.hasPrefix("    ") || $0.isEmpty }
        let line = try #require(lines.first { $0.hasPrefix("    if: ") })
        return String(line.dropFirst("    if: ".count))
    }

    /// Evaluates `a == 'x' && b != 'y' || …` over context paths; anything else fails the test.
    private func evaluate(_ condition: String, _ context: [String: String]) throws -> Bool {
        try condition.components(separatedBy: "||").contains { disjunct in
            try disjunct.components(separatedBy: "&&").allSatisfy { term in
                let negated = term.contains("!=")
                let sides = term.components(separatedBy: negated ? "!=" : "==")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                try #require(sides.count == 2, "Extend the evaluator for: \(term)")
                let value = try #require(context[sides[0]], "Unknown context: \(sides[0])")
                let literal = sides[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                return (value == literal) != negated
            }
        }
    }
}
