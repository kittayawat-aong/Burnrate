import Foundation

private struct CachedCodexLimit: Codable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

private struct CachedCodexUsage: Codable {
    let limits: [CachedCodexLimit]
    let email: String?
    let plan: String?
    let lastUpdated: Date
}

enum CodexUsageCache {
    private static let key = "cachedCodexUsage"

    static func save(_ snapshot: CodexUsageSnapshot, lastUpdated: Date) {
        let cached = CachedCodexUsage(
            limits: snapshot.limits.map {
                CachedCodexLimit(
                    id: $0.id,
                    label: $0.label,
                    utilization: $0.period.utilization,
                    resetsAt: $0.period.resetsAt
                )
            },
            email: snapshot.account?.email,
            plan: snapshot.account?.plan,
            lastUpdated: lastUpdated
        )
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> (snapshot: CodexUsageSnapshot, lastUpdated: Date)? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedCodexUsage.self, from: data) else {
            return nil
        }
        let limits = cached.limits.map {
            CodexUsageLimit(
                id: $0.id,
                label: $0.label,
                period: UsagePeriod(utilization: $0.utilization, resetsAt: $0.resetsAt)
            )
        }
        let account = (cached.email != nil || cached.plan != nil)
            ? CodexAccountInfo(email: cached.email, plan: cached.plan)
            : nil
        return (CodexUsageSnapshot(limits: limits, account: account), cached.lastUpdated)
    }
}
