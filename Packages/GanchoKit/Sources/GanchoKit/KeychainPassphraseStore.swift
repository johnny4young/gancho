import Foundation
import Security

/// Stores the SQLCipher database key in the Keychain.
///
/// There is no user-facing passphrase: the key is a 256-bit value generated
/// once with `SecRandomCopyBytes` and thereafter protected by the Keychain. Its
/// attributes encode the product's constraints (see docs/ARCHITECTURE.md):
///
/// - `kSecAttrSynchronizable` — when the build can use iCloud Keychain, the key
///   is stored synchronizable so it replicates across the user's devices and a
///   database restored from backup onto another device of the same Apple Account
///   stays readable. Builds with slim entitlements (the direct-download flavor,
///   whose empty entitlements can't participate in iCloud Keychain — the add
///   returns `errSecMissingEntitlement`) fall back to a DEVICE-LOCAL key
///   (`…ThisDeviceOnly`), which needs no entitlement and never leaves the device.
///   Reads prefer that device-local key when both forms exist, then fall back to
///   the synchronizable key for restores that only have the iCloud Keychain copy.
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
    /// `$(AppIdentifierPrefix)com.johnny4young.gancho.keys` in each target.
    /// macOS does not use a group (default keychain).
    public static var iosSharedAccessGroup: String {
        iosSharedAccessGroup(infoDictionary: Bundle.main.infoDictionary)
    }

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
        try loadOrCreateKeyReportingFreshness().key
    }

    /// Like ``loadOrCreateKey()`` but reports whether the key was just generated.
    /// A freshly generated key can't decrypt a pre-existing encrypted database
    /// (it was keyed by a different, unreachable key), so the store-open recovery
    /// path keys on this to know when it may safely start fresh.
    public func loadOrCreateKeyReportingFreshness() throws -> (key: String, isFresh: Bool) {
        if let existing = try readKey() {
            return (existing, false)
        }
        let key = try Self.generateKey()
        do {
            try storeKey(key)
            return (key, true)
        } catch Failure.keychain(errSecDuplicateItem) {
            if let winner = try readKey() {
                return (winner, false)
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
        // Prefer the device-local key. A direct-download build may create one
        // beside an older synchronizable key it could not read; preferring local
        // keeps later entitled builds opening the database the user is now using
        // instead of nondeterministically selecting the stale iCloud copy.
        if let localKey = try readKey(synchronizable: false) {
            return localKey
        }
        return try readKey(synchronizable: true)
    }

    private func readKey(synchronizable: Bool) throws -> String? {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] =
            synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                // An item exists but is unreadable — treat as missing rather
                // than crashing. Delete it first so the caller can regenerate
                // instead of hitting `errSecDuplicateItem` on the stale row.
                try deleteKey()
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        case let status where synchronizable && Self.synchronizableUnavailable(status):
            // A build without the iCloud-Keychain entitlement (the slim
            // direct-download entitlements) can't query the synchronizable
            // scope. Treat "not permitted" as "no key here" so the caller falls
            // through to creating a device-local one.
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    private func storeKey(_ key: String) throws {
        do {
            try addKey(key, synchronizable: true)
        } catch Failure.keychain(let status) where Self.synchronizableUnavailable(status) {
            // This build can't store a synchronizable (iCloud Keychain) item: it
            // lacks the application-identifier / keychain-access-groups entitlement
            // (the direct-download build ships intentionally slim entitlements, so
            // the synchronizable add returns errSecMissingEntitlement, -34018). A
            // device-local key needs no entitlement and, for a local-first store,
            // is an equal-or-better privacy trade — the key never leaves the
            // device. `errSecDuplicateItem` is NOT in this set, so a first-launch
            // race still surfaces to `loadOrCreateKey`'s re-read.
            try addKey(key, synchronizable: false)
        }
    }

    private func addKey(_ key: String, synchronizable: Bool) throws {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] =
            synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        // Synchronizable items must use a device-agnostic accessibility;
        // device-local ones take the more-protective `…ThisDeviceOnly`.
        query[kSecAttrAccessible as String] =
            synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = Data(key.utf8)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.keychain(status)
        }
    }

    /// Keychain statuses that mean "this build may not use synchronizable /
    /// iCloud-Keychain items" — the signal to fall back to a device-local key.
    /// Parameter errors stay fatal: they usually mean a malformed query or
    /// misconfigured access group, not an entitlement-limited release flavor.
    static func synchronizableUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
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

    static func iosSharedAccessGroup(infoDictionary: [String: Any]?) -> String {
        let prefix =
            (infoDictionary?["AppIdentifierPrefix"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrefix = normalizedTeamPrefix(prefix)
        return "\(resolvedPrefix)com.johnny4young.gancho.keys"
    }

    private static func normalizedTeamPrefix(_ prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty else { return "JGWX5ZT2N2." }
        return prefix.hasSuffix(".") ? prefix : "\(prefix)."
    }
}
