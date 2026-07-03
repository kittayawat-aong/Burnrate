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
            LogService.shared.log(.debug, .polling, "Cached usage snapshot saved (UserDefaults)")
        }
    }

    static func load() -> CachedUsage? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            LogService.shared.log(.debug, .polling, "No cached usage snapshot on disk")
            return nil
        }
        guard let cached = try? JSONDecoder().decode(CachedUsage.self, from: data) else {
            LogService.shared.log(.warning, .polling, "Cached usage snapshot could not be decoded — ignoring")
            return nil
        }
        LogService.shared.log(.debug, .polling, "Restored cached usage snapshot from \(cached.lastUpdated) — session \(Int(cached.sessionUtilization))%, weekly \(Int(cached.weeklyUtilization))%")
        return cached
    }
}
