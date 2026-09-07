import Foundation
import Security

/// Where the access group Gancho ended up using actually came from.
///
/// Surfacing this is the point of the type: a mismatch between what the OS
/// granted and what the build guessed is invisible otherwise — every
/// keychain call just fails, on the extensions first, with nothing to point
/// at.
public struct AccessGroupResolution: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Read back from the keychain, so it is the group the OS actually
        /// granted this process. Authoritative.
        case entitlement
        /// Built from `AppIdentifierPrefix` in the Info.plist, which
        /// XcodeGen fills from `DEVELOPMENT_TEAM`. A guess that is right
        /// whenever the team ID and the App ID prefix agree.
        case buildSetting
        /// Neither was available. Last resort.
        case fallback
    }

    public let group: String
    public let source: Source
    /// True when the OS granted a group the build-time guess would have
    /// missed — the legacy or transferred App ID case, where the team ID
    /// and the App Identifier Prefix differ. Worth reporting: it means
    /// every build before this one was reaching for the wrong group.
    public let contradictedBuildSetting: Bool
}

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
        iosSharedAccessGroupResolution.group
    }

    /// The resolution behind ``iosSharedAccessGroup``, so a shell can report a
    /// contradiction instead of leaving the user with silent keychain failures.
    ///
    /// Computed once per process. The answer cannot change while the process
    /// lives — the entitlement is fixed at signing — and `static let` gives
    /// that for free, thread-safely.
    public static let iosSharedAccessGroupResolution: AccessGroupResolution =
        iosSharedAccessGroupResolution(
            discovered: discoverGrantedAccessGroup(),
            infoDictionary: Bundle.main.infoDictionary)

    /// Asks the keychain which access group this process was actually granted.
    ///
    /// `keychain-access-groups` is expanded at CODE SIGNING time from the
    /// provisioning profile's App Identifier Prefix, while the Info.plist value
    /// XcodeGen writes comes from `DEVELOPMENT_TEAM`. Those agree for most
    /// accounts and differ for legacy or transferred App IDs — and when they
    /// differ, every read and write targets a group the process does not hold,
    /// so the app, share extension, keyboard, and widgets all fail closed with
    /// nothing to point at.
    ///
    /// The trick is that an item added with NO `kSecAttrAccessGroup` is filed
    /// by the OS in the process's first entitled group, and reading its
    /// attributes back reports that group fully expanded. That makes the
    /// keychain itself the source of truth rather than a build-time guess.
    ///
    /// Not `SecTaskCopyValueForEntitlement`, which would read the entitlement
    /// directly: `SecTask.h` ships in the macOS SDK only, so on iOS it would
    /// mean declaring private symbols.
    ///
    /// Returns nil — leaving the caller on the build-time value, today's
    /// behavior — whenever the probe cannot complete, notably before first
    /// unlock.
    private static func discoverGrantedAccessGroup() -> String? {
        #if os(iOS)
            let probe: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.johnny4young.gancho.access-group-probe",
                kSecAttrAccount as String: "access-group-probe"
            ]
            var insert = probe
            // Same accessibility as the key it is probing for, so the probe can
            // never succeed in a state where the real read would fail.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecValueData as String] = Data()

            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            // A leftover probe from a previous run is just as good to read.
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else { return nil }
            // Best-effort: a probe left behind is inert, and deleting it is not
            // worth failing the resolution over.
            defer { SecItemDelete(probe as CFDictionary) }

            var query = probe
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                let attributes = item as? [String: Any]
            else { return nil }
            return attributes[kSecAttrAccessGroup as String] as? String
        #else
            // macOS uses the default keychain with no group, and the CLI has no
            // entitlement to discover.
            return nil
        #endif
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
            kSecAttrAccount as String: account
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

    /// The tail every target's `keychain-access-groups` entitlement ends with.
    /// Only the team prefix in front of it is ever in question.
    static let sharedAccessGroupSuffix = "com.johnny4young.gancho.keys"

    /// Resolves the group to use, preferring what the OS granted over what the
    /// build guessed.
    ///
    /// Pure on purpose: `discovered` is supplied by the caller so the decision
    /// is testable without a keychain, an entitlement, or a device.
    ///
    /// A discovered group is trusted only when it carries the expected suffix.
    /// The probe files its item in the process's FIRST entitled group, and
    /// while every Gancho target is granted exactly one, a future target with a
    /// second group listed ahead of this one would otherwise silently redirect
    /// the store's key somewhere else.
    static func iosSharedAccessGroupResolution(
        discovered: String?,
        infoDictionary: [String: Any]?
    ) -> AccessGroupResolution {
        let rawPrefix =
            (infoDictionary?["AppIdentifierPrefix"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBuildSetting = !(rawPrefix ?? "").isEmpty
        let buildSettingGroup = "\(normalizedTeamPrefix(rawPrefix))\(sharedAccessGroupSuffix)"

        if let discovered = discovered?.trimmingCharacters(in: .whitespacesAndNewlines),
            discovered.hasSuffix(".\(sharedAccessGroupSuffix)")
        {
            return AccessGroupResolution(
                group: discovered,
                source: .entitlement,
                contradictedBuildSetting: discovered != buildSettingGroup)
        }
        return AccessGroupResolution(
            group: buildSettingGroup,
            source: hasBuildSetting ? .buildSetting : .fallback,
            contradictedBuildSetting: false)
    }

    static func iosSharedAccessGroup(infoDictionary: [String: Any]?) -> String {
        iosSharedAccessGroupResolution(discovered: nil, infoDictionary: infoDictionary).group
    }

    private static func normalizedTeamPrefix(_ prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty else { return "JGWX5ZT2N2." }
        return prefix.hasSuffix(".") ? prefix : "\(prefix)."
    }
}
