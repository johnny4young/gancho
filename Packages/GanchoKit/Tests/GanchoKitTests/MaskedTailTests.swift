import Foundation
import Testing

@testable import GanchoKit

@Suite("Masked tail — a protected card never shows more than the stored mask")
struct MaskedTailTests {
    @Test(
        "Mask-shaped stored previews show as stored",
        arguments: ["●●●● 4Q2v", "●●●●", "●●●● 1"])
    func storedMask(_ preview: String) {
        let clip = ClipItem(kind: .secret, preview: preview, isSensitive: true)
        #expect(ClipSafePresentation.maskedTail(for: clip) == preview)
    }

    @Test(
        "Anything else falls back to the plain mask",
        arguments: [
            "sk_live_51Hx2v4Q2v", "●●●● sk_live_4Q2v", "hunter2", "", "●●●● 4Q2v extra",
            "x●●● 4Q2v"
        ])
    func rawPreview(_ preview: String) {
        let clip = ClipItem(kind: .secret, preview: preview, isSensitive: true)
        #expect(ClipSafePresentation.maskedTail(for: clip) == ClipSafePresentation.masked)
    }
}
