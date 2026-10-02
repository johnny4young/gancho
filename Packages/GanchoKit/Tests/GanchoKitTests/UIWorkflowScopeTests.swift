import Foundation
import Testing

@Suite("Hosted UI scope routing")
struct UIWorkflowScopeTests {
    @Test("Repeated suites have separate execution allocation and preserve full platform gates")
    func stressAllocation() throws {
        let source = try workflow()
        #expect(
            source.contains(
                "timeout-minutes: ${{ (inputs.scope == 'interaction-stress' || "
                    + "inputs.scope == 'feature-stress') && 90 || 45 }}"))
        #expect(source.contains("if: ${{ inputs.scope != 'ios-interaction-stress' }}"))
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
            "full", "interaction-stress", "ios-interaction-stress", "feature-stress", "",
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
