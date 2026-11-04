import Foundation
import Testing

@testable import GanchoKit

@Suite("Mac Debug builds keep their data apart")
struct MacBuildIsolationTests {
    @Test("A release build keeps the real store, keys and preferences")
    func releaseKeepsRealData() {
        #expect(MacBuildIsolation.storeFolderName(isIsolated: false) == "Gancho")
        #expect(MacBuildIsolation.keychainService("a.b", isIsolated: false) == "a.b")
        #expect(MacBuildIsolation.launchDefaults(isIsolated: false) === UserDefaults.standard)
    }

    @Test("An isolated build gets its own store, keys and preferences")
    func isolatedGetsItsOwn() {
        #expect(MacBuildIsolation.storeFolderName(isIsolated: true) == "Gancho-Debug")
        #expect(MacBuildIsolation.keychainService("a.b", isIsolated: true) == "a.b.debug")
        #expect(MacBuildIsolation.launchDefaults(isIsolated: true) !== UserDefaults.standard)
    }

    #if os(macOS)
        @Test("This Debug build resolves to the isolated store and keys")
        func debugBuildUsesIsolatedData() {
            #expect(SharedStorageLocation.macAppStoreDirectory.lastPathComponent == "Gancho-Debug")
            #expect(KeychainPassphraseStore.defaultService.hasSuffix(".database-key.debug"))
            #expect(KeychainLicenseTokenStore.defaultService.hasSuffix(".license.debug"))
        }
    #endif
}
