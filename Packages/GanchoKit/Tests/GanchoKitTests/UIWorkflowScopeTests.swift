import Foundation
import Testing

@Suite("Hosted UI scope routing")
struct UIWorkflowScopeTests {
    private func workflow() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ui-tests.yml"),
            encoding: .utf8)
    }

    @Test(arguments: [
        "full", "interaction-stress", "", "full; touch INJECTED", "-skip-testing:GanchoUITests"
    ])
    func routesOnlyKnownScopes(scope: String) throws {
        let source = try workflow()
        let start = try #require(source.range(of: "          case \"$GANCHO_UI_SCOPE\" in"))
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
        process.environment = ["GANCHO_UI_SCOPE": scope, "PATH": "/usr/bin:/bin"]
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
        switch scope {
        case "full":
            #expect(process.terminationStatus == 0)
            #expect(arguments == ["-only-testing:GanchoUITests"])
        case "interaction-stress":
            let suites = [
                "PasteBackUITests", "ReuseSuggestionUITests", "ClipLargePreviewUITests",
                "ClipTitleEditingUITests", "PanelBoardUITests", "PanelReproUITests",
                "SourceAppFilterUITests", "VisualLibraryUITests"
            ]
            #expect(process.terminationStatus == 0)
            #expect(
                arguments == ["-test-iterations", "10"]
                    + suites.map { "-only-testing:GanchoUITests/\($0)" })
        default:
            #expect(process.terminationStatus == 2)
            #expect(arguments == ["::error::Unsupported UI test scope\n"])
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("INJECTED").path))
    }
}
