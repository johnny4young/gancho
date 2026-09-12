import XCTest

/// Native UI tests must never reopen the maintainer's database or preferences.
/// Presentation flags remain the test's choice: a plain agent launch is still
/// a plain agent launch, just backed by disposable encrypted storage.
@MainActor
final class GanchoUITestApplication: XCUIApplication {
    override func launch() {
        if !launchArguments.contains("-use-temp-durable-store")
            && !launchArguments.contains("-force-ephemeral-store")
        {
            launchArguments.append("-use-temp-durable-store")
        }
        if !launchArguments.contains("-ui-test-defaults-suite") {
            launchArguments += [
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.isolated.\(UUID().uuidString)"
            ]
        }
        if !launchArguments.contains("-isolate-ui-test-system-clipboard") {
            launchArguments.append("-isolate-ui-test-system-clipboard")
        }
        // Keep general UI automation independent of real StoreKit entitlements
        // and their CloudKit enablement. Purchases have a separate test target.
        if !launchArguments.contains("-force-free-tier") {
            launchArguments.append("-force-free-tier")
        }
        if !launchArguments.contains("-AppleLanguages") {
            launchArguments += ["-AppleLanguages", "(en)"]
        }
        super.launch()
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
