import Foundation
import Testing

@Suite("Release metadata")
struct ReleaseMetadataTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GanchoKitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // GanchoKit/
            .deletingLastPathComponent()  // Packages/
            .deletingLastPathComponent()  // repo root
    }

    private static func text(_ components: String...) throws -> String {
        let url = components.reduce(repositoryRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func firstCapture(in text: String, pattern: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = try #require(
            regex.firstMatch(in: text, range: range),
            "Missing pattern: \(pattern)")
        #expect(match.numberOfRanges > 1)
        let captureRange = try #require(Range(match.range(at: 1), in: text))
        return String(text[captureRange])
    }

    @Test func projectChangelogAndFormulaVersionsStayInSync() throws {
        let project = try Self.text("project.yml")
        let changelog = try Self.text("CHANGELOG.md")
        let formula = try Self.text("scripts", "homebrew", "gancho.rb")

        let marketingVersion = try Self.firstCapture(
            in: project,
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9]+\.[0-9]+\.[0-9]+)"?\s*$"#)
        let buildVersion = try Self.firstCapture(
            in: project,
            pattern: #"(?m)^\s*CURRENT_PROJECT_VERSION:\s*"?([0-9]+)"?\s*$"#)
        let changelogVersion = try Self.firstCapture(
            in: changelog,
            pattern: #"(?m)^## \[([0-9]+\.[0-9]+\.[0-9]+)\]"#)
        let formulaVersion = try Self.firstCapture(
            in: formula,
            pattern: #"(?m)^\s*version "([0-9]+\.[0-9]+\.[0-9]+)"\s*$"#)

        #expect(Int(buildVersion) ?? 0 >= 1)
        #expect(changelog.contains("## [Unreleased]"))
        #expect(changelogVersion == marketingVersion)
        #expect(formulaVersion == marketingVersion)
        #expect(formula.contains("archive/refs/tags/v#{version}.tar.gz"))

        for plistPath in [
            ["Apps", "GanchoMac", "Info.plist"],
            ["Apps", "GanchoiOS", "Info.plist"],
            ["Apps", "GanchoShare", "Info.plist"],
            ["Apps", "GanchoKeyboard", "Info.plist"],
            ["Apps", "GanchoWidgets", "Info.plist"],
        ] {
            let url = plistPath.reduce(Self.repositoryRoot) { $0.appendingPathComponent($1) }
            let plist = try String(contentsOf: url, encoding: .utf8)
            #expect(plist.contains("<string>$(MARKETING_VERSION)</string>"))
            #expect(plist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        }
    }

    @Test func releaseWorkflowGuardsTaggedArtifacts() throws {
        let workflow = try Self.text(".github", "workflows", "release.yml")

        #expect(workflow.contains("tags: [\"v*\"]"))
        #expect(workflow.contains("make release-check"))
        #expect(workflow.contains("GITHUB_REF_NAME#v"))
        #expect(workflow.contains("./scripts/package-macos-zip.sh"))
        #expect(workflow.contains("./scripts/qa-release.sh"))
        #expect(workflow.contains("softprops/action-gh-release"))
        #expect(workflow.contains("dist/Gancho-*.zip"))
    }

    @Test func pagesWorkflowDeploysTheStaticSite() throws {
        let workflow = try Self.text(".github", "workflows", "pages.yml")
        let index = try Self.text("site", "index.html")

        #expect(workflow.contains("actions/configure-pages"))
        #expect(workflow.contains("actions/upload-pages-artifact"))
        #expect(workflow.contains("actions/deploy-pages"))
        #expect(workflow.contains("path: site"))
        #expect(index.contains("Privacy-first"))
        #expect(index.contains("CHANGELOG.md"))
    }

    @Test func storeKitProductCopyDoesNotShipSyncEarly() throws {
        let storeKit = try Self.text("Apps", "GanchoMac", "Gancho.storekit")

        #expect(storeKit.contains("iCloud sync is coming soon"))
        #expect(!storeKit.contains("sync and AI"))
    }
}
