import Foundation
import Security

/// The access token is all Burnrate needs — the refresh token deliberately
/// stays untouched in Claude Code's Keychain item. Refresh tokens are
/// single-use (rotated by the server), so if Burnrate ever consumed one it
/// would invalidate the copy the CLI still holds and force the CLI into a
/// re-login.
struct OAuthCredentials {
    let accessToken: String
    /// The token's own expiry (`claudeAiOauth.expiresAt`, epoch ms), as
    /// written by Claude Code. A token past this date is certain to 401, so
    /// `UsageViewModel.refresh()` skips the network call entirely instead of
    /// burning a doomed request. Nil when the Keychain JSON omits it or for
    /// cache entries written by older builds.
    var expiresAt: Date? = nil
    /// kSecAttrModificationDate of the Claude Code Keychain item at the time
    /// this token was read from it. Compared against a fresh (prompt-free)
    /// attributes query to tell whether a live re-read could return anything
    /// newer than what we already have. Nil for cache entries written by
    /// older builds.
    var sourceModificationDate: Date? = nil

    /// True when the token is past its own expiry date. False when the
    /// expiry is unknown — only the API's response can judge those.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow <= 0
    }
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
    /// Claude Code's Keychain item, since a live read still costs a Keychain
    /// round-trip even with the `/usr/bin/security` read path below — so we
    /// only pay that cost when there's no cache yet. Once cached, the /usage
    /// API's response is what decides whether the token is actually still
    /// good; see the cache→live retry in `UsageViewModel.refresh()` for what
    /// happens when it isn't.
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

    /// Modification date of Claude Code's Keychain item, via an
    /// attributes-only query. The macOS "allow access" prompt guards the
    /// item's data (kSecValueData), not its attributes, so this never
    /// prompts and is safe to call on every poll. Returns nil when the item
    /// is missing or the query fails.
    static func itemModificationDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any]
        else { return nil }
        return attributes[kSecAttrModificationDate as String] as? Date
    }

    private static func readFromClaudeCodeKeychain() throws -> OAuthCredentials {
        let item = try readRawItem()
        var credentials = try parse(item.json)
        credentials.sourceModificationDate = item.modificationDate
        return credentials
    }

    /// Reads the item's secret data via a shelled-out `/usr/bin/security`
    /// call rather than an in-process `SecItemCopyMatching`. The classic
    /// login-keychain ACL check binds to the *calling process's* code
    /// signature — Burnrate.app asking directly is a foreign, frequently-
    /// rebuilt signature that macOS re-confirms via an "Allow access" prompt,
    /// while Apple's own `/usr/bin/security` binary is the tool the ACL
    /// dialog itself offers to run as, so it reads items lacking an explicit
    /// per-app trust list without prompting. Bounded by a timeout: macOS has
    /// been observed to hang `security` subprocesses indefinitely in some
    /// environments, which would otherwise deadlock the poll loop.
    private static func readRawItem() throws -> (json: [String: Any], modificationDate: Date?) {
        guard let result = runSecurityCommand(arguments: [
            "find-generic-password",
            "-s", service,
            "-a", NSUserName(),
            "-w"
        ]) else {
            throw KeychainError.notFound(status: errSecIO)
        }

        guard !result.timedOut, result.exitCode == 0 else {
            throw KeychainError.notFound(status: OSStatus(result.exitCode))
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw KeychainError.invalidData
        }

        return (json, itemModificationDate())
    }

    private struct SecurityCommandResult {
        let exitCode: Int32
        let stdout: String
        let timedOut: Bool
    }

    private static let securityCommandTimeout: TimeInterval = 3.0

    private static func runSecurityCommand(arguments: [String]) -> SecurityCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + securityCommandTimeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return SecurityCommandResult(exitCode: -1, stdout: "", timedOut: true)
        }

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return SecurityCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            timedOut: false
        )
    }

    private static func parse(_ json: [String: Any]) throws -> OAuthCredentials {
        guard
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String
        else {
            throw KeychainError.invalidData
        }

        var expiresAt: Date?
        if let millis = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: millis / 1000)
        }

        return OAuthCredentials(accessToken: access, expiresAt: expiresAt)
    }
}
