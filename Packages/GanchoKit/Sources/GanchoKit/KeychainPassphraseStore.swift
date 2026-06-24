import Foundation
import Security

/// Stores the SQLCipher database key in the Keychain.
///
/// There is no user-facing passphrase: the key is a 256-bit value generated
/// once with `SecRandomCopyBytes` and thereafter protected by the Keychain. Its
/// attributes encode the product's constraints (see docs/ARCHITECTURE.md):
///
/// - `kSecAttrSynchronizable` — iCloud Keychain replicates the key across the
///   user's devices, so a database restored from backup onto another device of
///   the same Apple Account stays readable. (Acceptance: multi-device key.)
/// - `kSecAttrAccessibleAfterFirstUnlock` — the menu-bar agent and the deferred
///   importer open the database while the device is locked, but never before
///   the first unlock after boot. Required for background capture, and the
///   most-protective accessibility that still allows it. Compatible with
///   synchronizable items (`…ThisDeviceOnly` is not).
/// - `accessGroup` (iOS) — when set, the app and any database-reading extension
///   (widgets, keyboard) resolve the same key. The macOS app and the unsandboxed
///   `gancho` CLI share the user keychain without a group.
///
/// The key is never logged, never derived from user input, and never leaves the
/// Keychain except to open the database in `Configuration.prepareDatabase`.
/// `Failure` deliberately carries only an `OSStatus`, never the key material.
public struct KeychainPassphraseStore: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        /// `SecItem…` returned an unexpected status. Holds the raw `OSStatus`
        /// only — never the key, so it is safe to log or surface.
        case keychain(OSStatus)
        /// The system CSPRNG failed to produce a key.
        case randomGenerationFailed
    }

    /// Shared keychain access group for the iOS app and its database-reading
    /// extensions (keyboard, widgets). The app writes the key here; the
    /// extensions read it. Must match the `keychain-access-groups` entitlement
    /// `$(AppIdentifierPrefix)com.johnny4young.gancho.keys` in each target —
    /// `$(AppIdentifierPrefix)` resolves to the team prefix (DEVELOPMENT_TEAM =
    /// JGWX5ZT2N2 in project.yml). macOS does not use a group (default keychain).
    public static let iosSharedAccessGroup = "JGWX5ZT2N2.com.johnny4young.gancho.keys"

    private let service: String
    private let account: String
    private let accessGroup: String?

    /// - Parameters:
    ///   - service: keychain item service; defaults to the database-key service.
    ///   - account: keychain item account; defaults to the single store key.
    ///   - accessGroup: shared keychain access group for iOS DB-reading
    ///     extensions. `nil` on macOS and in tests.
    public init(
        service: String = "com.johnny4young.gancho.database-key",
        account: String = "gancho-sqlite",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    /// Returns the existing key, or generates, stores, and returns a new one.
    ///
    /// Idempotent under a first-launch race: if two processes (app + extension,
    /// or app + CLI) both miss the read and try to add, the loser gets
    /// `errSecDuplicateItem` and re-reads the winner's key, so every caller
    /// converges on a single key for the database.
    public func loadOrCreateKey() throws -> String {
        if let existing = try readKey() {
            return existing
        }
        let key = try Self.generateKey()
        do {
            try storeKey(key)
            return key
        } catch Failure.keychain(errSecDuplicateItem) {
            if let winner = try readKey() {
                return winner
            }
            throw Failure.keychain(errSecDuplicateItem)
        }
    }

    /// Deletes the stored key. Test cleanup and the "reset encrypted store"
    /// recovery path (after which the next launch starts a fresh encrypted DB).
    public func deleteKey() throws {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }

    // MARK: - Keychain queries

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func readKey() throws -> String? {
        var query = baseQuery()
        // Match whether the item was stored synchronizable or not, so a key
        // that predates iCloud Keychain replication is still found.
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                // An item exists but is unreadable — treat as missing rather
                // than crashing; the caller regenerates.
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    private func storeKey(_ key: String) throws {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = Data(key.utf8)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.keychain(status)
        }
    }

    // MARK: - Key generation

    /// A 256-bit random key, hex-encoded (64 chars). Hex keeps the key 7-bit
    /// ASCII, so it is safe to hand to SQLCipher's `PRAGMA key = '…'` without
    /// quoting or encoding surprises.
    static func generateKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw Failure.randomGenerationFailed
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
