import Foundation

#if canImport(Security)
    import Security
#endif

/// A Keychain-backed `CloudTokenStore` (WG-185). The optional cloud-AI token lives in the Keychain —
/// **never in source or `UserDefaults`** — as a **this-device-only** item, is returned wrapped in
/// `Sensitive` (so it can't be logged), and is **revocable** via `SecItemDelete`. This file performs no
/// logging. If Security is unavailable, it fails closed.
struct KeychainCloudTokenStore: CloudTokenStore {
    private let service = "com.wakeguard.cloudAI"
    private let account = "cloudAIToken"

    func token() async -> Sensitive<String>? {
        #if canImport(Security)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data,
                let string = String(bytes: data, encoding: .utf8)
            else { return nil }
            return Sensitive(string)
        #else
            return nil
        #endif
    }

    func store(_ token: Sensitive<String>) async throws {
        #if canImport(Security)
            let data = Data(token.reveal().utf8)
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            _ = SecItemDelete(base as CFDictionary)
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw CloudTokenStoreError.keychain(status: status)
            }
        #else
            throw CloudTokenStoreError.unavailable
        #endif
    }

    func revoke() async throws {
        #if canImport(Security)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CloudTokenStoreError.keychain(status: status)
            }
        #else
            throw CloudTokenStoreError.unavailable
        #endif
    }

    func hasToken() async -> Bool {
        await token() != nil
    }
}

/// A cloud-token-store failure (WG-185). `status` is the raw Keychain `OSStatus` — a code, never the token.
enum CloudTokenStoreError: Error, Sendable, Equatable, Hashable {
    case unavailable
    case keychain(status: Int32)
}
