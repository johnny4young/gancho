import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Secret lifetime and timed reveal")
struct SecretLifetimeTests {
    private let captured = Date(timeIntervalSince1970: 1_800_000_000)

    private func secret(lifetime: TimeInterval = 600) -> ClipItem {
        ClipItem(
            createdAt: captured, kind: .secret, preview: "●●●● 4Q2v", contentHash: "s",
            isSensitive: true, expiresAt: captured.addingTimeInterval(lifetime))
    }

    @Test("Remaining time and fraction follow the stored expiry")
    func remainingFollowsExpiry() throws {
        let lifetime = try #require(SecretLifetime(item: secret(), lifetime: 600))
        let now = captured.addingTimeInterval(19)

        #expect(lifetime.remaining(at: now) == 581)
        #expect(abs(lifetime.fraction(at: now) - 581.0 / 600) < 0.0001)
    }

    @Test("A shortened lifetime setting wins over a later stored expiry")
    func shortenedSettingWins() throws {
        let lifetime = try #require(SecretLifetime(item: secret(lifetime: 1_800), lifetime: 300))

        #expect(lifetime.deadline == captured.addingTimeInterval(300))
        #expect(lifetime.fraction(at: captured) == 1)
    }

    @Test("Past the deadline nothing remains and the bar is empty")
    func pastDeadline() throws {
        let lifetime = try #require(SecretLifetime(item: secret(), lifetime: 600))
        let later = captured.addingTimeInterval(900)

        #expect(lifetime.remaining(at: later) == 0)
        #expect(lifetime.fraction(at: later) == 0)
    }

    @Test("No lifetime for a clip that is not sensitive or has no expiry")
    func noLifetime() {
        #expect(SecretLifetime(item: ClipItem(contentHash: "p"), lifetime: 600) == nil)
        let legacy = ClipItem(kind: .secret, contentHash: "l", isSensitive: true)
        #expect(SecretLifetime(item: legacy, lifetime: 600) == nil)
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
