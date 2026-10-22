import AppKit
import XCTest

/// Captures real app surfaces as rendered by the app itself (never a screen
/// region, which would include any window covering it) as `design-snapshot-<name>` attachments. The sandboxed
/// runner cannot write into the repo, so `make test-snapshots` exports them to
/// `build/design-snapshots/<name>.png` and the `Tests/DesignSnapshots` package
/// compares them with swift-snapshot-testing, which UI test bundles cannot
/// link. Baselines are recorded on a Retina Mac, so capture runs only through
/// `make test-snapshots` (`GANCHO_SNAPSHOTS=1`).
enum DesignSnapshot {
    static let attachmentPrefix = "design-snapshot-"

    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GANCHO_SNAPSHOTS"] == "1",
            "image snapshots run only via make test-snapshots")
    }

    static func save(_ image: NSImage, named name: String) throws {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = attachmentPrefix + name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: attachment.name ?? name) { $0.add(attachment) }
    }

    /// A per-run directory the app writes window renders into.
    static func makeRenderDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-snapshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Asks the app to render its window titled `title` (only its own views,
    /// never the screen) and returns the image.
    static func renderWindow(
        titled title: String, named name: String, in directory: URL
    ) throws
        -> NSImage
    {
        let file = directory.appendingPathComponent("\(name).png")
        try? FileManager.default.removeItem(at: file)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.johnny4young.gancho.ui-test.window-snapshot"),
            object: "\(directory.lastPathComponent)|\(title)|\(name)", userInfo: nil,
            options: [.deliverImmediately])
        return try XCTUnwrap(waitForImage(at: file), "the app did not render \(title)")
    }

    /// Polls for a PNG the app writes asynchronously.
    static func waitForImage(at file: URL, timeout: TimeInterval = 10) -> NSImage? {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: file.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return NSImage(contentsOf: file)
    }

    /// Crops an image to a rect in points from its top-left corner.
    static func crop(_ image: NSImage, to rect: CGRect) throws -> NSImage {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scale = CGFloat(cgImage.width) / image.size.width
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale,
            width: rect.width * scale, height: rect.height * scale)
        return NSImage(cgImage: try XCTUnwrap(cgImage.cropping(to: pixels)), size: rect.size)
    }
}
