import Foundation
import Testing

@testable import GanchoKit

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
}
