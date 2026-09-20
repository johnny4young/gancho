import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One in-memory region snapshot, never a recording or temporary image file.
struct ScreenTextCapture: Sendable {
    #if DEBUG
        // Selection-only UI tests must never request or perform real capture.
        nonisolated static var isSelectionOnlyTest: Bool {
            let args = CommandLine.arguments
            return args.contains("-screen-ocr-selector-for-ui-test")
                && args.contains("-use-temp-durable-store")
                && args.contains("-ui-test-paste-sink")
        }

        nonisolated static var hasSensitiveResultFixture: Bool {
            let args = CommandLine.arguments
            return args.contains("-screen-ocr-sensitive-result-for-ui-test")
                && args.contains("-use-temp-durable-store")
                && args.contains("-ui-test-paste-sink")
        }
    #endif
    @concurrent func image(in rect: CGRect) async throws -> Data {
        try Task.checkCancellation()
        #if DEBUG
            if Self.isSelectionOnlyTest { throw CancellationError() }
        #endif
        let image = try await SCScreenshotManager.captureImage(in: rect)
        try Task.checkCancellation()
        let data = NSMutableData()
        guard
            let output = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ScreenTextCaptureError.failed
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw ScreenTextCaptureError.failed }
        return data as Data
    }
}

enum ScreenTextCaptureError: Error { case failed }
