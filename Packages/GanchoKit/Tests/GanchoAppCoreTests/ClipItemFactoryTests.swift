import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Covers the capture→ClipItem mapping moved out of the macOS shell: one case
/// per payload branch plus the two secret-toggle branches. Deterministic and
/// pure — real `RuleClassifier()` / `SensitiveDataDetector()` (both are
/// zero-arg, on-device, no network), no store, no timers.
@Suite("ClipItemFactory — capture → ClipItem mapping")
struct ClipItemFactoryTests {
    private let classifier = RuleClassifier()
    private let detector = SensitiveDataDetector()

    private func make(
        _ capture: PasteboardCapture, detectSecrets: Bool = true
    ) -> (ClipItem, ClipContent?) {
        ClipItemFactory.make(
            from: capture, classifier: classifier, detector: detector,
            sensitiveLifetime: 600, detectSecrets: detectSecrets)
    }

    @Test("Image payload → .image kind, byte-size preview, binary content")
    func imagePayload() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let (item, content) = make(
            PasteboardCapture(payload: .image(data: data, typeIdentifier: "public.png")))

        #expect(item.kind == .image)
        #expect(item.preview == "Image (\(ByteSize.formatted(data.count)))")
        #expect(!item.isSensitive)
        #expect(content == .binary(data: data, typeIdentifier: "public.png"))
    }

    @Test("Plain-text URL → .url kind, tracking-stripped preview, text content")
    func urlPayload() {
        // The classifier tags a whole-string link as `.url`; canonicalization
        // then strips the tracking parameter, so preview and content are the
        // cleaned URL — proving the normalize step ran (non-vacuous).
        let raw = "https://example.com/path?q=1&utm_source=news"
        let clean = "https://example.com/path?q=1"
        let (item, content) = make(PasteboardCapture(text: raw))

        #expect(item.kind == .url)
        #expect(item.preview == clean)
        #expect(content == .text(clean))
        #expect(!item.isSensitive)
    }

    @Test("File references → .fileReference kind, joined names, fileReferences content")
    func fileReferencesPayload() {
        let urls = [
            URL(fileURLWithPath: "/tmp/report.pdf"),
            URL(fileURLWithPath: "/tmp/notes.txt")
        ]
        let (item, content) = make(PasteboardCapture(payload: .fileReferences(urls)))

        #expect(item.kind == .fileReference)
        #expect(item.preview == "report.pdf, notes.txt")
        #expect(content == .fileReferences(["/tmp/report.pdf", "/tmp/notes.txt"]))
    }

    @Test("detectSecrets:false leaves a secret-looking clip un-flagged")
    func secretsToggledOff() {
        // A GitHub-token shape, split mid-literal so the source carries no
        // contiguous scannable token. With detection off, the masking/flagging
        // step is skipped entirely — the clip stays plain text.
        let token = "ghp_abcdefghijklmno" + "pqrstuvwxyz0123456789"
        let (item, content) = make(PasteboardCapture(text: token), detectSecrets: false)

        #expect(!item.isSensitive)
        #expect(item.kind != .secret)
        #expect(item.preview == token)
        #expect(content == .text(token))
    }

    @Test("detectSecrets:true on rich text flags it and stores masked text, not the RTF")
    func secretsFlaggedPrefersText() {
        // Same synthetic token, delivered as rich text so the sensitive branch's
        // content choice is observable: a flagged rich clip stores `.text` (the
        // plain payload), NEVER the `.rtf` binary that would carry the secret.
        let token = "ghp_abcdefghijklmno" + "pqrstuvwxyz0123456789"
        let rtf = Data("{\\rtf1 secret}".utf8)
        let (item, content) = make(
            PasteboardCapture(payload: .richText(rtf: rtf, plainText: token)))

        #expect(item.isSensitive)
        #expect(item.kind == .secret)
        // Masked preview: bullets + the last 4 non-whitespace characters.
        #expect(item.preview == "●●●● 6789")
        #expect(!item.preview.contains("ghp_"))
        #expect(content == .text(token))
    }
}
