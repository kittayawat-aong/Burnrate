import Foundation

/// Claude account details parsed from `~/.claude.json` (`oauthAccount`).
struct AccountInfo {
    var displayName: String?
    var email: String?
    var organizationName: String?
    var organizationRole: String?
    /// Human-readable plan, e.g. "Claude Pro", derived from `organizationType`.
    var plan: String?
    var rateLimitTier: String?
    var billingType: String?
    var hasExtraUsageEnabled: Bool?
    var accountCreatedAt: Date?
    var subscriptionCreatedAt: Date?
    var accountUuid: String?
    var organizationUuid: String?

    /// Ordered (label, value) pairs shown in the popover.
    /// Trim lines here to taste — each entry is one row.
    var displayRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append((label, value)) }
        }

//        add("Name", displayName)
        add("Email", email)
        add("Plan", plan)
//        add("Organization", organizationName)
//        add("Role", organizationRole?.capitalized)
//        add("Rate tier", rateLimitTier)
//        add("Billing", billingType)
        if let extra = hasExtraUsageEnabled {
            add("Extra usage", extra ? "Enabled" : "Disabled")
        }
//        add("Account created", accountCreatedAt.map(Self.formatDate))
//        add("Subscribed", subscriptionCreatedAt.map(Self.formatDate))
//        add("Account ID", accountUuid)
//        add("Org ID", organizationUuid)
        return rows
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
