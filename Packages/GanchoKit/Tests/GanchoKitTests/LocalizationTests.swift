import Foundation
import Testing

/// Localization gate (pattern inherited from vitrine): bilingual from the
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

    @Test("Every key carries a translated Spanish value")
    func everyKeyHasSpanish() throws {
        for catalog in try Self.loadCatalogs() {
            #expect(!catalog.strings.isEmpty, "\(catalog.path) must not be empty")
            for (key, value) in catalog.strings {
                let unit =
                    ((value["localizations"] as? [String: Any])?["es"] as? [String: Any])?[
                        "stringUnit"] as? [String: Any]
                let state = unit?["state"] as? String
                let esValue = (unit?["value"] as? String) ?? ""
                #expect(
                    state == "translated",
                    "\(catalog.path): '\(key)' is missing a translated es value")
                #expect(
                    esValue.isEmpty == false,
                    "\(catalog.path): '\(key)' has an empty es value")
            }
        }
    }

    @Test("Format placeholders match between English keys and Spanish values")
    func placeholdersAligned() throws {
        for catalog in try Self.loadCatalogs() {
            for (key, value) in catalog.strings {
                let es =
                    (((value["localizations"] as? [String: Any])?["es"] as? [String: Any])?[
                        "stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(
                    Self.placeholders(in: key) == Self.placeholders(in: es),
                    "\(catalog.path): placeholder mismatch in '\(key)' → '\(es)'")
            }
        }
    }

    /// Sweep: every user-facing prose literal in app views must be a catalog
    /// key. Heuristic: `Text("…")`, `Label("…"`, and `String(localized:`
    /// literals containing a space (identifiers/symbols have none).
    @Test("No hardcoded user-facing prose outside the catalogs")
    func hardcodedSweep() throws {
        let catalogs = try Self.loadCatalogs()
        let knownKeys = Set(catalogs.flatMap(\.strings.keys))
        let appsDir = Self.repoRoot.appendingPathComponent("Apps")
        let files = try FileManager.default.subpathsOfDirectory(atPath: appsDir.path)
            .filter { $0.hasSuffix(".swift") }

        let pattern = #"(?:Text|Label)\(\s*"([^"\\]+)""#
        let regex = try NSRegularExpression(pattern: pattern)

        for file in files {
            let source = try String(
                contentsOf: appsDir.appendingPathComponent(file), encoding: .utf8)
            let matches = regex.matches(
                in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let literal = String(source[range])
                // Prose = contains a space; interpolations resolve at runtime.
                guard literal.contains(" "), !literal.contains("\\(") else { continue }
                #expect(
                    knownKeys.contains(literal),
                    "Apps/\(file): hardcoded prose '\(literal)' is not in any String Catalog")
            }
        }
    }

    private static func placeholders(in text: String) -> [String] {
        let pattern = #"%(\d+\$)?[@dDfFsScCuUxXo]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }
}
