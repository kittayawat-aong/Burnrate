import Foundation
import Security

struct OAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

enum KeychainError: Error, LocalizedError {
    case notFound(status: OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound(let status):
            return "Keychain read failed: \(Self.secMessage(status)) (status \(status))"
        case .invalidData: return "Could not parse Claude credentials"
        }
    }

    private static func secMessage(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown error"
    }
}

/// Which read path produced a set of credentials — used by `UsageViewModel`
/// to decide whether a 401 from the API is trustworthy. Cached credentials
/// can be stale (Claude Code may have silently rotated the token since we
/// last managed a live read), so a 401 on `.cache`-sourced credentials isn't
/// proof the token is actually expired.
enum CredentialsSource {
    case live, cache
}

/// Reads the OAuth credentials that Claude Code stores in the login Keychain
/// under the generic-password service "Claude Code-credentials".
struct KeychainService {
    static let service = "Claude Code-credentials"

    /// Prefers the cached copy (see `CredentialsCache`) over a live read of
    /// Claude Code's Keychain item. A live read of another app's Keychain
    /// item makes macOS show an "Allow access" prompt every time the
    /// requesting app's code signature doesn't match a prior grant (which,
    /// for a frequently-rebuilt app, is often) — so we only pay that cost
    /// when there's no cache yet. Once cached, the /usage API's response is
    /// what decides whether the token is actually still good; see the
    /// cache→live retry in `UsageViewModel.refresh()` for what happens when
    /// it isn't.
    static func loadCredentials() throws -> (credentials: OAuthCredentials, source: CredentialsSource) {
        if let cached = CredentialsCache.load() {
            LogService.shared.log(.debug, .keychain, "Using cached credentials (skipping live Keychain read to avoid a repeated access prompt)")
            return (cached, .cache)
        }

        do {
            let credentials = try readFromClaudeCodeKeychain()
            CredentialsCache.save(credentials)
            LogService.shared.log(.debug, .keychain, "No cache yet — live read of \"\(service)\" succeeded")
            return (credentials, .live)
        } catch {
            LogService.shared.log(.error, .keychain, "No cache yet and live read of \"\(service)\" failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Forces a fresh, uncached Keychain read. Used to confirm whether
    /// cached credentials that the API just rejected with a 401 are really
    /// expired, or whether the earlier live read simply failed transiently
    /// and a retry would have picked up a still-valid (possibly rotated) token.
    static func retryLiveRead() throws -> OAuthCredentials {
        let credentials = try readFromClaudeCodeKeychain()
        CredentialsCache.save(credentials)
        LogService.shared.log(.info, .keychain, "Retry live read of \"\(service)\" succeeded")
        return credentials
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
            throw KeychainError.notFound(status: status)
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
