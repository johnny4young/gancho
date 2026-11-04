import Foundation
import Testing

@Suite("Focused UI test workflow")
struct UITestFocusWorkflowTests {
    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: LocalizationTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("The script's own cases pass")
    func scriptSelfTest() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            LocalizationTests.repoRoot.appendingPathComponent("scripts/ui-test-focus.sh").path,
            "--self-test"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Requested tests reach the shell only through the environment")
    func inputsStayOutOfTheShell() throws {
        let workflow = try source(".github/workflows/ui-test-focus.yml")
        let allowedPrefixes = ["if: ", "FOCUS_TESTS: ", "FOCUS_ITERATIONS: "]
        for line in workflow.split(separator: "\n") where line.contains("inputs.") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            #expect(allowedPrefixes.contains { trimmed.hasPrefix($0) }, "\(trimmed)")
        }
    }

    @Test("Both platforms prove each requested test passed on the pinned Xcode")
    func everyJobVerifies() throws {
        let workflow = try source(".github/workflows/ui-test-focus.yml")
        let verify =
            #"./scripts/ui-test-focus.sh verify build/focus-evidence/tests.json "$FOCUS_TESTS""#
        #expect(workflow.components(separatedBy: verify).count == 3)
        #expect(workflow.components(separatedBy: "Xcode_26.6.app").count == 3)
    }

    @Test("A full-suite dispatch only supersedes the same commit and scope, on the pinned Xcode")
    func fullSuiteRunsCanBeCompared() throws {
        let workflow = try source(".github/workflows/ui-tests.yml")
        #expect(
            workflow.contains("group: ui-tests-${{ github.sha }}-${{ inputs.scope || 'full' }}"))
        #expect(workflow.components(separatedBy: "Xcode_26.6.app").count == 3)
    }
}
