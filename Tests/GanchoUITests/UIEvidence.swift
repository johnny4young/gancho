import XCTest

extension XCTestCase {
    /// Attaches the app's own render of one of its windows as `name`. An
    /// element screenshot copies a screen region instead, so it can include
    /// any window covering the app and fails while the screen is locked.
    ///
    /// `window` is a window title or accessibility identifier, or `@sheet`
    /// for the visible sheet. The app must be a `GanchoUITestApplication`,
    /// which passes the render directory.
    @MainActor
    func keepRender(of window: String, in app: XCUIApplication, named name: String) throws {
        let arguments = app.launchArguments
        let index = try XCTUnwrap(
            arguments.firstIndex(of: "-ui-test-snapshot-dir"),
            "launch with GanchoUITestApplication to keep rendered evidence")
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let file = UUID().uuidString
        _ = try DesignSnapshot.renderWindow(titled: window, named: file, in: directory)
        let png = directory.appendingPathComponent("\(file).png")
        defer { try? FileManager.default.removeItem(at: png) }
        let attachment = XCTAttachment(
            data: try Data(contentsOf: png), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
