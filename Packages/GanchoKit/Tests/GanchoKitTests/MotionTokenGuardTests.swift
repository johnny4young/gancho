import Foundation
import Testing

/// Every animation in the app goes through `GanchoMotion`, so Reduce Motion is
/// honoured in one place. A literal curve or a bare `withAnimation {` would
/// animate regardless of the setting.
@Suite("Motion tokens — no literal curves in the apps")
struct MotionTokenGuardTests {
    static let curves = "snappy|easeIn|easeOut|easeInOut|linear|spring|bouncy|smooth"
    static let pattern = [
        #"\.("# + curves + #")\(duration:"#,
        #"withAnimation\s*\{"#,
        #"withAnimation\(\.("# + curves + #")\b"#,
        #"\.animation\(\.("# + curves + #")\b"#
    ].joined(separator: "|")

    @Test func appsUseMotionTokens() throws {
        let literal = try NSRegularExpression(pattern: Self.pattern)
        let apps = LocalizationTests.repoRoot.appendingPathComponent("Apps")
        let files = try #require(
            FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in literal.matches(in: text, range: range) {
                let line = text[..<Range(match.range, in: text)!.lowerBound]
                    .split(separator: "\n", omittingEmptySubsequences: false).count
                offenders.append("\(url.lastPathComponent):\(line)")
            }
        }
        #expect(offenders.isEmpty, "use GanchoMotion tokens: \(offenders)")
    }
}
