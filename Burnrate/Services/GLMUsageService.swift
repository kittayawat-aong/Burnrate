import Foundation
import Alamofire

enum GLMUsageError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case rateLimited
    case server(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GLM (z.ai) is not signed in\nRun “opencode”, use /connect, and pick “Z.AI Coding Plan” — or turn GLM off in Settings."
        case .unauthorized:
            return "GLM usage unauthorized (401)\nThe API key in opencode’s auth.json was rejected — reconnect via opencode /connect."
        case .rateLimited:
            return "GLM usage rate limited (429)"
        case .server(let code, let message):
            return "GLM usage server error (\(code))\(message.map { " — \($0)" } ?? "")"
        case .invalidResponse:
            return "Could not read GLM usage response"
        }
    }
}

/// Reads z.ai GLM Coding Plan usage through the (undocumented) usage-monitor
/// API also used by z.ai's own dashboard. The API key is borrowed — never
/// written or refreshed — from opencode's auth.json, exactly as the CLI
/// stored it. Burnrate never handles z.ai OAuth tokens.
struct GLMUsageService {
    static let quotaEndpoint = "https://api.z.ai/api/monitor/usage/quota/limit"
    static let modelUsageEndpoint = "https://api.z.ai/api/monitor/usage/model-usage"

    /// opencode provider ids that hold a z.ai coding-plan key, in probe order.
    private static let providerIDs = ["zai-coding-plan", "zai", "z-ai", "z.ai", "zhipu", "zhipuai"]
    private static let authURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/opencode/auth.json")

    static func fetch() async throws -> GLMUsageSnapshot {
        let key = try loadAPIKey()
        let limitsEnvelope = try await get(quotaEndpoint, key: key)
        let (limits, plan) = try parseQuota(limitsEnvelope)

        // Token totals are a nice-to-have: a failure here must not fail the
        // whole refresh, the quota windows are the authoritative part.
        var tokens: [GLMModelUsage] = []
        var total = 0
        do {
            let formatter = Self.windowFormatter
            let end = Date()
            let start = end.addingTimeInterval(-24 * 3600)
            let url = Self.modelUsageEndpoint + [
                "?startTime=\(formatter.string(from: start))",
                "&endTime=\(formatter.string(from: end))",
            ].joined()
            let envelope = try await get(url, key: key)
            (tokens, total) = try Self.parseModelUsage(envelope)
        } catch {
            LogService.shared.log(.warning, .glm, "Model usage query failed (ignored): \(error.localizedDescription)")
        }

        return GLMUsageSnapshot(limits: limits, plan: plan, tokensLast24h: tokens, totalTokensLast24h: total)
    }

    // MARK: - Credentials

    /// Extracts the z.ai API key from opencode's auth.json. Entries may be a
    /// bare string or an object ({"type":"api","key":"..."}), so both shapes
    /// are accepted, same as the community clients that discovered this file.
    static func loadAPIKey() throws -> String {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw GLMUsageError.notConfigured
        }
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GLMUsageError.notConfigured
        }
        for id in providerIDs {
            guard let entry = json[id] else { continue }
            if let key = entry as? String, !key.isEmpty {
                return key
            }
            if let object = entry as? [String: Any] {
                for field in ["key", "apiKey", "token", "accessToken"] {
                    if let key = object[field] as? String, !key.isEmpty {
                        return key
                    }
                }
            }
        }
        throw GLMUsageError.notConfigured
    }

    // MARK: - HTTP

    private static func get(_ url: String, key: String) async throws -> [String: Any] {
        // z.ai's monitor API expects the raw key in Authorization — no
        // "Bearer" prefix (verified against the live endpoint).
        let headers: HTTPHeaders = [
            HTTPHeader(name: "Authorization", value: key),
            .accept("application/json"),
            .acceptLanguage("en-US,en"),
        ]

        let start = Date()
        let response = await AF.request(url, method: .get, headers: headers) {
            $0.timeoutInterval = 20
        }
        .serializingData()
        .response
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response.response else {
            LogService.shared.log(.error, .glm, "GET \(url) network error after \(ms)ms: \(response.error?.localizedDescription ?? "unknown")")
            throw response.error ?? URLError(.unknown)
        }
        let data = response.data ?? Data()
        guard http.statusCode == 200 else {
            LogService.shared.log(.warning, .glm, "GET \(url) -> \(http.statusCode) (\(ms)ms) — \(String(data: data, encoding: .utf8) ?? "")")
            switch http.statusCode {
            case 401: throw GLMUsageError.unauthorized
            case 429: throw GLMUsageError.rateLimited
            default: throw GLMUsageError.server(http.statusCode, nil)
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GLMUsageError.invalidResponse
        }
        return json
    }

    // MARK: - Parsing

    private static func parseQuota(_ envelope: [String: Any]) throws -> ([GLMUsageLimit], String?) {
        guard envelope["code"] as? Int == 200, let data = envelope["data"] as? [String: Any] else {
            let message = envelope["msg"] as? String
            throw GLMUsageError.server(envelope["code"] as? Int ?? -1, message)
        }
        let plan = (data["level"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawLimits = data["limits"] as? [[String: Any]], !rawLimits.isEmpty else {
            throw GLMUsageError.invalidResponse
        }

        var limits: [GLMUsageLimit] = []
        for raw in rawLimits {
            guard let percentage = number(raw["percentage"]) else { continue }
            let resetsAt = number(raw["nextResetTime"]).map { Date(timeIntervalSince1970: $0 / 1000) }
            let unit = number(raw["unit"]).map(Int.init)
            let count = number(raw["number"]).map(Int.init)
            let type = raw["type"] as? String

            limits.append(
                GLMUsageLimit(
                    id: "glm-\(type ?? "limit")-\(unit ?? 0)-\(count ?? 0)",
                    label: windowLabel(unit: unit, count: count, resetsAt: resetsAt),
                    period: UsagePeriod(
                        utilization: min(max(percentage, 0), 100),
                        resetsAt: resetsAt
                    ),
                    creditsUsed: number(raw["currentValue"]),
                    creditsTotal: number(raw["usage"])
                )
            )
        }
        guard !limits.isEmpty else { throw GLMUsageError.invalidResponse }
        // Soonest reset first: limits.first is the active short (session)
        // window, matching how the menu bar picks what to display.
        limits.sort { ($0.period.resetsAt ?? .distantFuture) < ($1.period.resetsAt ?? .distantFuture) }
        return (limits, plan)
    }

    private static func parseModelUsage(_ envelope: [String: Any]) throws -> ([GLMModelUsage], Int) {
        guard envelope["code"] as? Int == 200, let data = envelope["data"] as? [String: Any],
              let totals = data["totalUsage"] as? [String: Any] else {
            throw GLMUsageError.invalidResponse
        }
        let total = number(totals["totalTokensUsage"]).map(Int.init) ?? 0
        let models = ((totals["modelSummaryList"] as? [[String: Any]]) ?? [])
            .compactMap { summary -> GLMModelUsage? in
                guard let name = summary["modelName"] as? String else { return nil }
                let tokens = number(summary["totalTokens"]).map(Int.init) ?? 0
                return GLMModelUsage(name: name, tokens: tokens)
            }
            .sorted { $0.tokens > $1.tokens }
        return (models, total)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    /// Window names from the observed unit encodings: unit 3 counts hours
    /// (the coding plan's rolling 5-hour window), unit 6 counts months.
    /// Anything unrecognized falls back to classifying by how far away the
    /// reset is, so new window shapes still render sensibly.
    private static func windowLabel(unit: Int?, count: Int?, resetsAt: Date?) -> String {
        switch (unit, count) {
        case (3, 5): return "Session (5h)"
        case (3, let hours?): return "\(hours)-hour window"
        case (6, let months?) where months == 1: return "Monthly"
        case (6, let months?): return "\(months)-month window"
        default:
            let distance = resetsAt.map { $0.timeIntervalSinceNow } ?? 0
            return distance < 24 * 3600 ? "Session" : "Usage window"
        }
    }

    /// The monitor API takes local wall-clock times ("yyyy-MM-dd HH:mm:ss"),
    /// matching the hourly buckets the response is bucketed by.
    private static let windowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
