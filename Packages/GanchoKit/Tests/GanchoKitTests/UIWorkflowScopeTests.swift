import Foundation
import Testing

@Suite("Hosted UI scope routing")
struct UIWorkflowScopeTests {
    @Test("The macOS job's allocation fits repeated suites and full platform gates stay")
    func stressAllocation() throws {
        let source = try workflow()
        #expect(source.contains("timeout-minutes: 90"))
        #expect(
            source.contains(
                "if: ${{ inputs.scope != 'ios-interaction-stress' && inputs.scope != 'ios-full' }}"
            ))
        #expect(source.contains("if: ${{ inputs.scope != 'interaction-stress' }}"))
        #expect(source.contains("case \"$GANCHO_IOS_UI_SCOPE\" in"))
        #expect(source.contains("-only-testing:GanchoiOSUITests/OutboundPrivacyUITests"))
        let scopedCoverage = source.components(
            separatedBy: #"echo "Coverage scope: $UI_EVIDENCE_LABEL""#)
        #expect(scopedCoverage.count == 3, "each coverage summary must name its scope")
        let macOSLabel =
            "UI_EVIDENCE_LABEL: ${{ inputs.scope == 'feature-stress' && 'macOS feature stress (10x)'"
        let iOSLabel =
            "UI_EVIDENCE_LABEL: ${{ inputs.scope == 'feature-stress' && 'iOS feature stress (10x)'"
        for label in [macOSLabel, iOSLabel] {
            #expect(
                source.components(separatedBy: label).count == 3,
                "evidence and coverage must share every stress label")
        }
    }

    @Test("Three full-suite shards run every macOS UI test class exactly once")
    func shardsCoverEveryClassOnce() throws {
        let root = LocalizationTests.repoRoot
        var sharded: [String] = []
        for shard in 1...3 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [
                root.appendingPathComponent("scripts/ui_test_shard.py").path, "\(shard)/3"
            ]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            let lines = try #require(String(bytes: data, encoding: .utf8)).split(separator: "\n")
            #expect(!lines.isEmpty, "shard \(shard) is empty")
            sharded += lines.map { String($0.dropFirst("-only-testing:GanchoUITests/".count)) }
        }

        let declaration = try NSRegularExpression(
            pattern: #"^(?:final )?class (\w+)\s*:\s*\w*XCTestCase"#, options: .anchorsMatchLines)
        var classes: Set<String> = []
        let tests = root.appendingPathComponent("Tests/GanchoUITests")
        let files = try #require(
            FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in declaration.matches(in: text, range: NSRange(text.startIndex..., in: text))
            {
                classes.insert((text as NSString).substring(with: match.range(at: 1)))
            }
        }
        #expect(sharded.count == Set(sharded).count, "a class runs in two shards")
        #expect(Set(sharded) == classes)
    }

    private func workflow() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ui-tests.yml"),
            encoding: .utf8)
    }

    @Test(
        arguments: [
            "full", "ios-full", "interaction-stress", "ios-interaction-stress", "feature-stress",
            "",
            "full; touch INJECTED", "-skip-testing:GanchoUITests"
        ], ["macos", "ios"])
    func routesOnlyKnownScopes(scope: String, platform: String) throws {
        let source = try workflow()
        let variable = platform == "macos" ? "GANCHO_UI_SCOPE" : "GANCHO_IOS_UI_SCOPE"
        let start = try #require(source.range(of: "          case \"$\(variable)\" in"))
        let end = try #require(
            source.range(of: "          esac", range: start.upperBound..<source.endIndex))
        let routing = String(source[start.lowerBound..<end.upperBound])
        #expect(source.contains(#""${test_arguments[@]}""#))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-ui-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Execute only the closed scope switch, never xcodebuild or GUI automation.
        process.arguments = ["-c", routing + #"; printf '%s\0' "${test_arguments[@]}""#]
        process.environment = [variable: scope, "PATH": "/usr/bin:/bin"]
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let arguments = try #require(String(bytes: data, encoding: .utf8)).split(separator: "\0")
            .map(
                String.init)
        assertRoute(
            arguments: arguments, exitStatus: process.terminationStatus,
            platform: platform, scope: scope)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("INJECTED").path))
    }
    private func assertRoute(
        arguments: [String], exitStatus: Int32, platform: String, scope: String
    ) {
        switch (platform, scope) {
        case (_, "full"):
            #expect(exitStatus == 0)
            let target = platform == "macos" ? "GanchoUITests" : "GanchoiOSUITests"
            #expect(arguments == ["-only-testing:\(target)"])
        case ("ios", "ios-full"):
            #expect(exitStatus == 0)
            #expect(arguments == ["-only-testing:GanchoiOSUITests"])
        case ("macos", "interaction-stress"):
            let suites = [
                "PasteBackUITests", "ReuseSuggestionUITests", "ClipLargePreviewUITests",
                "ClipTitleEditingUITests", "PanelBoardUITests", "PanelReproUITests",
                "SourceAppFilterUITests", "VisualLibraryUITests"
            ]
            #expect(exitStatus == 0)
            #expect(
                arguments == ["-test-iterations", "10"]
                    + suites.map { "-only-testing:GanchoUITests/\($0)" })
        case ("macos", "feature-stress"):
            #expect(exitStatus == 0)
            #expect(
                arguments == [
                    "-test-iterations", "10",
                    "-only-testing:GanchoUITests/LibrarySnippetDraftUITests",
                    "-only-testing:GanchoUITests/VisualLibraryUITests",
                    "-only-testing:GanchoUITests/ReuseSuggestionUITests",
                    "-only-testing:GanchoUITests/TranslationCapabilityUITests",
                    "-only-testing:GanchoUITests/SelectedContextUITests",
                    "-only-testing:GanchoUITests/TextRecipeUITests"
                ])
        case ("ios", "feature-stress"):
            #expect(exitStatus == 0)
            #expect(
                arguments == [
                    "-test-iterations", "10",
                    "-only-testing:GanchoiOSUITests/TranslationCapabilityUITests",
                    "-only-testing:GanchoiOSUITests/ClipTitleEditingUITests"
                ])
        case ("ios", "ios-interaction-stress"):
            #expect(exitStatus == 0)
            #expect(
                arguments == [
                    "-test-iterations", "10",
                    "-only-testing:GanchoiOSUITests/OutboundPrivacyUITests"
                ])
        default:
            #expect(exitStatus == 2)
            #expect(arguments == ["::error::Unsupported UI test scope\n"])
        }
    }

}
