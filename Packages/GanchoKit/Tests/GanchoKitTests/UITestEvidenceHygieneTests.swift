import Foundation
import Testing

@Suite("Native UI evidence stays scoped to Gancho components")
struct UITestEvidenceHygieneTests {
    @Test("Manual attachments never capture the whole desktop or application surface")
    func scopedAttachments() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("Tests/GanchoUITests")
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(
                source.range(of: #"\bXCUIScreen\b"#, options: .regularExpression) == nil,
                "Use a scoped component in \(file.lastPathComponent)")
            #expect(
                applicationScreenshot(in: source) == nil,
                "An application screenshot may contain other apps in \(file.lastPathComponent)")
        }
    }

    @Test("Application screenshots are found under any receiver name")
    func applicationScreenshotDetection() {
        #expect(
            applicationScreenshot(in: "add(XCTAttachment(screenshot: app.screenshot()))") != nil)
        #expect(
            applicationScreenshot(in: "let gancho = XCUIApplication()\n_ = gancho.screenshot()")
                != nil)
        #expect(applicationScreenshot(in: "_ = XCUIApplication().screenshot()") != nil)
        #expect(applicationScreenshot(in: "_ = app.dialogs[\"history-panel\"].screenshot()") == nil)
    }

    /// Receivers are `app` plus every name bound to `XCUIApplication(...)` in the file.
    private func applicationScreenshot(in source: String) -> Range<String.Index>? {
        var receivers = ["app", #"XCUIApplication\([^)]*\)"#]
        let binding = #/(?:let|var)\s+(\w+)\s*(?::\s*XCUIApplication\s*)?=\s*XCUIApplication\(/#
        receivers += source.matches(of: binding).map { String($0.1) }
        let pattern = #"\b(?:"# + receivers.joined(separator: "|") + #")\s*\.screenshot\(\)"#
        return source.range(of: pattern, options: .regularExpression)
    }
}
