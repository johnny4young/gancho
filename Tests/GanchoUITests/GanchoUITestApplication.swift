import XCTest

/// Native UI tests must never reopen the maintainer's database or preferences.
/// Presentation flags remain the test's choice: a plain agent launch is still
/// a plain agent launch, just backed by disposable encrypted storage.
@MainActor
final class GanchoUITestApplication: XCUIApplication {
    override func launch() {
        launchArguments = Self.isolatedArguments(launchArguments)
        // Evidence is rendered by the app itself (`keepRender`), never copied
        // from the screen.
        if !launchArguments.contains("-ui-test-snapshot-dir") {
            let renders = FileManager.default.temporaryDirectory
                .appendingPathComponent("gancho-evidence-\(UUID().uuidString)", isDirectory: true)
            if (try? FileManager.default.createDirectory(
                at: renders, withIntermediateDirectories: true)) != nil
            {
                launchArguments += ["-ui-test-snapshot-dir", renders.path]
            }
        }
        super.launch()
    }

    static func isolatedArguments(_ original: [String]) -> [String] {
        var arguments = original
        if !arguments.contains("-use-temp-durable-store")
            && !arguments.contains("-force-ephemeral-store")
        {
            arguments.append("-use-temp-durable-store")
        }
        if !arguments.contains("-ui-test-defaults-suite") {
            arguments += [
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.isolated.\(UUID().uuidString)"
            ]
        }
        if !arguments.contains("-isolate-ui-test-system-clipboard") {
            arguments.append("-isolate-ui-test-system-clipboard")
        }
        // Keep general UI automation independent of real StoreKit entitlements
        // and their CloudKit enablement. Purchases have a separate test target.
        if !arguments.contains("-force-free-tier") {
            arguments.append("-force-free-tier")
        }
        if !arguments.contains("-AppleLanguages") {
            arguments += ["-AppleLanguages", "(en)"]
        }
        return arguments
    }
}

/// Target only the running test process through its existing per-launch nonce.
/// Unlike global URL opening this cannot choose an installed copy or relaunch
/// the app and reset the state a persistence test is exercising.
enum GanchoUITestCommands {
    static func post(_ command: String, token: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.johnny4young.gancho.menu-bar-command.\(command)"),
            object: token, userInfo: nil, options: [.deliverImmediately])
    }
}
