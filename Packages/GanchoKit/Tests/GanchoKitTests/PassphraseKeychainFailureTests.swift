import Foundation
import Security
import Testing

@testable import GanchoKit

private final class FakePassphraseKeychain: PassphraseKeychainOperations, @unchecked Sendable {
    private let lock = NSLock()
    var local: Data?
    var synchronized: Data?
    var malformedLocal = false
    var duplicateWinner: Data?
    private(set) var reads: [Bool] = []
    private(set) var adds = 0
    private(set) var deletes = 0

    init(local: Data? = nil, synchronized: Data? = nil) {
        self.local = local
        self.synchronized = synchronized
    }

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.withLock {
            let sync = query[kSecAttrSynchronizable as String] as? Bool ?? false
            reads.append(sync)
            if !sync && malformedLocal { return (errSecSuccess, nil) }
            let data = sync ? synchronized : local
            return (data == nil ? errSecItemNotFound : errSecSuccess, data)
        }
    }

    func add(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            adds += 1
            if let duplicateWinner {
                synchronized = duplicateWinner
                return errSecDuplicateItem
            }
            synchronized = query[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            deletes += 1
            local = nil
            synchronized = nil
            return errSecSuccess
        }
    }
}

@Suite("Passphrase Keychain failures — injected operations only")
struct PassphraseKeychainFailureTests {
    private let valid = Data(String(repeating: "a1", count: 32).utf8)

    @Test("Malformed preferred authority never deletes or falls through to another scope")
    func malformedPreferred() throws {
        for malformed in [Data([0xff]), Data(), Data("not-a-key".utf8)] {
            let fake = FakePassphraseKeychain(local: malformed, synchronized: valid)
            let store = KeychainPassphraseStore(operations: fake)
            #expect(throws: KeychainPassphraseStore.Failure.malformedKey) {
                try store.loadOrCreateKeyReportingFreshness()
            }
            #expect(fake.reads == [false])
            #expect(fake.adds == 0 && fake.deletes == 0)
            #expect(fake.local == malformed && fake.synchronized == valid)
        }
    }

    @Test("A successful non-Data read fails closed without touching stored authority")
    func unexpectedResultType() throws {
        let fake = FakePassphraseKeychain(synchronized: valid)
        fake.malformedLocal = true
        #expect(throws: KeychainPassphraseStore.Failure.malformedKey) {
            try KeychainPassphraseStore(operations: fake).loadOrCreateKey()
        }
        #expect(fake.adds == 0 && fake.deletes == 0)
        #expect(fake.synchronized == valid)
    }

    @Test("Real absence creates once; duplicate first-launch contenders read the winner")
    func absenceAndDuplicate() throws {
        let empty = FakePassphraseKeychain()
        let store = KeychainPassphraseStore(operations: empty)
        #expect(try store.loadOrCreateKeyReportingFreshness().isFresh)
        #expect(try !store.loadOrCreateKeyReportingFreshness().isFresh)
        #expect(empty.adds == 1 && empty.deletes == 0)

        let racing = FakePassphraseKeychain()
        racing.duplicateWinner = valid
        let result = try KeychainPassphraseStore(operations: racing)
            .loadOrCreateKeyReportingFreshness()
        #expect(result.key == String(data: valid, encoding: .utf8))
        #expect(!result.isFresh && racing.adds == 1 && racing.deletes == 0)
    }

    @Test("Valid preferred and synchronized keys remain byte-for-byte unchanged")
    func validLegacyAndFallback() throws {
        let uppercase = Data(String(repeating: "AB", count: 32).utf8)
        for fake in [
            FakePassphraseKeychain(local: uppercase, synchronized: valid),
            FakePassphraseKeychain(synchronized: valid)
        ] {
            let expected = fake.local ?? valid
            let result = try KeychainPassphraseStore(operations: fake)
                .loadOrCreateKeyReportingFreshness()
            #expect(result.key == String(data: expected, encoding: .utf8))
            #expect(!result.isFresh && fake.adds == 0 && fake.deletes == 0)
        }
        #expect(!KeychainPassphraseStore.isStoredKey(String(repeating: "é", count: 64)))
        #expect(!KeychainPassphraseStore.isStoredKey(String(decoding: valid, as: UTF8.self) + "\n"))
    }
}
