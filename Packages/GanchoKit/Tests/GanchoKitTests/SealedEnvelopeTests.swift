import Foundation
import Testing

@testable import GanchoKit

@Suite("SealedEnvelope — shared seal/open primitive")
struct SealedEnvelopeTests {
    let key = Data(repeating: 0xA1, count: 32)
    let otherKey = Data(repeating: 0xB2, count: 32)

    @Test("Seal/open round-trips and the sealed bytes hide the plaintext")
    func roundTrip() throws {
        let plaintext = Data("clipboard secret".utf8)
        let sealed = try SealedEnvelope.seal(plaintext, key: key)

        #expect(SealedEnvelope.isSealed(sealed))
        #expect(!sealed.contains(plaintext), "plaintext must not appear in sealed bytes")
        #expect(try SealedEnvelope.open(sealed, key: key) == plaintext)
    }

    @Test("Opening with the wrong key throws (GCM authentication)")
    func wrongKeyThrows() throws {
        let sealed = try SealedEnvelope.seal(Data("secret".utf8), key: key)
        #expect(throws: (any Error).self) {
            try SealedEnvelope.open(sealed, key: otherKey)
        }
    }

    @Test("A single flipped ciphertext bit fails to open")
    func tamperThrows() throws {
        var sealed = try SealedEnvelope.seal(Data("secret".utf8), key: key)
        sealed[sealed.index(before: sealed.endIndex)] ^= 0x01
        #expect(throws: (any Error).self) {
            try SealedEnvelope.open(sealed, key: key)
        }
    }

    @Test("Unsealed bytes pass through open unchanged (legacy plaintext)")
    func plaintextPassThrough() throws {
        let plain = Data("never sealed".utf8)
        #expect(!SealedEnvelope.isSealed(plain))
        #expect(try SealedEnvelope.open(plain, key: key) == plain)
    }

    @Test("isSealed is false for short and empty data")
    func isSealedBounds() {
        #expect(!SealedEnvelope.isSealed(Data()))
        #expect(!SealedEnvelope.isSealed(SealedEnvelope.magic.prefix(4)))
        #expect(SealedEnvelope.isSealed(SealedEnvelope.magic))
    }

    @Test("BlobStore's on-disk magic IS the shared envelope magic")
    func magicMatchesBlobStoreFormat() {
        // The framing was extracted from BlobStore; existing sealed blobs and
        // thumbnails must keep decoding, so the bytes are pinned here too.
        #expect(BlobStore.encryptedMagic == SealedEnvelope.magic)
        #expect(
            SealedEnvelope.magic
                == Data([0x47, 0x61, 0x6e, 0x63, 0x68, 0x6f, 0x42, 0x6c, 0x6f, 0x62, 0x01]))
    }
}
