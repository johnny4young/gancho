import AppKit
import XCTest

/// Launch a fresh accessory instance through LaunchServices with explicit
/// isolation arguments, without XCTest requiring foreground activation.
@MainActor
final class SignedHandoffApplication {
    var launchArguments: [String] = []
    private var commandNonce = ""
    private var application: NSRunningApplication?

    var isRunning: Bool { application?.isTerminated == false }
    var processIdentifier: pid_t? { application?.processIdentifier }

    func launch() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GANCHO_DISPOSABLE_SIGNED_HOST"] == "github-hosted",
            NSUserName() == "runner"
        else {
            throw NSError(domain: "GanchoSignedIntegration", code: 1)
        }
        let path = try XCTUnwrap(environment["GANCHO_SIGNED_APP"])
        commandNonce = UUID().uuidString
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        let waitsForFixtures = launchArguments.contains("-seed-sample-clips")
        let arguments = GanchoUITestApplication.isolatedArguments(
            launchArguments + ["-command-nonce", commandNonce]
                + (waitsForFixtures ? ["-ui-test-wait-for-fixtures"] : []))
        configuration.arguments = arguments
        application = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path), configuration: configuration)
        XCTAssertEqual(application?.executableURL?.lastPathComponent, "Gancho")
        try verifyArguments(arguments, owner: XCTUnwrap(application))
        if waitsForFixtures { try await waitForFixtures(arguments: arguments) }
    }

    private func waitForFixtures(arguments: [String]) async throws {
        let index = try XCTUnwrap(arguments.firstIndex(of: "-ui-test-defaults-suite"))
        let suite = arguments[index + 1]
        XCTAssertTrue(suite.hasPrefix("com.johnny4young.gancho.uitests."))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deadline = ContinuousClock.now + .seconds(30)
        while !defaults.bool(forKey: "ui-test-fixtures-ready"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard defaults.bool(forKey: "ui-test-fixtures-ready") else {
            throw NSError(
                domain: "GanchoSignedIntegration", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "All isolated fixtures must finish before exercising the helper"
                ])
        }
    }

    private func verifyArguments(_ expected: [String], owner: NSRunningApplication) throws {
        let query = Process()
        query.executableURL = URL(fileURLWithPath: "/bin/ps")
        query.arguments = ["-ww", "-p", String(owner.processIdentifier), "-o", "command="]
        let output = Pipe()
        query.standardOutput = output
        query.standardError = FileHandle.nullDevice
        try query.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        query.waitUntilExit()
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        let actual = text.split(whereSeparator: \.isWhitespace)
        let nonceMatches =
            actual.firstIndex(of: "-command-nonce").map { index in
                actual.indices.contains(index + 1) && actual[index + 1] == Substring(commandNonce)
            } ?? false
        guard query.terminationStatus == 0, nonceMatches,
            expected.allSatisfy({ actual.contains(Substring($0)) })
        else {
            throw NSError(
                domain: "GanchoSignedIntegration", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The exact owner process must receive all isolated launch arguments",
                    "ephemeral-argument": actual.contains("-force-ephemeral-store"),
                    "paused-argument": actual.contains("-start-capture-paused"),
                    "session-argument-matches": nonceMatches
                ])
        }
    }

    func terminate() {
        guard let application, !application.isTerminated else { return }
        if !application.terminate() { application.forceTerminate() }
        let deadline = Date().addingTimeInterval(8)
        while !application.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if !application.isTerminated {
            application.forceTerminate()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(application.isTerminated, "Cleanup must stop only the exact owner process")
    }
}
