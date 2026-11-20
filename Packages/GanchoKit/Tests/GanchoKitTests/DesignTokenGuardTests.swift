import Foundation
import Testing

/// App views take colour, elevation and motion from `GanchoDesign`, so the
/// contrast rule, the dark-mode elevation and Reduce Motion hold in one place.
@Suite("Design tokens — no literal curves, shadows, raw hues, stray accent or accent bars")
struct DesignTokenGuardTests {
    static let curves = "snappy|easeIn|easeOut|easeInOut|linear|spring|bouncy|smooth"

    /// A literal curve, a bare `withAnimation {`, or a raw token that skips
    /// its `reduceMotion:` function animates regardless of Reduce Motion.
    @Test func appsUseMotionTokens() throws {
        let pattern = [
            #"\.("# + Self.curves + #")\(duration:"#,
            #"withAnimation\s*\{"#,
            #"(withAnimation|\.animation)\([^,)]*(?<!GanchoMotion)\.("# + Self.curves + #")\b"#,
            #"GanchoMotion\.(quick|smooth|leave|fade|tick)\b(?!\()"#
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

    /// The warning hue and the system tints fail 4.5:1 as text on light
    /// surfaces, also inside a ternary. Widgets are skipped: the system renders
    /// their tint.
    @Test func appsUseReadableInk() throws {
        let pattern =
            #"foreground(Style|Color)\((?![^)]*?(ReadableInk|ContrastingForeground)\()"#
            + #"[^)]*?(GanchoTokens\.Palette\.warning\b"#
            + #"|(?<![\w)])\.(accentColor|tint|green)\b)"#
        let offenders = try Self.matches(of: pattern, excluding: ["GanchoWidgets"])
        #expect(offenders.isEmpty, "use an ink token, warningInk or ReadableInk: \(offenders)")
    }

    /// Indigo, amber, agent blue and kind tints are retired; red is a token kept
    /// for errors, Delete, denied and a secret's last minute. A destructive
    /// button's role draws its own red.
    @Test func appsDoNotUseRetiredSystemHues() throws {
        let hues = #"(Color)?\.(red|orange|blue|indigo|purple|yellow|teal|pink|mint|cyan|brown)\b"#
        let pattern =
            #"\.(foregroundStyle|foregroundColor|tint|fill|background|stroke|strokeBorder)\([^)]*?"#
            + #"(?<![\w)])"# + hues + #"|\btint:\s*"# + hues
        let offenders = try Self.matches(of: pattern, excluding: ["GanchoWidgets"])
        #expect(offenders.isEmpty, "use Palette.danger, warningInk or a neutral ink: \(offenders)")
    }

    /// The system segmented style puts a white label on the control tint.
    @Test func appsUseTheGanchoSegmentedStyle() throws {
        let offenders = try Self.matches(of: #"\.pickerStyle\(\s*\.segmented\s*\)"#)
        #expect(offenders.isEmpty, "use ganchoSegmented(): \(offenders)")
    }

    /// Where each accent-bearing component may appear. The accent means
    /// "Return does this", so a new entry is a design decision, not a fix.
    static let accentBudget: [(pattern: String, files: Set<String>)] = [
        (#"\bLiveDot\("#, ["Apps/GanchoMac/PanelStatusFooter.swift"]),
        // The link peek's "Pastes as" names the same Return the dock's verb runs;
        // the action panel marks the row Return runs and filters with the caret;
        // the first-run lesson teaches that Return pastes.
        (
            #"\bReturnKeyCap\("#,
            [
                "Apps/GanchoMac/PeekLinkHero.swift", "Apps/GanchoMac/PeekTransformPopover.swift",
                "Apps/GanchoMac/PanelFirstRunStageView.swift",
                // The stack's next row is what Return pastes while it shows.
                "Apps/GanchoMac/PeekPasteStack.swift"
            ]
        ),
        (#"\.ganchoCaret\("#, ["Apps/GanchoMac/PeekTransformPopover.swift"]),
        (
            #"ganchoPrimaryVerb\(|PrimaryVerb\.ui"#,
            [
                "Apps/GanchoMac/PeekActionButton.swift", "Apps/GanchoiOS/CaptureView.swift",
                "Apps/GanchoiOS/ClipDetailView+Hero.swift",
                "Apps/GanchoKeyboard/KeyboardView.swift",
                "Apps/GanchoShare/ShareSheetView.swift",
                "Apps/GanchoWidgets/RecentClipsLargeView.swift",
                "Apps/GanchoWidgets/ClipLiveActivity.swift"
            ]
        ),
        (#"Palette\.brandGreen\b"#, ["Apps/GanchoMac/WrappedView.swift"])
    ]

    /// The apps cannot name the accent, its hex values or the system accent;
    /// they get it from the primary verb, the Return cap and the live dot.
    @Test func appsSpendTheAccentOnlyOnItsBudget() throws {
        let raw =
            #"Palette\.accent\w*|\bAccentText\b|ColorPair\b|controlAccentColor"#
            + #"|(?i:C8F53C|C3F22E|47750A|161C00)"#
        let offenders = try Self.matches(of: raw)
        #expect(offenders.isEmpty, "the accent stays inside GanchoDesign: \(offenders)")

        let widgets = try Self.matches(
            of: #"(?<![\w)])\.accentColor\b"#, excluding: ["GanchoWidgets"])
        #expect(widgets.isEmpty, "use the neutral tokens, not the system accent: \(widgets)")

        for entry in Self.accentBudget {
            let outside = try Self.matches(of: entry.pattern, relativePaths: true).filter {
                !entry.files.contains(String($0.prefix { $0 != ":" }))
            }
            #expect(outside.isEmpty, "outside the accent budget: \(outside)")
        }
    }

    /// The budget cannot be bypassed from inside the module either: beside the
    /// tokens and the ink rule, only the primary verb, the caps and dot, and the
    /// search caret name the accent.
    @Test func designModuleSpendsTheAccentInFourPlaces() throws {
        let design = LocalizationTests.repoRoot
            .appendingPathComponent("Packages/GanchoKit/Sources/GanchoDesign")
        let offenders = try Self.matches(
            of: #"Palette\.accent(Text)?\b|ColorPair\.(accent|accentText)\b"#
                + #"|\b(AccentFill|OnAccentInk|AccentText)\("#,
            in: design,
            excluding: [
                "GanchoColors.swift", "ContrastingForeground.swift", "GanchoButtonStyle.swift",
                "KeyCap.swift", "SearchField.swift"
            ])
        #expect(offenders.isEmpty, "the accent has four places: \(offenders)")

        // The module draws the Return cap once: on the selected row's key.
        let caps = try Self.matches(
            of: #"\bReturnKeyCap\("#, in: design, excluding: ["Components.swift"])
        #expect(caps.isEmpty, "the Return cap marks the selected row only: \(caps)")
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

    static func matches(
        of pattern: String,
        in root: URL = LocalizationTests.repoRoot.appendingPathComponent("Apps"),
        excluding skipped: [String] = [], relativePaths: Bool = false
    ) throws -> [String] {
        let prefix = LocalizationTests.repoRoot.standardizedFileURL.path + "/"
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
                let path = url.standardizedFileURL.path
                let name =
                    relativePaths && path.hasPrefix(prefix)
                    ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
                offenders.append("\(name):\(line)")
            }
        }
        return offenders
    }
}
