import Foundation
import Testing

@Suite("Native UI evidence is rendered by Gancho, never copied from the screen")
struct UITestEvidenceHygieneTests {
    @Test("Attachments never copy a screen region")
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
                screenCopy(in: source) == nil,
                "Use keepRender: a screenshot may contain other apps in \(file.lastPathComponent)")
        }
    }

    @Test("Screen copies are found on any element or receiver")
    func screenCopyDetection() {
        #expect(screenCopy(in: "add(XCTAttachment(screenshot: app.screenshot()))") != nil)
        #expect(screenCopy(in: "_ = XCUIApplication().screenshot()") != nil)
        #expect(screenCopy(in: "_ = app.dialogs[\"history-panel\"].screenshot()") != nil)
        #expect(screenCopy(in: "let shot = XCTAttachment(\n    screenshot: shot)") != nil)
        #expect(
            screenCopy(in: "try keepRender(of: \"history-panel\", in: app, named: name)") == nil)
    }

    /// An element screenshot is still a copy of the screen region under it.
    private func screenCopy(in source: String) -> Range<String.Index>? {
        source.range(
            of: #"\.screenshot\(\)|XCTAttachment\(\s*screenshot:"#, options: .regularExpression)
    }
}
