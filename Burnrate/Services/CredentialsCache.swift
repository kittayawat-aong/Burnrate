import Foundation
import Security

/// Caches the last successfully-read Claude Code OAuth credentials under
/// Burnrate's own Keychain item. Reading "Claude Code-credentials" (an item
/// owned by another app) occasionally fails transiently (e.g. the login
/// keychain briefly refusing the cross-app access check) even though the
/// token itself is still valid. When that happens we fall back to this cache
/// instead of reporting the token as expired — the /usage API call is the
/// real arbiter of expiration (a 401 response).
enum CredentialsCache {
    private static let service = "Burnrate-credentials-cache"

    private struct StoredCredentials: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    static func save(_ credentials: OAuthCredentials) {
        let stored = StoredCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return nil }

        return OAuthCredentials(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            expiresAt: stored.expiresAt
        )
    }
}
