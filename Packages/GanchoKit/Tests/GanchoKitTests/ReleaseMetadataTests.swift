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

    private static func matchCount(in text: String, pattern: String) throws -> Int {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
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
            ["Apps", "GanchoWidgets", "Info.plist"]
        ] {
            let url = plistPath.reduce(Self.repositoryRoot) { $0.appendingPathComponent($1) }
            let plist = try String(contentsOf: url, encoding: .utf8)
            #expect(plist.contains("<string>$(MARKETING_VERSION)</string>"))
            #expect(plist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        }
    }

    @Test func releaseWorkflowBuildsTheSignedLicenseDMG() throws {
        let workflow = try Self.text(".github", "workflows", "release.yml")

        #expect(workflow.contains("tags: [\"v*\"]"))
        #expect(workflow.contains("make release-check"))
        #expect(workflow.contains("GITHUB_REF_NAME#v"))
        // The publish job builds the signed, notarized direct-download DMG with
        // the license-signing key baked in, then publishes + bumps the cask.
        #expect(workflow.contains("make package-dmg"))
        #expect(workflow.contains("GANCHO_LICENSE_SIGNING_KEY"))
        #expect(workflow.contains("softprops/action-gh-release"))
        #expect(workflow.contains("dist/Gancho-*.dmg"))
        #expect(workflow.contains("update-homebrew-tap.sh"))
    }

    @Test func releaseWorkflowPublishesTheSignedAppcast() throws {
        let workflow = try Self.text(".github", "workflows", "release.yml")

        // The appcast (the SUFeedURL the installed base polls) is signed over the
        // exact released DMG and deployed to GitHub Pages + a redirect stub to
        // the canonical Cloudflare domain — all on the release tag.
        #expect(workflow.contains("make appcast"))
        #expect(workflow.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
        #expect(workflow.contains("actions/deploy-pages"))
        #expect(workflow.contains("path: _site"))
        #expect(workflow.contains("https://gancho.app/"))
    }

    @Test func pagesWorkflowDeploysTheLandingToCloudflare() throws {
        let workflow = try Self.text(".github", "workflows", "pages.yml")
        let index = try Self.text("site", "index.html")

        // The Website workflow deploys ONLY the marketing landing to Cloudflare
        // Pages; the appcast is published by the Release workflow (above).
        #expect(workflow.contains("wrangler@4 pages deploy"))
        #expect(workflow.contains("--project-name=gancho-web"))
        #expect(index.contains("private by design"))
        #expect(index.contains("CHANGELOG.md"))
    }

    @Test func publicProductTruthMatchesSourceContracts() throws {
        let project = try Self.text("project.yml")
        let package = try Self.text("Packages", "GanchoKit", "Package.swift")
        let readme = try Self.text("README.md")
        let site = try Self.text("site", "index.html")
        let security = try Self.text("docs", "SECURITY-MODEL.md")
        let truth = try Self.text("docs", "PRODUCT-TRUTH.md")

        let marketingVersion = try Self.firstCapture(
            in: project,
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9]+\.[0-9]+\.[0-9]+)"?\s*$"#)

        #expect(project.contains("macOS: \"26.0\""))
        #expect(project.contains("iOS: \"26.0\""))
        #expect(site.contains("macOS 26+ · iOS 26+"))
        #expect(try Self.matchCount(in: package, pattern: #"(?m)^\s*\.library\(name:"#) == 8)
        #expect(try Self.matchCount(in: package, pattern: #"(?m)^\s*\.executable\(name:"#) == 1)
        #expect(readme.contains("eight library products + a CLI"))
        #expect(readme.contains("disabled until explicit consent"))
        #expect(security.contains("Telemetry is disabled until the user consents"))
        #expect(site.contains("releases/latest"))
        #expect(readme.contains("v\(marketingVersion) DMG"))
        #expect(truth.contains("v\(marketingVersion)"))
        #expect(site.contains("v\(marketingVersion)"))
    }

    @Test func productTruthGatePassesAgainstTrackedFiles() throws {
        let process = Process()
        process.executableURL = Self.repositoryRoot
            .appendingPathComponent("scripts/check-product-truth.sh")
        process.currentDirectoryURL = Self.repositoryRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(bytes: data, encoding: .utf8) ?? "Product truth gate failed"
        #expect(process.terminationStatus == 0, Comment(rawValue: message))
    }

    @Test func storeKitProductCopyDoesNotShipSyncEarly() throws {
        let storeKit = try Self.text("Apps", "GanchoMac", "Gancho.storekit")

        #expect(storeKit.contains("iCloud sync is coming soon"))
        #expect(!storeKit.contains("sync and AI"))
    }
}
