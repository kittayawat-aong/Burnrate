import Foundation

/// One metered GLM Coding Plan window returned by z.ai's usage monitor API.
struct GLMUsageLimit: Identifiable {
    let id: String
    let label: String
    let period: UsagePeriod
    /// Credits consumed in this window, when the plan reports credits.
    let creditsUsed: Double?
    let creditsTotal: Double?

    var creditsText: String? {
        guard let creditsUsed, let creditsTotal, creditsTotal > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let used = formatter.string(from: NSNumber(value: creditsUsed)) ?? "\(Int(creditsUsed))"
        let total = formatter.string(from: NSNumber(value: creditsTotal)) ?? "\(Int(creditsTotal))"
        return "\(used) / \(total) credits used"
    }
}

/// Token totals for one model over the last 24 hours.
struct GLMModelUsage: Identifiable {
    var id: String { name }
    let name: String
    let tokens: Int
}

struct GLMUsageSnapshot {
    /// Sorted soonest-reset first, so `limits.first` is the active short window.
    let limits: [GLMUsageLimit]
    /// Plan tier reported by z.ai (e.g. "lite"). Nil when absent.
    let plan: String?
    let tokensLast24h: [GLMModelUsage]
    let totalTokensLast24h: Int
}
