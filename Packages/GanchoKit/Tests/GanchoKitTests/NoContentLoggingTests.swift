import Foundation
import Testing

/// The release-checklist sweep, automated: engine modules must contain NO
/// logging calls at all (clipboard content must never be loggable), and app
/// debug prints must stay on an explicit content-free allowlist.
@Suite("Security model — no content logging")
struct NoContentLoggingTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Logging tokens that could carry content into the unified log.
    static let forbidden = ["print(", "NSLog(", "os_log(", "Logger("]

    /// App-side debug lines audited as content-free (path suffix: token).
    static let allowlist: [(file: String, token: String)] = [
        ("Apps/GanchoMac/PanelController.swift", "print(\"panel: open took")
    ]

    @Test("Engine modules contain no logging calls")
    func engineModulesAreSilent() throws {
        let sources = Self.repoRoot.appendingPathComponent("Packages/GanchoKit/Sources")
        for file in try Self.swiftFiles(under: sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in Self.forbidden {
                for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated()
                {
                    guard line.contains(token) else { continue }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // String literals about logging (classifier keywords,
                    // docs) are fine; calls are not.
                    guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///"),
                        !Self.insideStringLiteral(line: String(line), token: token)
                    else { continue }
                    Issue.record(
                        "\(file.lastPathComponent):\(number + 1) uses \(token) in an engine module — content could leak into logs"
                    )
                }
            }
        }
    }

    @Test("App debug prints stay on the audited allowlist")
    func appPrintsAreAllowlisted() throws {
        let apps = Self.repoRoot.appendingPathComponent("Apps")
        for file in try Self.swiftFiles(under: apps) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                guard line.contains("print("),
                    !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                else { continue }
                let allowed = Self.allowlist.contains { entry in
                    file.path.hasSuffix(entry.file) && line.contains(entry.token)
                }
                #expect(
                    allowed,
                    "\(file.lastPathComponent):\(number + 1): unaudited print — audit it and allowlist, or remove"
                )
            }
        }
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .map { root.appendingPathComponent($0) }
    }

    /// Cheap check: the token appears inside a quoted literal on this line
    /// (e.g. the classifier's "print(" python keyword marker).
    private static func insideStringLiteral(line: String, token: String) -> Bool {
        guard let range = line.range(of: token) else { return false }
        let before = line[line.startIndex..<range.lowerBound]
        return before.count(where: { $0 == "\"" }) % 2 == 1
    }
}
