import Foundation
import Testing

/// App views take colour, elevation and motion from `GanchoDesign`, so the
/// contrast rule, the dark-mode elevation and Reduce Motion hold in one place.
@Suite("Design tokens — no literal curves, shadows or green text in the apps")
struct DesignTokenGuardTests {
    static let curves = "snappy|easeIn|easeOut|easeInOut|linear|spring|bouncy|smooth"

    /// A literal curve or a bare `withAnimation {` animates regardless of
    /// Reduce Motion.
    @Test func appsUseMotionTokens() throws {
        let pattern = [
            #"\.("# + Self.curves + #")\(duration:"#,
            #"withAnimation\s*\{"#,
            #"(withAnimation|\.animation)\([^,)]*(?<!GanchoMotion)\.("# + Self.curves + #")\b"#
        ].joined(separator: "|")
        let offenders = try Self.matches(of: pattern)
        #expect(offenders.isEmpty, "use GanchoMotion tokens: \(offenders)")
    }

    /// A literal shadow skips the dark-mode highlight that replaces it.
    @Test func appsUseElevationTokens() throws {
        let offenders = try Self.matches(of: #"\.shadow\("#)
        #expect(offenders.isEmpty, "use ganchoElevation: \(offenders)")
    }

    /// The accent and status greens fail 4.5:1 as text on light surfaces.
    @Test func appsUseReadableGreenInk() throws {
        let pattern =
            #"foreground(Style|Color)\((GanchoTokens\.Palette\.(accent|success)"#
            + #"|\.accentColor|Color\.accentColor|\.green)\)"#
        let offenders = try Self.matches(of: pattern)
        #expect(offenders.isEmpty, "use accentInk, brandText or ReadableInk: \(offenders)")
    }

    private static func matches(of pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let apps = LocalizationTests.repoRoot.appendingPathComponent("Apps")
        let files = try #require(
            FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let bound = Range(match.range, in: text)?.lowerBound else { continue }
                let line = text[..<bound]
                    .split(separator: "\n", omittingEmptySubsequences: false).count
                offenders.append("\(url.lastPathComponent):\(line)")
            }
        }
        return offenders
    }
}
