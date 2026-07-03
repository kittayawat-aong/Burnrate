import Foundation

/// Reads Claude account info from `~/.claude.json` (written by Claude Code).
struct AccountService {
    static func loadAccount() -> AccountInfo? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")

        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let oauth = root["oauthAccount"] as? [String: Any]
        else {
            LogService.shared.log(.warning, .account, "Could not read account info from ~/.claude.json")
            return nil
        }

        LogService.shared.log(.debug, .account, "Loaded account info from ~/.claude.json")
        return AccountInfo(
            displayName: oauth["displayName"] as? String,
            email: oauth["emailAddress"] as? String,
            organizationName: oauth["organizationName"] as? String,
            organizationRole: oauth["organizationRole"] as? String,
            plan: pretty(oauth["organizationType"] as? String),
            rateLimitTier: pretty(oauth["organizationRateLimitTier"] as? String),
            billingType: pretty(oauth["billingType"] as? String),
            hasExtraUsageEnabled: oauth["hasExtraUsageEnabled"] as? Bool,
            accountCreatedAt: isoDate(oauth["accountCreatedAt"] as? String),
            subscriptionCreatedAt: isoDate(oauth["subscriptionCreatedAt"] as? String),
            accountUuid: oauth["accountUuid"] as? String,
            organizationUuid: oauth["organizationUuid"] as? String
        )
    }

    /// "claude_pro" -> "Claude Pro", "stripe_subscription" -> "Stripe Subscription".
    private static func pretty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    private static func isoDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
