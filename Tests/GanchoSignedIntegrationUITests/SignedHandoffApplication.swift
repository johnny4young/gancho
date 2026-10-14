import AppKit
import XCTest

/// XCTest's launch waits for foreground activation, which an accessory app
/// need not acquire. Use AppKit while retaining the same disposable state.
@MainActor
final class SignedHandoffApplication {
    var launchArguments: [String] = []
    private var application: NSRunningApplication?

    var isRunning: Bool { application?.isTerminated == false }

    func launch() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GANCHO_DISPOSABLE_SIGNED_HOST"] == "github-hosted",
            NSUserName() == "runner"
        else {
            throw NSError(domain: "GanchoSignedIntegration", code: 1)
        }
        let path = try XCTUnwrap(environment["GANCHO_SIGNED_APP"])
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = GanchoUITestApplication.isolatedArguments(launchArguments)
        application = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path), configuration: configuration)
    }

    func terminate() {
        guard let application, !application.isTerminated else { return }
        XCTAssertTrue(application.terminate(), "The exact owner must accept a clean quit")
        let deadline = Date().addingTimeInterval(8)
        while !application.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(application.isTerminated, "The exact owner must finish its clean quit")
    }
}
