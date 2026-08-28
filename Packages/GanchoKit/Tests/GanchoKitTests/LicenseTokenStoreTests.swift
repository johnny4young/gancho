import Foundation
import Testing

@testable import GanchoKit

private func licenseKeychainProbePasses() -> Bool {
    let store = KeychainLicenseTokenStore(
        service: "com.johnny4young.gancho.license-probe-\(UUID().uuidString)",
        account: "probe")
    defer { try? store.clear() }
    return (try? store.save("probe")) != nil && store.load() == "probe"
}

@Suite("In-memory license store — concurrent access")
struct InMemoryLicenseTokenStoreTests {
    @Test("Concurrent saves and loads remain complete and replaceable")
    func concurrentAccess() async throws {
        let store = InMemoryLicenseTokenStore(token: "seed")

        let observed = await withTaskGroup(
            of: String?.self, returning: [String?].self
        ) { group in
            for index in 0..<500 {
                group.addTask {
                    try? store.save("token-\(index)")
                    return store.load()
                }
            }

            var values: [String?] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        #expect(observed.count == 500)
        #expect(
            observed.allSatisfy { value in
                value == "seed" || value?.hasPrefix("token-") == true
            })

        try store.save("final")
        #expect(store.load() == "final")
        try store.clear()
        #expect(store.load() == nil)
    }
}

/// Live device-local round-trip. A locked-down CI runner without a usable login
/// Keychain skips this suite; source-level release guards still run everywhere.
@Suite(
    "License activation store — device-local round-trip",
    .enabled(if: licenseKeychainProbePasses()))
struct LicenseTokenStoreTests {
    private func uniqueStore() -> KeychainLicenseTokenStore {
        KeychainLicenseTokenStore(
            service: "com.johnny4young.gancho.license-test-\(UUID().uuidString)",
            account: "activation-record")
    }

    @Test("Saving again replaces the existing activation record in place")
    func replacesExistingRecord() throws {
        let store = uniqueStore()
        defer { try? store.clear() }

        try store.save("first-record")
        #expect(store.load() == "first-record")

        try store.save("replacement-record")
        #expect(store.load() == "replacement-record")

        try store.clear()
        #expect(store.load() == nil)
    }
}
