import Foundation
import Security
import Synchronization

/// Persists the direct-download activation record on THIS device. The record is
/// never synchronized through iCloud Keychain: each machine activates its own
/// Lemon Squeezy seat.
///
/// The token-shaped API name and default Keychain account are retained for
/// source and on-disk compatibility with builds that preceded activation
/// records. Values are now JSON-encoded `LicenseActivationRecord` instances,
/// never locally signed tokens.
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
            kSecAttrAccount as String: account
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
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Failure.keychain(updateStatus)
        }

        var addition = baseQuery()
        addition.merge(attributes) { _, replacement in replacement }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.keychain(addStatus) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }
}

/// In-memory store for previews, tests, and from-source builds.
public final class InMemoryLicenseTokenStore: LicenseTokenStore {
    private let storedToken: Mutex<String?>

    public init(token: String? = nil) { self.storedToken = Mutex(token) }

    public func load() -> String? { storedToken.withLock { $0 } }
    public func save(_ token: String) throws { storedToken.withLock { $0 = token } }
    public func clear() throws { storedToken.withLock { $0 = nil } }
}
