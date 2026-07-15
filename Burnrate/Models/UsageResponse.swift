import Foundation

/// A single usage window returned by `/api/oauth/usage`.
struct UsagePeriod {
    /// 0–100 percentage used.
    let utilization: Double
    /// When this window resets, if known.
    let resetsAt: Date?
}

/// A scoped entry from the response's `limits` array — a cap that applies to
/// one model or surface only (e.g. the temporary per-model weekly limit for
/// "Fable"). Parsed generically from whatever the endpoint returns, nothing
/// is hardcoded per model: rows appear and disappear in the UI as Anthropic
/// adds or retires scoped limits.
struct ScopedUsage: Identifiable {
    /// Human-readable name from `scope.model.display_name` (or the closest
    /// available fallback).
    let label: String
    /// The `group` field ("session"/"weekly"), used for the window suffix in
    /// the UI. Nil when the response omits it.
    let group: String?
    let period: UsagePeriod

    var id: String { "\(label)-\(group ?? "")" }
}

/// Parsed response from the (undocumented) OAuth usage endpoint.
///
/// The endpoint is undocumented and its shape may change, so parsing is done
/// defensively against several plausible key spellings rather than via a rigid
/// `Codable` model.
struct UsageResponse {
    let session: UsagePeriod   // 5-hour window
    let weekly: UsagePeriod    // 7-day window
    let scopedLimits: [ScopedUsage]  // model/surface-scoped extras, often empty

    static func parse(_ data: Data) -> UsageResponse? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let sessionDict = firstDict(in: root, keys: ["five_hour", "fiveHour", "session", "5h"])
        let weeklyDict = firstDict(in: root, keys: ["seven_day", "sevenDay", "weekly", "7d", "seven_day_oauth_apps"])

        // Require at least one recognizable window.
        guard sessionDict != nil || weeklyDict != nil else { return nil }

        return UsageResponse(
            session: UsagePeriod(from: sessionDict),
            weekly: UsagePeriod(from: weeklyDict),
            scopedLimits: parseScopedLimits(root["limits"] as? [[String: Any]] ?? [])
        )
    }

    /// Picks the entries of the `limits` array that carry a scope with a
    /// nameable target. Unscoped entries (`scope: null`) duplicate the
    /// top-level five_hour/seven_day windows and are skipped.
    private static func parseScopedLimits(_ limits: [[String: Any]]) -> [ScopedUsage] {
        limits.compactMap { entry in
            guard let scope = entry["scope"] as? [String: Any] else { return nil }
            let model = scope["model"] as? [String: Any]
            let surface = scope["surface"] as? [String: Any]
            let label = (model?["display_name"] as? String)
                ?? (model?["id"] as? String)
                ?? (surface?["display_name"] as? String)
            guard let label, !label.isEmpty else { return nil }
            return ScopedUsage(
                label: label,
                group: entry["group"] as? String,
                period: UsagePeriod(from: entry)
            )
        }
    }

    private static func firstDict(in root: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let dict = root[key] as? [String: Any] { return dict }
        }
        return nil
    }
}

extension UsagePeriod {
    init(from dict: [String: Any]?) {
        let dict = dict ?? [:]
        self.utilization = UsagePeriod.number(
            in: dict,
            keys: ["utilization", "percent", "percent_used", "used_percent", "percentage", "used"]
        )
        self.resetsAt = UsagePeriod.date(
            in: dict,
            keys: ["resets_at", "resetsAt", "reset_at", "resetAt"]
        )
    }

    private static func number(in dict: [String: Any], keys: [String]) -> Double {
        for key in keys {
            if let v = dict[key] as? Double { return normalize(v) }
            if let v = dict[key] as? Int { return normalize(Double(v)) }
            if let s = dict[key] as? String, let v = Double(s) { return normalize(v) }
        }
        return 0
    }

    /// Endpoints sometimes return a 0–1 fraction instead of a 0–100 percentage.
    private static func normalize(_ value: Double) -> Double {
        let v = value < 1.0 && value > 0 ? value * 100 : value
        return min(max(v, 0), 100)
    }

    private static func date(in dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let s = dict[key] as? String, let d = parseDate(s) { return d }
            if let ms = dict[key] as? Double { return Date(timeIntervalSince1970: ms > 1_000_000_000_000 ? ms / 1000 : ms) }
            if let ms = dict[key] as? Int {
                let d = Double(ms)
                return Date(timeIntervalSince1970: d > 1_000_000_000_000 ? d / 1000 : d)
            }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
