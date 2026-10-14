import AppKit
import XCTest

/// Launch the exact executable with explicit arguments. Neither foreground
/// activation nor LaunchServices argument forwarding is required.
@MainActor
final class SignedHandoffApplication {
    var launchArguments: [String] = []
    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }
    var processIdentifier: pid_t? { process?.processIdentifier }

    func launch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GANCHO_DISPOSABLE_SIGNED_HOST"] == "github-hosted",
            NSUserName() == "runner"
        else {
            throw NSError(domain: "GanchoSignedIntegration", code: 1)
        }
        let path = try XCTUnwrap(environment["GANCHO_SIGNED_APP"])
        let child = Process()
        child.executableURL = URL(fileURLWithPath: path)
            .appendingPathComponent("Contents/MacOS/Gancho")
        child.arguments = GanchoUITestApplication.isolatedArguments(launchArguments)
        child.environment = environment.filter {
            !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("XCTest")
                && !$0.key.hasPrefix("XCInject")
        }
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        process = child
        try child.run()
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(process.isRunning, "Cleanup must stop only the exact child process")
    }
}
