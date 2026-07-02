import Foundation
import Security

struct OAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

enum KeychainError: Error, LocalizedError {
    case notFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound: return "No Claude credentials found in Keychain"
        case .invalidData: return "Could not parse Claude credentials"
        }
    }
}

/// Reads the OAuth credentials that Claude Code stores in the login Keychain
/// under the generic-password service "Claude Code-credentials".
struct KeychainService {
    static let service = "Claude Code-credentials"

    /// Reads the current credentials from Claude Code's Keychain item. Falls
    /// back to the last known-good copy (see `CredentialsCache`) if that read
    /// fails, since a failed read here doesn't necessarily mean the token is
    /// actually expired — it can also mean the cross-app Keychain access
    /// check itself failed transiently.
    static func loadCredentials() throws -> OAuthCredentials {
        do {
            let credentials = try readFromClaudeCodeKeychain()
            CredentialsCache.save(credentials)
            return credentials
        } catch {
            if let cached = CredentialsCache.load() {
                return cached
            }
            throw error
        }
    }

    private static func readFromClaudeCodeKeychain() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.notFound
        }

        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String
        else {
            throw KeychainError.invalidData
        }

        let refresh = oauth["refreshToken"] as? String

        var expires: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = oauth["expiresAt"] as? Int {
            expires = Date(timeIntervalSince1970: Double(ms) / 1000)
        }

        return OAuthCredentials(accessToken: access, refreshToken: refresh, expiresAt: expires)
    }
}
