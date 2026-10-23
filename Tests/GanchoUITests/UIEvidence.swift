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
        let path = try XCTUnwrap(
            arguments.firstIndex(of: "-ui-test-snapshot-dir").flatMap {
                arguments.dropFirst($0 + 1).first
            }, "launch with GanchoUITestApplication to keep rendered evidence")
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let file = UUID().uuidString
        // A directory the test passed itself may hold its own renders.
        let existed = FileManager.default.fileExists(atPath: directory.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(
                at: existed ? directory.appendingPathComponent("\(file).png") : directory)
        }
        let png = try DesignSnapshot.requestRender(of: window, named: file, in: directory)
        let attachment = XCTAttachment(
            data: try Data(contentsOf: png), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
