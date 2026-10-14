import AppKit
import XCTest

/// Launch a fresh accessory instance through LaunchServices with explicit
/// isolation arguments, without XCTest requiring foreground activation.
@MainActor
final class SignedHandoffApplication {
    var launchArguments: [String] = []
    private(set) var commandNonce = ""
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
        configuration.arguments = GanchoUITestApplication.isolatedArguments(
            launchArguments + ["-command-nonce", commandNonce])
        application = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path), configuration: configuration)
        XCTAssertEqual(application?.executableURL?.lastPathComponent, "Gancho")
    }

    func terminate() {
        guard let application, !application.isTerminated else { return }
        if !application.terminate() { application.forceTerminate() }
        let deadline = Date().addingTimeInterval(8)
        while !application.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(application.isTerminated, "Cleanup must stop only the exact owner process")
    }
}
