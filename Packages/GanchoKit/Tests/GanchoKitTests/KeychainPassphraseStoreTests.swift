import Foundation
import Security
import Testing

@testable import GanchoKit

/// Whether this environment can add/read a device-local generic-password item.
/// The `swift test` runner has no entitlements — the same context as the
/// direct-download build — so a device-local key works here where a
/// synchronizable one returns -34018. A locked-down CI runner (no usable login
/// keychain) skips the round-trip suite instead of failing it.
private func keychainProbePasses() -> Bool {
    let probe = KeychainPassphraseStore(
        service: "com.johnny4young.gancho.probe-\(UUID().uuidString)", account: "probe")
    defer { try? probe.deleteKey() }
    return (try? probe.loadOrCreateKey()) != nil
}

/// Unit coverage for the key *generation* only. The Keychain round-trip needs
/// an app's `keychain-access-groups` entitlement, which the `swift test` runner
/// lacks (it returns `errSecMissingEntitlement`, -34018), so the store's
/// load/create/delete path is verified live on device, not here.
@Suite("KeychainPassphraseStore — key generation")
struct KeychainPassphraseStoreTests {
    @Test("A generated key is 64 hex characters (256 bits)")
    func keyShape() throws {
        let key = try KeychainPassphraseStore.generateKey()
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
        // Hex stays 7-bit ASCII, safe for SQLCipher's PRAGMA key.
        #expect(key.allSatisfy { $0.isASCII })
    }

    @Test("Successive keys differ (the CSPRNG is actually random)")
    func keysAreUnique() throws {
        var seen = Set<String>()
        for _ in 0..<256 {
            let key = try KeychainPassphraseStore.generateKey()
            #expect(seen.insert(key).inserted, "generated a duplicate 256-bit key")
        }
    }

    @Test("iOS shared access group follows the signed app identifier prefix")
    func accessGroupUsesInfoPlistPrefix() {
        #expect(
            KeychainPassphraseStore.iosSharedAccessGroup(infoDictionary: [
                "AppIdentifierPrefix": "TEAM12345."
            ]) == "TEAM12345.com.johnny4young.gancho.keys")
        #expect(
            KeychainPassphraseStore.iosSharedAccessGroup(infoDictionary: [
                "AppIdentifierPrefix": "TEAM12345"
            ]) == "TEAM12345.com.johnny4young.gancho.keys")
        #expect(
            KeychainPassphraseStore.iosSharedAccessGroup(infoDictionary: [:])
                == "JGWX5ZT2N2.com.johnny4young.gancho.keys")
    }

    @Test("Synchronizable-unavailable statuses drive the device-local fallback")
    func synchronizableUnavailableStatuses() {
        // The statuses a build without the iCloud-Keychain entitlement returns
        // when it can't use a synchronizable item — the signal to fall back.
        #expect(KeychainPassphraseStore.synchronizableUnavailable(errSecMissingEntitlement))
        #expect(KeychainPassphraseStore.synchronizableUnavailable(errSecNotAvailable))
        // Duplicates belong to the first-launch-race re-read path, and parameter
        // errors usually mean a malformed query or access-group bug — neither
        // should rotate the key by falling back. Success is obviously not a
        // failure.
        #expect(!KeychainPassphraseStore.synchronizableUnavailable(errSecDuplicateItem))
        #expect(!KeychainPassphraseStore.synchronizableUnavailable(errSecParam))
        #expect(!KeychainPassphraseStore.synchronizableUnavailable(errSecSuccess))
    }
}

/// Live device-local round-trip — provable here precisely because the runner is
/// entitlement-less, exactly like the direct-download build. Skipped when the
/// environment has no usable keychain.
@Suite(
    "KeychainPassphraseStore — device-local round-trip",
    .enabled(if: keychainProbePasses()))
struct KeychainDeviceLocalTests {
    private func uniqueStore() -> KeychainPassphraseStore {
        KeychainPassphraseStore(
            service: "com.johnny4young.gancho.test-\(UUID().uuidString)", account: "gancho-test")
    }

    @Test("A key persists and re-reads without any entitlement")
    func persistsAndReReads() throws {
        let store = uniqueStore()
        defer { try? store.deleteKey() }
        let first = try store.loadOrCreateKeyReportingFreshness()
        #expect(first.isFresh, "the first resolve generates a new key")
        #expect(first.key.count == 64)
        let second = try store.loadOrCreateKeyReportingFreshness()
        #expect(second.key == first.key, "the key persists across resolves")
        #expect(!second.isFresh, "an existing key is not fresh")
    }

    @Test("A deleted key is regenerated as fresh, and differs")
    func deleteThenRegenerate() throws {
        let store = uniqueStore()
        defer { try? store.deleteKey() }
        let original = try store.loadOrCreateKey()
        try store.deleteKey()
        let regenerated = try store.loadOrCreateKeyReportingFreshness()
        #expect(regenerated.isFresh)
        #expect(regenerated.key != original)
    }
}
