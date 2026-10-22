import AppKit
import XCTest

/// Captures real app surfaces by element (never the whole screen, which would
/// include the desktop) into `build/design-snapshots/<name>.png`. The
/// `Tests/DesignSnapshots` package compares them with swift-snapshot-testing,
/// which UI test bundles cannot link. Baselines are recorded on a Retina Mac,
/// so capture runs only through `make test-snapshots` (`GANCHO_SNAPSHOTS=1`).
enum DesignSnapshot {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // GanchoUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("build/design-snapshots")

    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GANCHO_SNAPSHOTS"] == "1",
            "image snapshots run only via make test-snapshots")
    }

    static func save(_ image: NSImage, named name: String) throws {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// The element's screenshot, optionally cropped to a rect in points
    /// relative to the element's top-left corner.
    @MainActor
    static func image(of element: XCUIElement, crop: CGRect? = nil) -> NSImage {
        let full = element.screenshot().image
        guard let crop,
            let cgImage = full.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return full }
        let scale = CGFloat(cgImage.width) / full.size.width
        let pixels = CGRect(
            x: crop.minX * scale, y: crop.minY * scale,
            width: crop.width * scale, height: crop.height * scale)
        guard let cropped = cgImage.cropping(to: pixels) else { return full }
        return NSImage(cgImage: cropped, size: crop.size)
    }
}
