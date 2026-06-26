import Foundation
import Security

/// Persists the signed direct-download license token on THIS device. The token
/// is device-bound and never synchronised through iCloud Keychain: each machine
/// activates its own Lemon Squeezy seat.
public protocol LicenseTokenStore: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// Keychain-backed store: device-only accessibility, never synchronizable.
public struct KeychainLicenseTokenStore: LicenseTokenStore {
    public enum Failure: Error, Sendable, Equatable { case keychain(OSStatus) }

    private let service: String
    private let account: String

    public init(
        service: String = "com.johnny4young.gancho.license",
        account: String = "license-token"
    ) {
        self.service = service
        self.account = account
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data, let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    public func save(_ token: String) throws {
        try clear()
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }
}

/// In-memory store for previews, tests, and from-source builds.
public final class InMemoryLicenseTokenStore: LicenseTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) { self.token = token }

    public func load() -> String? { lock.withLock { token } }
    public func save(_ token: String) throws { lock.withLock { self.token = token } }
    public func clear() throws { lock.withLock { self.token = nil } }
}
