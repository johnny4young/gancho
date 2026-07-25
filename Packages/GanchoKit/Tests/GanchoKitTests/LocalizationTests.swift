import Foundation
import Testing

/// Localization gate: bilingual from the
/// first real string. Reads the app String Catalogs straight from the repo
/// (path-derived from #filePath), so the gate runs in plain `swift test`.
@Suite("Localization gate — en + es from day one")
struct LocalizationTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // file → GanchoKitTests
        .deletingLastPathComponent()  // → Tests
        .deletingLastPathComponent()  // → GanchoKit
        .deletingLastPathComponent()  // → Packages
        .deletingLastPathComponent()  // → repo root
    static let catalogPaths = [
        "Apps/GanchoMac/Localizable.xcstrings",
        "Apps/GanchoiOS/Localizable.xcstrings",
        // The widget extension is its own bundle with its own catalog.
        "Apps/GanchoWidgets/Localizable.xcstrings",
        // The keyboard extension, likewise.
        "Apps/GanchoKeyboard/Localizable.xcstrings"
    ]

    struct Catalog {
        var path: String
        var strings: [String: [String: Any]]
    }

    static func loadCatalogs() throws -> [Catalog] {
        try catalogPaths.map { path in
            let url = repoRoot.appendingPathComponent(path)
            let object =
                try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = (object?["strings"] as? [String: [String: Any]]) ?? [:]
            return Catalog(path: path, strings: strings)
        }
    }

    /// The es string unit(s) for a key: either a single `stringUnit`, or every
    /// category of a `variations.plural` (so pluralized keys validate too).
    static func esUnits(_ value: [String: Any]) -> [(state: String?, value: String)] {
        guard let es = (value["localizations"] as? [String: Any])?["es"] as? [String: Any] else {
            return []  // No es localization at all → let the emptiness be the failure.
        }
        if let unit = es["stringUnit"] as? [String: Any] {
            return [(unit["state"] as? String, unit["value"] as? String ?? "")]
        }
        if let plural = (es["variations"] as? [String: Any])?["plural"] as? [String: Any] {
            return plural.values
                .compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                .map { ($0["state"] as? String, $0["value"] as? String ?? "") }
        }
        // No es localization, or one with neither a stringUnit nor plural
        // variations: return empty so `#expect(!units.isEmpty, "…no es value")`
        // is the real guard, instead of a sentinel that silently passes it.
        return []
    }

    @Test("Every key carries a translated Spanish value")
    func everyKeyHasSpanish() throws {
        for catalog in try Self.loadCatalogs() {
            #expect(!catalog.strings.isEmpty, "\(catalog.path) must not be empty")
            for (key, value) in catalog.strings {
                let units = Self.esUnits(value)
                #expect(!units.isEmpty, "\(catalog.path): '\(key)' has no es value")
                for unit in units {
                    #expect(
                        unit.state == "translated",
                        "\(catalog.path): '\(key)' is missing a translated es value")
                    #expect(
                        unit.value.isEmpty == false,
                        "\(catalog.path): '\(key)' has an empty es value")
                }
            }
        }
    }

    @Test("Format placeholders match between English keys and Spanish values")
    func placeholdersAligned() throws {
        for catalog in try Self.loadCatalogs() {
            for (key, value) in catalog.strings {
                for unit in Self.esUnits(value) {
                    #expect(
                        Self.placeholders(in: key) == Self.placeholders(in: unit.value),
                        "\(catalog.path): placeholder mismatch in '\(key)' → '\(unit.value)'")
                }
            }
        }
    }

    // The sweep keeps catalog loading, literal discovery, and assertion context
    // together so localization failures point at the offending string.
    // swiftlint:disable function_body_length
    /// Sweep: every user-facing prose literal in app code must be a catalog key
    /// — and not merely *somewhere*, but in the catalog of EACH bundle that
    /// ships the file. Beyond SwiftUI `Text` / `Label`, it covers the
    /// declaration forms that also reach users: App Intents (`title`,
    /// `IntentDescription`, `IntentDialog`, a `dialog:` result) and WidgetKit
    /// gallery metadata (`configurationDisplayName`, `description`). Each bundle
    /// resolves a `LocalizedStringResource` from its OWN catalog, so a shared
    /// string shown in N bundles must be translated in all N.
    ///
    /// Enforcement is PER-BUNDLE, not "present in some catalog": that loophole
    /// is exactly what let the Save Clipboard intent ship English on iOS while
    /// it was localized for the widget. `Apps/GanchoShared` compiles into the
    /// iOS app, the widget AND the keyboard, but only the app + widget vend its
    /// App Intents to users, so those are the catalogs required (the keyboard
    /// extension does not surface them). Directories without their own catalog
    /// (`GanchoShare`, `GanchoMenuBarHelper`) fall back to "present in any".
    ///
    /// Two forms the sweep used to miss, both common enough to have shipped a
    /// gap. Interpolated copy counts: `Text("No clips for “\(query)”.")`
    /// resolves to the key `No clips for “%@”.`, and skipping those (the old
    /// capture group could not cross a `\(` at all) is how that very key
    /// shipped missing while Spanish users read English. And a declaration
    /// TYPED `LocalizedStringKey` is a key with no `Text(…)` around it —
    /// `case .today: "Today"` in a `-> LocalizedStringKey` switch.
    @Test("No hardcoded user-facing prose outside the catalogs")
    func hardcodedSweep() throws {
        // swiftlint:enable function_body_length
        let catalogs = try Self.loadCatalogs()
        let keysByCatalog = Dictionary(
            uniqueKeysWithValues: catalogs.map { ($0.path, Set($0.strings.keys)) })
        let anyCatalogKeys = Set(catalogs.flatMap(\.strings.keys))

        func requiredCatalogs(for file: String) -> [String] {
            if file.hasPrefix("GanchoMac/") { return ["Apps/GanchoMac/Localizable.xcstrings"] }
            if file.hasPrefix("GanchoiOS/") { return ["Apps/GanchoiOS/Localizable.xcstrings"] }
            if file.hasPrefix("GanchoWidgets/") {
                return ["Apps/GanchoWidgets/Localizable.xcstrings"]
            }
            if file.hasPrefix("GanchoKeyboard/") {
                return ["Apps/GanchoKeyboard/Localizable.xcstrings"]
            }
            if file.hasPrefix("GanchoShared/") {
                return [
                    "Apps/GanchoiOS/Localizable.xcstrings",
                    "Apps/GanchoWidgets/Localizable.xcstrings"
                ]
            }
            return []  // No dedicated catalog → fall back to "any catalog".
        }

        // Each pattern ends just BEFORE the opening quote of a user-facing
        // literal; `SwiftLiteralScanner` reads the literal itself, so
        // interpolated copy is covered instead of silently skipped.
        // Container/control patterns are deliberately NOT word-boundary
        // anchored: `Button(` must also match wrapper components such as
        // `ActionButton(` — a wrapper is exactly where a gap once hid.
        let literalPatterns = [
            #"(?:Text|Label)\(\s*(?=")"#,
            #"(?:Button|Toggle|Menu|Section)\(\s*(?=")"#,
            #"ActionButton\(\s*(?=")"#,
            #"\.(?:navigationTitle|alert|confirmationDialog)\(\s*(?=")"#,
            #"LocalizedString(?:Resource|Key)\(\s*(?=")"#,
            #"LocalizedString(?:Resource|Key)\s*=\s*(?=")"#,
            #"IntentDescription\(\s*(?=")"#,
            #"IntentDialog\(\s*(?=")"#,
            #"\bdialog:\s*(?=")"#,
            #"\.configurationDisplayName\(\s*(?=")"#,
            #"\.description\(\s*(?=")"#
        ]
        // A declaration typed `LocalizedStringKey` needs no `Text(…)` wrapper
        // to reach users: `case .today: "Today"` in a `-> LocalizedStringKey`
        // switch IS a catalog key, and so is every other literal in that body.
        // Each pattern ends ON the delimiter opening the body.
        let keyBodyPatterns: [(pattern: String, open: Character, close: Character)] = [
            (#"(?:->|:)\s*LocalizedStringKey\??\s*\{"#, "{", "}"),
            (#":\s*\[LocalizedStringKey\]\s*=\s*\["#, "[", "]")
        ]
        let literalRegexes = try literalPatterns.map { try NSRegularExpression(pattern: $0) }
        let keyBodyRegexes = try keyBodyPatterns.map {
            (regex: try NSRegularExpression(pattern: $0.pattern), open: $0.open, close: $0.close)
        }

        let appsDir = Self.repoRoot.appendingPathComponent("Apps")
        let files = try FileManager.default.subpathsOfDirectory(atPath: appsDir.path)
            .filter { $0.hasSuffix(".swift") }

        for file in files {
            let source = try String(
                contentsOf: appsDir.appendingPathComponent(file), encoding: .utf8)
            let required = requiredCatalogs(for: file)
            let wholeFile = NSRange(source.startIndex..., in: source)
            var literals: [[SwiftLiteralSegment]] = []
            for regex in literalRegexes {
                for match in regex.matches(in: source, range: wholeFile) {
                    guard let range = Range(match.range, in: source),
                        let segments = SwiftLiteralScanner.scan(
                            source, from: range.upperBound
                        ).segments
                    else { continue }
                    literals.append(segments)
                }
            }
            for (regex, open, close) in keyBodyRegexes {
                for match in regex.matches(in: source, range: wholeFile) {
                    guard let range = Range(match.range, in: source) else { continue }
                    let opened = source.index(before: range.upperBound)
                    let end = SwiftLiteralScanner.blockEnd(
                        in: source, openedAt: opened, open: open, close: close)
                    literals += SwiftLiteralScanner.literals(
                        in: source, range: source.index(after: opened)..<end)
                }
            }

            for segments in literals {
                let candidates = SwiftLiteralScanner.localizedKeys(for: segments)
                guard let key = candidates.first, Self.isUserFacingCopy(segments, key: key)
                else { continue }
                if required.isEmpty {
                    #expect(
                        candidates.contains(where: anyCatalogKeys.contains),
                        "Apps/\(file): hardcoded prose '\(key)' is not in any String Catalog")
                } else {
                    for catalog in required {
                        let keys = keysByCatalog[catalog] ?? []
                        #expect(
                            candidates.contains(where: keys.contains),
                            "Apps/\(file): '\(key)' is missing from \(catalog)")
                    }
                }
            }
        }
    }

    /// Is this literal user-facing copy — the thing a translator would touch?
    ///
    /// Prose contains a space; a lone Capitalized word is UI copy too ("Clear",
    /// "Share", "Recent"), while the lowercase single tokens that reach these
    /// call sites are SF Symbol names ("globe", "delete.left") and must not
    /// false-positive. That capitalization rule used to apply only to
    /// interactive-control patterns, which silently excused `Text("Recent")`
    /// and the `dialog: "Copied."` of an App Intent.
    ///
    /// An interpolated literal additionally needs a letter in its STATIC text:
    /// `"\(label): \(preview)"` and `"\(title) · \(count)"` compose values that
    /// are localized (or numeric) already, leaving a translator nothing to
    /// change, while `"No clips for “\(query)”."` plainly is copy.
    static func isUserFacingCopy(_ segments: [SwiftLiteralSegment], key: String) -> Bool {
        var staticText = ""
        var isInterpolated = false
        for segment in segments {
            switch segment {
            case .text(let text): staticText += text
            case .interpolation: isInterpolated = true
            }
        }
        if isInterpolated, !staticText.contains(where: \.isLetter) { return false }
        return key.contains(" ") || key.first?.isUppercase == true
    }

    private static func placeholders(in text: String) -> [String] {
        let pattern = #"%(\d+\$)?[@dDfFsScCuUxXo]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }
}
