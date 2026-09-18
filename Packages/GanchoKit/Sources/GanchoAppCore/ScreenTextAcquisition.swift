import CoreGraphics
import Foundation

/// The acquisition boundary is checked after every suspension before capture.
/// Cancelling the owning OCR task is irreversible, even if Private Mode is
/// turned off before a pending selector returns.
@MainActor public enum ScreenTextAcquisition {
    public static func image(
        select: @MainActor () async -> CGRect?,
        isAllowed: @MainActor () -> Bool,
        settle: @MainActor () async throws -> Void = {
            // Give the compositor time to remove the selector. Physical window
            // exclusion still needs separate verification on supported displays.
            try await Task.sleep(for: .milliseconds(100))
        },
        capture: @Sendable (CGRect) async throws -> Data
    ) async throws -> Data {
        try Task.checkCancellation()
        guard isAllowed(), let region = await select() else { throw CancellationError() }
        try Task.checkCancellation()
        guard isAllowed() else { throw CancellationError() }
        try await settle()
        try Task.checkCancellation()
        guard isAllowed() else { throw CancellationError() }
        let image = try await capture(region)
        try Task.checkCancellation()
        guard isAllowed() else { throw CancellationError() }
        return image
    }
}
