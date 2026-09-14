import XCTest

/// Shared launcher for the suites that drive the Settings window. Each of them
/// used to compose the same argument list by hand, and the copies drifted (store
/// mode, language pin, onboarding suppression). One place owns the invariants:
///
/// - `-open-deep-link-on-launch gancho://settings` opens Settings in-process, so
///   Launch Services can never route the URL to another installed Gancho.
/// - `-has-seen-welcome YES`: a fresh defaults suite would otherwise open the
///   onboarding window on top of Settings and compete for key focus.
/// - `-AppleLanguages (en)`: identifiers are stable, but the window title and
///   any label lookup are localized.
///
/// The window is asserted, not skipped: with the in-process hook a missing
/// Settings window is a routing regression, not an environment limitation.
@MainActor
func launchSettingsWindow(
    extraArguments: [String] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
        [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-has-seen-welcome", "YES",
            "-open-deep-link-on-launch", "gancho://settings",
            "-AppleLanguages", "(en)"
        ] + extraArguments
    app.launch()
    guard app.windows["Settings"].firstMatch.waitForExistence(timeout: 8) else {
        XCTFail("Settings window not exposed to the UI runner", file: file, line: line)
        app.terminate()
        throw CocoaError(.fileNoSuchFile)
    }
    return app
}
