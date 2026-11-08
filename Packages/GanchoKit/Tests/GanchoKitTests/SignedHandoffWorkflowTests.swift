import Foundation
import Testing

@Suite("Signed handoff triggers")
struct SignedHandoffWorkflowTests {
    private static func paths(under trigger: String) throws -> [String] {
        let source = try String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(
                ".github/workflows/signed-handoff.yml"),
            encoding: .utf8)
        let block = try #require(
            source.components(separatedBy: "\n  \(trigger):\n").dropFirst().first,
            "no \(trigger) trigger")
        return block.split(separator: "\n")
            .drop { !$0.hasPrefix("    paths:") }.dropFirst()
            .prefix { $0.hasPrefix("      - ") }
            .map { String($0.dropFirst("      - ".count)) }
    }

    /// GitHub path filters: `**` crosses directories, `*` stays inside one.
    private static func matches(_ path: String, _ patterns: [String]) -> Bool {
        patterns.contains { pattern in
            let regex =
                "^"
                + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*\\*", with: ".*")
                .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"
            return path.range(of: regex, options: .regularExpression) != nil
        }
    }

    @Test("Every change a pull request skips still runs on main after the merge")
    func mainCoversWhatPullRequestsSkip() throws {
        let pullRequest = try Self.paths(under: "pull_request")
        let main = try Self.paths(under: "push")
        #expect(!pullRequest.isEmpty)
        for pattern in pullRequest {
            let covered =
                main.contains(pattern)
                || main.contains { $0.hasSuffix("/**") && pattern.hasPrefix($0.dropLast(2)) }
            #expect(covered, "\(pattern) runs on pull requests but not on main")
        }
    }

    @Test("A failed or timed-out run on main opens one issue; pull requests never do")
    func mainFailureOpensAnIssue() throws {
        let source = try String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(
                ".github/workflows/signed-handoff.yml"),
            encoding: .utf8)
        let parts = source.components(separatedBy: "\n  report-main-failure:\n")
        let job = try #require(parts.dropFirst().first, "no report job")
        #expect(job.contains("needs: [signed-handoff]"))
        #expect(job.contains("always() && github.event_name == 'push'"))
        #expect(
            job.contains(
                #"contains(fromJSON('["failure","cancelled"]'), needs.signed-handoff.result)"#))
        #expect(job.contains("issues: write"))
        #expect(!parts[0].contains("issues: write"), "only the report job may write issues")
    }

    @Test(
        "Helper, signing and paste-back changes run on the pull request; other app code on main",
        arguments: [
            ("Apps/GanchoMac/GanchoMenuBarHelperLauncher.swift", true),
            ("Apps/GanchoMac/Gancho.entitlements", true),
            ("Packages/GanchoKit/Sources/ClipboardCore/PasteBackService.swift", true),
            ("Apps/GanchoMac/PanelController.swift", false),
            ("Packages/GanchoKit/Sources/GanchoKit/GanchoArchive.swift", false)
        ])
    func triggers(path: String, onPullRequest: Bool) throws {
        #expect(
            FileManager.default.fileExists(
                atPath: LocalizationTests.repoRoot.appendingPathComponent(path).path))
        #expect(Self.matches(path, try Self.paths(under: "pull_request")) == onPullRequest)
        #expect(Self.matches(path, try Self.paths(under: "push")))
    }
}
