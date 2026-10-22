import AppKit
import XCTest

/// The panel screens the README and website show, captured from the real app
/// with synthetic clips only: capture stays stopped (the real clipboard is
/// never read), the panel is opaque and placed, and the app renders its own
/// panel window, so nothing else on screen can end up in a marketing image.
/// `make ui-evidence` exports the attachments after `make test-ui`.
final class ProductScreensUITests: XCTestCase {
    private var renders: URL!

    override func setUpWithError() throws {
        renders = try DesignSnapshot.makeRenderDirectory()
    }

    override func tearDownWithError() throws {
        if let renders { try? FileManager.default.removeItem(at: renders) }
    }

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-visual-library", "-seed-peek-link", "-force-free-tier",
                "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.screens.\(UUID().uuidString)",
                "-ui-test-snapshot-dir", renders.path
            ] + extra
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.element(boundBy: 4).waitForExistence(timeout: 15),
            "the visual-library (4) and peek-link (1) seeds must list five rows")
        XCTAssertFalse(
            app.descendants(matching: .any)["capture-notice"].firstMatch.exists,
            "marketing screens must not show the expected paused banner")
        return app
    }

    @MainActor
    private func select(_ predicate: NSPredicate, in app: XCUIApplication) {
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        let row = rows.matching(predicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    @MainActor
    private func keep(_ app: XCUIApplication, _ name: String) throws {
        XCTAssertTrue(app.dialogs["history-panel"].firstMatch.exists)
        let image = try DesignSnapshot.renderWindow(titled: "Gancho", named: name, in: renders)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLinkPeekLight() throws {
        let app = launch(["-appearance", "light"])
        defer { app.terminate() }
        select(NSPredicate(format: "label CONTAINS %@", "example.com"), in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-link-hero"].firstMatch.waitForExistence(
                timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["peek-dock"].firstMatch.exists)
        try keep(app, "screen-panel-peek")
    }

    /// The Text size preference at Large: the release screen for 0.9.1.
    @MainActor
    func testLinkPeekLargeText() throws {
        let app = launch(["-appearance", "light", "-panel-text-size", "large"])
        defer { app.terminate() }
        select(NSPredicate(format: "label CONTAINS %@", "example.com"), in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-link-hero"].firstMatch.waitForExistence(
                timeout: 5))
        try keep(app, "screen-panel-large-text")
    }

    @MainActor
    func testGalleryDark() throws {
        let app = launch(["-appearance", "dark", "-panel-layout", "gallery"])
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["panel-gallery"].firstMatch.waitForExistence(timeout: 5)
        )
        select(NSPredicate(format: "label CONTAINS %@", "#008080"), in: app)
        try keep(app, "screen-panel-gallery")
    }

    @MainActor
    func testAmbientImageDark() throws {
        let app = launch(["-appearance", "dark", "-panel-ambient-tint", "YES"])
        defer { app.terminate() }
        select(
            NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "image", "•••"),
            in: app)
        try keep(app, "screen-panel-ambient")
    }
}
