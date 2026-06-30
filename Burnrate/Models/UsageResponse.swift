import Foundation

/// A single usage window returned by `/api/oauth/usage`.
struct UsagePeriod {
    /// 0–100 percentage used.
    let utilization: Double
    /// When this window resets, if known.
    let resetsAt: Date?
}

/// Parsed response from the (undocumented) OAuth usage endpoint.
///
/// The endpoint is undocumented and its shape may change, so parsing is done
/// defensively against several plausible key spellings rather than via a rigid
/// `Codable` model.
struct UsageResponse {
    let session: UsagePeriod   // 5-hour window
    let weekly: UsagePeriod    // 7-day window

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
            weekly: UsagePeriod(from: weeklyDict)
        )
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
            keys: ["utilization", "percent_used", "used_percent", "percentage", "used"]
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
