import Foundation

private struct CachedGLMLimit: Codable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
    let creditsUsed: Double?
    let creditsTotal: Double?
}

private struct CachedGLMModel: Codable {
    let name: String
    let tokens: Int
}

private struct CachedGLMUsage: Codable {
    let limits: [CachedGLMLimit]
    let plan: String?
    let models: [CachedGLMModel]
    let totalTokens: Int
    let lastUpdated: Date
}

enum GLMUsageCache {
    private static let key = "cachedGLMUsage"

    static func save(_ snapshot: GLMUsageSnapshot, lastUpdated: Date) {
        let cached = CachedGLMUsage(
            limits: snapshot.limits.map {
                CachedGLMLimit(
                    id: $0.id,
                    label: $0.label,
                    utilization: $0.period.utilization,
                    resetsAt: $0.period.resetsAt,
                    creditsUsed: $0.creditsUsed,
                    creditsTotal: $0.creditsTotal
                )
            },
            plan: snapshot.plan,
            models: snapshot.tokensLast24h.map { CachedGLMModel(name: $0.name, tokens: $0.tokens) },
            totalTokens: snapshot.totalTokensLast24h,
            lastUpdated: lastUpdated
        )
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> (snapshot: GLMUsageSnapshot, lastUpdated: Date)? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedGLMUsage.self, from: data) else {
            return nil
        }
        let limits = cached.limits.map {
            GLMUsageLimit(
                id: $0.id,
                label: $0.label,
                period: UsagePeriod(utilization: $0.utilization, resetsAt: $0.resetsAt),
                creditsUsed: $0.creditsUsed,
                creditsTotal: $0.creditsTotal
            )
        }
        return (
            GLMUsageSnapshot(
                limits: limits,
                plan: cached.plan,
                tokensLast24h: cached.models.map { GLMModelUsage(name: $0.name, tokens: $0.tokens) },
                totalTokensLast24h: cached.totalTokens
            ),
            cached.lastUpdated
        )
    }
}
