import Foundation
import Testing

@Suite("Signed handoff triggers")
struct SignedHandoffWorkflowTests {
    private static func read(_ path: String) -> String {
        (try? String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(path), encoding: .utf8))
            ?? ""
    }

    private static let workflow = read(".github/workflows/signed-handoff.yml")
    private static let pullRequest = paths(under: "pull_request")
    private static let push = paths(under: "push")

    private static func paths(under trigger: String) -> [String] {
        guard let block = workflow.components(separatedBy: "\n  \(trigger):\n").dropFirst().first
        else { return [] }
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

    @Test("Every pull-request path also runs on main, and main still covers all app code")
    func mainCoversPullRequestsAndAppCode() {
        #expect(!Self.pullRequest.isEmpty)
        for pattern in Self.pullRequest {
            let covered =
                Self.push.contains(pattern)
                || Self.push.contains { $0.hasSuffix("/**") && pattern.hasPrefix($0.dropLast(2)) }
            #expect(covered, "\(pattern) runs on pull requests but not on main")
        }
        for root in ["Apps/GanchoMac/**", "Apps/GanchoMenuBarHelper/**", "Packages/GanchoKit/**"] {
            #expect(Self.push.contains(root), "\(root) no longer runs on main")
        }
    }

    @Test("Every source compiled into the menu-bar helper runs on the pull request")
    func helperSourcesRunOnPullRequests() throws {
        let project = Self.read("project.yml")
        let target = try #require(
            project.components(separatedBy: "\n  GanchoMenuBarHelper:\n").dropFirst().first)
        let sources = target.split(separator: "\n")
            .drop { $0 != "    sources:" }.dropFirst()
            .prefix { $0.hasPrefix("      ") }
            .compactMap { line -> String? in
                guard line.hasPrefix("      - path: ") else { return nil }
                return String(line.dropFirst("      - path: ".count))
            }
        #expect(!sources.isEmpty)
        for source in sources {
            let probe = source.hasSuffix(".swift") ? source : source + "/Probe.swift"
            #expect(Self.matches(probe, Self.pullRequest), "\(source) skips the pull request")
        }
    }

    @Test("Only pushes to main run it, and a later merge never cancels an earlier one")
    func mainRunsKeepTheirOwnGroup() {
        #expect(Self.workflow.contains("\n  push:\n    branches: [main]\n"))
        #expect(
            Self.workflow.contains(
                "group: signed-handoff-${{ github.event_name == 'push' && github.run_id"
                    + " || github.event.pull_request.number || github.ref }}"))
    }

    @Test("A failed or timed-out run on main opens one issue; pull requests never do")
    func mainFailureOpensAnIssue() throws {
        let parts = Self.workflow.components(separatedBy: "\n  report-main-failure:\n")
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
            ("Packages/GanchoKit/Sources/GanchoAppCore/MenuBarAffordanceWatchdog.swift", true),
            ("Apps/GanchoMac/PanelController.swift", false),
            ("Packages/GanchoKit/Sources/GanchoKit/GanchoArchive.swift", false)
        ])
    func triggers(path: String, onPullRequest: Bool) {
        #expect(
            FileManager.default.fileExists(
                atPath: LocalizationTests.repoRoot.appendingPathComponent(path).path))
        #expect(Self.matches(path, Self.pullRequest) == onPullRequest)
        #expect(Self.matches(path, Self.push))
    }
}
