import Foundation
import Security

/// Host-provided secure storage for account passwords (port of `liblanis@0.1.2 lib/src/secret_store.dart`).
public protocol SecretStore: Sendable {
    func write(_ value: String, for key: String) throws
    func read(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var data: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func write(_ value: String, for key: String) { lock.withLock { data[key] = value } }
    public func read(_ key: String) -> String? { lock.withLock { data[key] } }
    public func delete(_ key: String) { _ = lock.withLock { data.removeValue(forKey: key) } }
}

/// Keychain-backed store. Same `service` as the Flutter app's `flutter_secure_storage`
/// can later be used to migrate existing accounts.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    public init(service: String = "io.github.alessioc42.sph.accounts") { self.service = service }

    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    public func write(_ value: String, for key: String) throws {
        try? delete(key)
        var q = query(key)
        q[kSecValueData] = Data(value.utf8)
        #if !targetEnvironment(macCatalyst) && !os(macOS)
        // Data-protection keychain attribute; on macOS / Catalyst it requires a keychain-access-groups
        // entitlement (errSecMissingEntitlement, -34018), so the legacy keychain is used there instead.
        q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecMissingEntitlement, q[kSecAttrAccessible] != nil {
            q.removeValue(forKey: kSecAttrAccessible)
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LanisError.unknown("Keychain write failed: \(status)") }
    }

    public func read(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let d = out as? Data else { throw LanisError.unknown("Keychain read failed: \(status)") }
        return String(data: d, encoding: .utf8)
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LanisError.unknown("Keychain delete failed: \(status)") }
    }
}
