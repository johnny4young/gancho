import CryptoKit
import Foundation

/// The ONE seal/open primitive for content that crosses a process or disk
/// boundary outside the SQLCipher database — blob payloads, cached
/// thumbnails, and the share-extension inbox all route through it, so the
/// "content exists in exactly four places" guarantee holds by construction.
///
/// Wire format (byte-identical to the framing `BlobStore` has always
/// written, so every sealed blob and thumbnail already on disk decodes
/// unchanged): an 11-byte magic header followed by AES-GCM's `combined`
/// representation (nonce ‖ ciphertext ‖ tag). Bytes without the magic are
/// plaintext by definition — `open` passes them through, which is what
/// keeps legacy (pre-sealing) files readable across an update.
public enum SealedEnvelope {
    /// Header marking sealed bytes ("GanchoBlob" + format version 0x01).
    /// This is the on-disk format of every encrypted blob and thumbnail
    /// already written — it must NEVER change.
    public static let magic = Data([
        0x47, 0x61, 0x6e, 0x63, 0x68, 0x6f, 0x42, 0x6c, 0x6f, 0x62, 0x01
    ])

    /// Failures beyond what CryptoKit itself throws (a wrong key or a
    /// tampered payload surfaces as a CryptoKit authentication error).
    public enum EnvelopeError: Error {
        /// AES-GCM produced no `combined` representation. Cannot happen with
        /// the default 12-byte nonce; kept as a structural guard.
        case malformedSealedData
    }

    /// Seals `data` under `key` (raw symmetric key bytes, the store's blob
    /// encryption key): `magic ‖ AES.GCM(nonce ‖ ciphertext ‖ tag)`.
    public static func seal(_ data: Data, key: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: key))
        guard let combined = sealed.combined else {
            throw EnvelopeError.malformedSealedData
        }
        var payload = magic
        payload.append(combined)
        return payload
    }

    /// Opens sealed data with `key`. Bytes WITHOUT the magic header are
    /// returned as-is (plaintext pass-through, so legacy unsealed files keep
    /// draining). Throws when the payload is sealed but the key is wrong or
    /// a single bit was flipped — GCM authenticates before it decrypts.
    public static func open(_ data: Data, key: Data) throws -> Data {
        guard isSealed(data) else { return data }
        let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count)))
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    /// True when `data` carries the sealed-envelope magic header.
    public static func isSealed(_ data: Data) -> Bool {
        data.count >= magic.count && data.prefix(magic.count).elementsEqual(magic)
    }
}
