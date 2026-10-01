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
                !source.contains("app.screenshot()"),
                "An application screenshot may contain other apps in \(file.lastPathComponent)")
        }
    }
}
