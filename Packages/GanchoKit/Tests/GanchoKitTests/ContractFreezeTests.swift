import Foundation
import Testing

/// The frozen store contract gate. `GanchoClientStore` is the supported
/// third-party / cross-target subset; `FullClipStore` also composes first-party
/// facets. GRDB-shaped members live behind `@_spi(GanchoInternal)`. These tests
/// run in the normal package test job, so they act as the CI doc-coverage +
/// freeze gate without a separate DocC step: renaming a frozen facet,
/// un-documenting a requirement, or promoting a GRDB-shaped member back onto
/// the ambient public surface fails the build.
@Suite("Frozen client contract")
struct ContractFreezeTests {
    /// The twelve facets and two compositions that make up the frozen surface.
    static let facets = [
        "ClipReading", "ClipSearching", "SourceAppProviding", "ClipMutating",
        "ReuseSuggestionProviding", "ClipEnriching", "BoardStoring", "SnippetStoring",
        "StoreStatsProviding", "PrivateActivityReceiptStoring", "ExportProviding",
        "StoreMaintaining"
    ]
    static let compositions = ["GanchoClientStore", "FullClipStore"]

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GanchoKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // GanchoKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
    }

    private static func source(_ components: String...) throws -> String {
        let url = components.reduce(repoRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func clientContract() throws -> String {
        try source("Packages", "GanchoKit", "Sources", "GanchoKit", "ClientContract.swift")
    }

    @Test func everyFacetAndCompositionIsDeclared() throws {
        let src = try Self.clientContract()
        for facet in Self.facets {
            #expect(
                src.contains("public protocol \(facet):"),
                "frozen facet `\(facet)` must stay declared in ClientContract.swift")
        }
        for composition in Self.compositions {
            #expect(
                src.contains("typealias \(composition)"),
                "frozen composition `\(composition)` must stay declared")
        }
    }

    /// Every requirement inside a frozen facet protocol must carry a doc comment
    /// — the doc-coverage half of the freeze. Walks each `public protocol …`
    /// block and asserts each `func`/`var` requirement is preceded by `///`.
    @Test func everyFacetRequirementIsDocumented() throws {
        let lines = try Self.clientContract().components(separatedBy: "\n")
        var undocumented: [String] = []
        var currentProtocol: String?

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let match = Self.facets.first(where: {
                raw.contains("public protocol \($0):")
            }) {
                currentProtocol = match
                continue
            }
            // A frozen protocol ends at its closing brace in column 0.
            if currentProtocol != nil, raw == "}" {
                currentProtocol = nil
                continue
            }
            guard let proto = currentProtocol,
                line.hasPrefix("func ") || line.hasPrefix("var ")
            else { continue }
            // The preceding line must be a doc comment, skipping blank lines and
            // attribute lines (`@discardableResult`, …) that sit between the
            // `///` block and the requirement.
            let previous = lines[..<index].reversed().first {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("@")
            }
            if previous?.trimmingCharacters(in: .whitespaces).hasPrefix("///") != true {
                undocumented.append("\(proto): \(line)")
            }
        }
        #expect(
            undocumented.isEmpty,
            "frozen facet requirements missing a doc comment: \(undocumented)")
    }

    /// GRDB-shaped members that are NOT facet witnesses must stay behind
    /// `@_spi(GanchoInternal)`, so they leave the ambient app-facing / external
    /// public surface. Promoting them back to plain `public` fails here.
    @Test func grdbShapedMembersStayBehindSPI() throws {
        let store = try Self.source(
            "Packages", "GanchoKit", "Sources", "GanchoKit", "GRDBClipboardStore.swift")
        for member in ["func migrate() throws", "func thumbnailURL(for id: UUID)"] {
            guard let range = store.range(of: member) else {
                Issue.record("expected `\(member)` in GRDBClipboardStore.swift")
                continue
            }
            let preamble = store[..<range.lowerBound]
            #expect(
                preamble.hasSuffix("@_spi(GanchoInternal)\n    public ")
                    || preamble.hasSuffix("@_spi(GanchoInternal) public "),
                "`\(member)` must stay behind @_spi(GanchoInternal)")
        }
    }

    /// The architecture doc records the frozen surface, so the contract has a
    /// human-readable freeze record alongside the compiler-enforced one.
    @Test func architectureDocumentsTheFrozenContract() throws {
        let doc = try Self.source("docs", "ARCHITECTURE.md")
        #expect(doc.contains("Frozen client contract"))
        for name in Self.facets + Self.compositions {
            #expect(doc.contains(name), "ARCHITECTURE.md must list the frozen facet `\(name)`")
        }
    }
}
