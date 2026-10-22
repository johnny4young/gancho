import AppKit
import SnapshotTesting
import Testing

/// One check per PNG captured by the UI suite, against
/// `__Snapshots__/DesignSnapshotTests/screen.<name>.png`.
/// `GANCHO_SNAPSHOT_RECORD=all` re-records every baseline.
@Suite struct DesignSnapshotTests {
    static let captures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DesignSnapshotTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DesignSnapshots
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("build/design-snapshots")

    static var names: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: captures.path)) ?? []
        return files.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
    }

    static var record: SnapshotTestingConfiguration.Record {
        switch ProcessInfo.processInfo.environment["GANCHO_SNAPSHOT_RECORD"] {
        case "all": .all
        case "never": .never
        default: .missing
        }
    }

    @Test(.enabled(if: !names.isEmpty, "no captures; run make test-snapshots"), arguments: names)
    func matchesBaseline(_ name: String) throws {
        let url = Self.captures.appendingPathComponent("\(name).png")
        let image = try #require(NSImage(contentsOf: url), "unreadable capture \(name)")
        withSnapshotTesting(record: Self.record) {
            // Perceptual tolerance absorbs anti-aliasing, not layout changes.
            assertSnapshot(
                of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: name,
                testName: "screen")
        }
    }
}
