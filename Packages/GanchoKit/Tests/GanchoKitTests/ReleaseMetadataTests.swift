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

    /// The deployment-floor inventory must exist, be executable, and
    /// keep its two safety guarantees: it restores the manifest no matter how
    /// it exits, and it probes each target separately (a whole-package build
    /// would stop at the first blocker and hide the rest). The documented
    /// finding — GanchoKit is already floor-clean at macOS 15 — is captured in
    /// docs/DEPLOYMENT-FLOOR.md so a regression in that claim is reviewable.
    @Test func deploymentFloorInventoryExistsAndIsSafe() throws {
        let script = try Self.text("scripts", "check-deployment-floor.sh")
        // Restore-on-exit is the load-bearing guarantee — a left-over lowered
        // floor would silently change what every later build checks.
        #expect(script.contains("trap restore EXIT"))
        #expect(script.contains("trap 'exit 130' INT TERM"))
        #expect(script.contains("swift build --target"))
        #expect(script.contains(".macOS(.v${macos_floor})"))
        #expect(script.contains("probe_failures"))

        let scriptURL = Self.repositoryRoot
            .appendingPathComponent("scripts/check-deployment-floor.sh")
        let isExecutable = FileManager.default.isExecutableFile(atPath: scriptURL.path)
        #expect(isExecutable, "the floor inventory must be executable")

        let doc = try Self.text("docs", "DEPLOYMENT-FLOOR.md")
        #expect(doc.contains("macOS 15 package inventory"))
        #expect(doc.contains("iOS 18 remains a separate Xcode build probe"))
        #expect(doc.contains("FoundationModels"))
        #expect(doc.contains("glassEffect"))
    }

    @Test func releaseWorkflowBuildsTheProfileBackedSignedDMG() throws {
        let workflow = try Self.text(".github", "workflows", "release.yml")

        #expect(workflow.contains("tags: [\"v*\"]"))
        #expect(workflow.contains("make release-check"))
        #expect(workflow.contains("GITHUB_REF_NAME#v"))
        // The publish job fails closed around the signed, notarized,
        // profile-backed direct-download DMG, then publishes + bumps the cask.
        #expect(workflow.contains("make package-dmg"))
        #expect(workflow.contains("MACOS_PROVISIONING_PROFILE_BASE64"))
        #expect(workflow.contains("REQUIRE_PRODUCTION_RELEASE: \"1\""))
        #expect(workflow.contains("REQUIRE_SYNC_ENTITLEMENTS: \"1\""))
        #expect(!workflow.contains("GANCHO_LICENSE_SIGNING_KEY: ${{ secrets."))
        #expect(workflow.contains("softprops/action-gh-release"))
        #expect(workflow.contains("dist/Gancho-*.dmg"))
        #expect(workflow.contains("update-homebrew-tap.sh"))
    }

    @Test func releaseWorkflowRequiresOutcomeLedNotesForTheTag() throws {
        let project = try Self.text("project.yml")
        let workflow = try Self.text(".github", "workflows", "release.yml")
        let marketingVersion = try Self.firstCapture(
            in: project,
            pattern: #"(?m)^\s*MARKETING_VERSION:\s*"?([0-9]+\.[0-9]+\.[0-9]+)"?\s*$"#)
        let notes = try Self.text("docs", "releases", "v\(marketingVersion).md")

        #expect(workflow.contains("notes=\"docs/releases/${GITHUB_REF_NAME}.md\""))
        #expect(workflow.contains("body_path: docs/releases/${{ github.ref_name }}.md"))
        #expect(workflow.contains("fail_on_unmatched_files: true"))
        #expect(!workflow.contains("generate_release_notes: true"))
        #expect(notes.hasPrefix("# Gancho v\(marketingVersion)"))
        #expect(notes.contains("## Highlights"))
        #expect(notes.contains("## Install or update"))
        #expect(notes.contains("## Availability"))
        #expect(notes.contains("## Release verification"))
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

    /// The upstream canary must (a) pass when the latest releases match the
    /// pins and (b) DETECT a deliberately advanced upstream — both proven
    /// offline via fixture files built from the real pins, no source edits.
    @Test func upstreamCanaryDetectsAdvancedUpstreams() throws {
        let pinsURL = Self.repositoryRoot.appendingPathComponent("scripts/upstream-pins.env")
        let pinLines = try String(contentsOf: pinsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("#") && $0.contains("=") }
        #expect(pinLines.count == 5, "the canary tracks exactly five upstreams")

        func runCanary(latest: [String]) throws -> (status: Int32, output: String) {
            let fixture = FileManager.default.temporaryDirectory
                .appendingPathComponent("canary-\(UUID().uuidString).env")
            try latest.joined(separator: "\n").write(
                to: fixture, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: fixture) }
            let process = Process()
            process.executableURL = Self.repositoryRoot
                .appendingPathComponent("scripts/check-upstream-deps.sh")
            process.arguments = ["--latest", fixture.path]
            process.currentDirectoryURL = Self.repositoryRoot
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
        }

        let current = try runCanary(latest: pinLines)
        #expect(current.status == 0, Comment(rawValue: current.output))

        let advanced = pinLines.map {
            $0.hasPrefix("GRDB=") ? "GRDB=99.0.0" : $0
        }
        let stale = try runCanary(latest: advanced)
        #expect(stale.status == 1, "an advanced upstream must fail the canary")
        #expect(stale.output.contains("UPSTREAM ADVANCED: GRDB"), Comment(rawValue: stale.output))

        // A pin AHEAD of the latest release (pre-release, fork tag, rollback)
        // is deliberate state, not drift — reported, never a failure.
        let behind = pinLines.map {
            $0.hasPrefix("GRDB=") ? "GRDB=1.0.0" : $0
        }
        let pinnedAhead = try runCanary(latest: behind)
        #expect(pinnedAhead.status == 0, Comment(rawValue: pinnedAhead.output))
        #expect(
            pinnedAhead.output.contains("pinned ahead"), Comment(rawValue: pinnedAhead.output))
    }

    /// Dependabot may never touch the encrypted-store fork: the automation's
    /// scope is part of the security model, so its exclusions are pinned here.
    @Test func dependabotExcludesTheEncryptedStoreFork() throws {
        let config = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(".github/dependabot.yml"),
            encoding: .utf8)
        #expect(config.contains("- dependency-name: \"GRDB.swift\""))
        #expect(config.contains("- dependency-name: \"SQLCipher.swift\""))
        #expect(
            !FileManager.default.fileExists(
                atPath: Self.repositoryRoot
                    .appendingPathComponent(".github/workflows/auto-merge.yml").path),
            "no auto-merge workflow may exist")
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

    @Test func buildWarningClassifierRejectsSeededWarnings() throws {
        let process = Process()
        process.executableURL = Self.repositoryRoot
            .appendingPathComponent("scripts/check-build-warnings.sh")
        process.arguments = ["--self-test"]
        process.currentDirectoryURL = Self.repositoryRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(bytes: data, encoding: .utf8) ?? "Warning classifier self-test failed"
        #expect(process.terminationStatus == 0, Comment(rawValue: message))
    }

    @Test func storeKitProductCopyDoesNotShipSyncEarly() throws {
        let storeKit = try Self.text("Apps", "GanchoMac", "Gancho.storekit")

        #expect(storeKit.contains("iCloud sync is coming soon"))
        #expect(!storeKit.contains("sync and AI"))
    }
}
