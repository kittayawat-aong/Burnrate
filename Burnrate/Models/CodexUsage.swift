import Foundation

/// One metered Codex usage window returned by the local Codex app server.
struct CodexUsageLimit: Identifiable {
    let id: String
    let label: String
    let period: UsagePeriod
}

struct CodexAccountInfo {
    let email: String?
    let plan: String?

    var displayRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let email, !email.isEmpty { rows.append(("Email", email)) }
        if let plan, !plan.isEmpty { rows.append(("Plan", plan.capitalized)) }
        return rows
    }
}

struct CodexUsageSnapshot {
    let limits: [CodexUsageLimit]
    let account: CodexAccountInfo?
}
