import Foundation

/// The one way to obtain the symmetric key that `SealedEnvelope` uses for
/// content living outside the SQLCipher database.
///
/// `GRDBClipboardStore.encrypted(directory:keychainAccessGroup:)` derives the
/// same bytes for its `BlobStore`, but it only does so behind a full database
/// open. The share extension has no business opening the store — it lives for
/// seconds and GRDB stays single-owner in the host app — yet it still writes
/// content to disk, so it needs the key without the store. This is that seam,
/// and it derives the key identically, so bytes sealed by one side always open
/// on the other.
///
/// Reading also creates the key when none exists yet, matching every other
/// caller: whichever process reaches the keychain first wins, and the shared
/// access group makes that choice invisible to the rest.
public enum StoreContentKey {
    /// Loads (or first-creates) the content key.
    ///
    /// - Parameter keychainAccessGroup: the shared access group on iOS, where
    ///   the app and its extensions must resolve the same key. Nil uses the
    ///   process's own keychain, which is what macOS wants.
    /// - Throws: `KeychainPassphraseStore.Failure` when the keychain is
    ///   unreachable. Callers that write content MUST treat a throw as "do not
    ///   write" rather than falling back to plaintext.
    public static func load(keychainAccessGroup: String? = nil) throws -> Data {
        let passphrase = try KeychainPassphraseStore(accessGroup: keychainAccessGroup)
            .loadOrCreateKey()
        return BlobStore.encryptionKeyData(for: passphrase)
    }
}
