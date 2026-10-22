import Foundation
import Testing

/// `Resources/Brand` is the single source for the mark. Every shipped copy must
/// stay byte-identical, and no surface may fall back to an SF Symbol stand-in.
@Suite("Brand assets — one source, exact copies")
struct BrandAssetParityTests {
    static let copies: [(source: String, copy: String)] = [
        (
            "gancho-mark.svg",
            "Apps/GanchoWidgets/Assets.xcassets/GanchoMark.imageset/gancho-mark.svg"
        ),
        ("gancho-mark.svg", "Apps/GanchoMac/Assets.xcassets/GanchoMark.imageset/gancho-mark.svg"),
        ("gancho-mark.svg", "site/assets/gancho-mark.svg"),
        (
            "gancho-mark-bare.svg",
            "Apps/GanchoMac/Assets.xcassets/GanchoMarkBare.imageset/gancho-mark-bare.svg"
        ),
        (
            "gancho-mark-template.svg",
            "Apps/GanchoWidgets/Assets.xcassets/GanchoMarkTemplate.imageset/gancho-mark-template.svg"
        )
    ]

    @Test(arguments: copies.map(\.copy))
    func copyMatchesTheBrandSource(_ copy: String) throws {
        let source = try #require(Self.copies.first { $0.copy == copy }?.source)
        let root = LocalizationTests.repoRoot
        let expected = try Data(
            contentsOf: root.appendingPathComponent("Resources/Brand/\(source)"))
        let actual = try Data(contentsOf: root.appendingPathComponent(copy))
        #expect(actual == expected, "\(copy) drifted from Resources/Brand/\(source)")
    }

    @Test func noSurfaceUsesThePaperclipSymbol() throws {
        let apps = LocalizationTests.repoRoot.appendingPathComponent("Apps")
        let files = try #require(
            FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("\"paperclip\"") { offenders.append(url.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "brand mark replaced by SF paperclip in \(offenders)")
    }
}
