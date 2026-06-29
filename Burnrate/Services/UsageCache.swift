import Foundation

/// The last successful usage fetch, persisted so values survive relaunches and
/// remain visible when a later fetch fails (e.g. 429).
struct CachedUsage: Codable {
    var sessionUtilization: Double
    var sessionResetsAt: Date?
    var weeklyUtilization: Double
    var weeklyResetsAt: Date?
    var lastUpdated: Date
}

enum UsageCache {
    private static let key = "cachedUsage"

    static func save(session: UsagePeriod, weekly: UsagePeriod, lastUpdated: Date) {
        let cached = CachedUsage(
            sessionUtilization: session.utilization,
            sessionResetsAt: session.resetsAt,
            weeklyUtilization: weekly.utilization,
            weeklyResetsAt: weekly.resetsAt,
            lastUpdated: lastUpdated
        )
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> CachedUsage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }
}
