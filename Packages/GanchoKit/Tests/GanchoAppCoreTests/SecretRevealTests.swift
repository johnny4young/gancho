import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("A secret's timed reveal")
struct SecretRevealTests {
    private let captured = Date(timeIntervalSince1970: 1_800_000_000)

    private func secret() -> ClipItem {
        ClipItem(
            createdAt: captured, kind: .secret, preview: "●●●● 4Q2v", contentHash: "s",
            isSensitive: true, expiresAt: captured.addingTimeInterval(600))
    }

    @Test("A reveal lasts exactly its window and can end early")
    func revealWindow() {
        var reveal = SecretReveal()
        #expect(!reveal.isRevealed(at: captured))

        reveal.reveal(at: captured)
        #expect(reveal.isRevealed(at: captured.addingTimeInterval(9.9)))
        #expect(!reveal.isRevealed(at: captured.addingTimeInterval(SecretReveal.window)))

        reveal.reveal(at: captured)
        reveal.hide()
        #expect(!reveal.isRevealed(at: captured.addingTimeInterval(1)))
    }

    @Test("A refused reveal never reads the store; text and paths read as text")
    func revealReadsOnlyWhenAllowed() async {
        let reads = ReadCounter()
        let item = secret()
        let refused = await SecretReveal.text(for: item, allowed: false) { _ in
            await reads.increment()
            return .text("synthetic")
        }
        #expect(refused == nil)
        #expect(await reads.none)

        #expect(
            await SecretReveal.text(for: item, allowed: true) { _ in .text("synthetic") }
                == "synthetic")
        #expect(
            await SecretReveal.text(for: item, allowed: true) { _ in .fileReferences(["/a", "/b"]) }
                == "/a\n/b")
        #expect(
            await SecretReveal.text(for: item, allowed: true) { _ in
                .binary(data: Data([1]), typeIdentifier: "public.png")
            } == nil)
    }
}

private actor ReadCounter {
    private(set) var none = true
    func increment() { none = false }
}
