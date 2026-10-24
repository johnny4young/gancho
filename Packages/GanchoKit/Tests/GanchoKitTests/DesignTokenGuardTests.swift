import Foundation
import Testing

/// App views take colour, elevation and motion from `GanchoDesign`, so the
/// contrast rule, the dark-mode elevation and Reduce Motion hold in one place.
@Suite("Design tokens — no literal curves, shadows, green text or accent bars in the apps")
struct DesignTokenGuardTests {
    static let curves = "snappy|easeIn|easeOut|easeInOut|linear|spring|bouncy|smooth"

    /// A literal curve, a bare `withAnimation {`, or a raw token that skips
    /// its `reduceMotion:` function animates regardless of Reduce Motion.
    @Test func appsUseMotionTokens() throws {
        let pattern = [
            #"\.("# + Self.curves + #")\(duration:"#,
            #"withAnimation\s*\{"#,
            #"(withAnimation|\.animation)\([^,)]*(?<!GanchoMotion)\.("# + Self.curves + #")\b"#,
            #"GanchoMotion\.(quick|smooth|leave|fade)\b(?!\()"#
        ].joined(separator: "|")
        let design = LocalizationTests.repoRoot
            .appendingPathComponent("Packages/GanchoKit/Sources/GanchoDesign")
        let offenders =
            try Self.matches(of: pattern)
            + Self.matches(of: pattern, in: design, excluding: ["GanchoMotion.swift"])
        #expect(offenders.isEmpty, "use GanchoMotion tokens: \(offenders)")
    }

    /// A literal shadow skips the dark-mode highlight that replaces it.
    @Test func appsUseElevationTokens() throws {
        let offenders = try Self.matches(of: #"\.shadow\("#)
        #expect(offenders.isEmpty, "use ganchoElevation: \(offenders)")
    }

    /// The accent, success and warning hues fail 4.5:1 as text on light
    /// surfaces, also inside a ternary. Widgets are skipped: the system renders
    /// their tint.
    @Test func appsUseReadableGreenInk() throws {
        let pattern =
            #"foreground(Style|Color)\((?![^)]*?(ReadableInk|ContrastingForeground)\()"#
            + #"[^)]*?(GanchoTokens\.Palette\.(accent|success|warning)\b"#
            + #"|(?<![\w)])\.(accentColor|tint|green)\b)"#
        let offenders = try Self.matches(of: pattern, excluding: ["GanchoWidgets"])
        #expect(offenders.isEmpty, "use accentInk, brandText or ReadableInk: \(offenders)")
    }

    /// A hand-built pill keeps the raw hue as text, below 4.5:1 on its own wash.
    @Test func appsBuildTintedPillsWithTheToken() throws {
        let offenders = try Self.matches(
            of: #"\.background\(\s*GanchoTokens\.Palette\.\w+(\(for: [^)]*\))?\.opacity\("#
                + #"[^)]*\),\s*in: Capsule\(\)"#)
        #expect(offenders.isEmpty, "use ganchoTintedPill: \(offenders)")
    }

    /// Selection, status and kind never show as a thin leading bar: use a wash,
    /// a full border, weight or an icon.
    @Test func noLeadingAccentBars() throws {
        let bar = #"\.frame\(width:\s*[2-6](\.\d+)?\)"#
        let design = LocalizationTests.repoRoot
            .appendingPathComponent("Packages/GanchoKit/Sources/GanchoDesign")
        let swift = try Self.matches(of: bar) + Self.matches(of: bar, in: design)
        #expect(swift.isEmpty, "no leading accent bars: \(swift)")

        let css = try NSRegularExpression(
            pattern: #"border-(left|inline-start)(-width)?\s*:|box-shadow:\s*inset\s+\d"#
                + #"|\bborder-[ls]-\d"#)
        for page in ["site/index.html", "site/styles.css"] {
            let url = LocalizationTests.repoRoot.appendingPathComponent(page)
            let text = try String(contentsOf: url, encoding: .utf8)
            let hits = css.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            #expect(hits == 0, "no leading accent bars in \(page)")
        }
    }

    private static func matches(
        of pattern: String,
        in root: URL = LocalizationTests.repoRoot.appendingPathComponent("Apps"),
        excluding skipped: [String] = []
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let files = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            if skipped.contains(where: url.pathComponents.contains) { continue }
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
