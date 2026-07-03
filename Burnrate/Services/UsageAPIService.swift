import Foundation

enum UsageAPIError: Error, LocalizedError {
    case unauthorized
    case rateLimited
    case server(Int)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized (401) — re-login via Claude Code"
        case .rateLimited: return "Rate limited (429)"
        case .server(let code): return "Server error (\(code))"
        case .decoding: return "Could not read usage response"
        case .network(let e): return e.localizedDescription
        }
    }
}

/// Calls the undocumented Anthropic OAuth usage endpoint.
struct UsageAPIService {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        LogService.shared.log(.debug, .api, "GET /api/oauth/usage — Authorization: Bearer \(redacted(accessToken)), anthropic-beta: oauth-2025-04-20")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            LogService.shared.log(.error, .api, "GET /api/oauth/usage network error after \(elapsedMs(since: start))ms: \(error.localizedDescription)")
            throw UsageAPIError.network(error)
        }
        let ms = elapsedMs(since: start)

        guard let http = response as? HTTPURLResponse else {
            LogService.shared.log(.error, .api, "GET /api/oauth/usage returned a non-HTTP response after \(ms)ms")
            throw UsageAPIError.decoding
        }

        switch http.statusCode {
        case 200:
            LogService.shared.log(.debug, .api, "GET /api/oauth/usage -> 200 (\(data.count) bytes, \(ms)ms) — \(bodySnippet(data))")
        case 401:
            LogService.shared.log(.warning, .api, "GET /api/oauth/usage -> 401 Unauthorized (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").map { " (Retry-After: \($0)s)" } ?? ""
            LogService.shared.log(.warning, .api, "GET /api/oauth/usage -> 429 Rate limited\(retryAfter) (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.rateLimited
        default:
            LogService.shared.log(.error, .api, "GET /api/oauth/usage -> \(http.statusCode) (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.server(http.statusCode)
        }

        guard let usage = UsageResponse.parse(data) else {
            LogService.shared.log(.error, .api, "GET /api/oauth/usage: could not parse response body — \(bodySnippet(data))")
            throw UsageAPIError.decoding
        }

        LogService.shared.log(.info, .api, "Usage parsed — session \(describe(usage.session)), weekly \(describe(usage.weekly))")
        return usage
    }

    private static func describe(_ period: UsagePeriod) -> String {
        let resets = period.resetsAt.map(isoFormatter.string) ?? "unknown"
        return "\(Int(period.utilization))% (resets \(resets))"
    }

    private static func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Shows just enough of the token to correlate log lines without leaking
    /// a usable credential into the log file.
    private static func redacted(_ token: String) -> String {
        guard token.count > 12 else { return "***" }
        return "\(token.prefix(8))…\(token.suffix(4))"
    }

    private static let isoFormatter = ISO8601DateFormatter()

    /// A log-safe preview of a response body (usage/error payloads only —
    /// never request headers/tokens). Pretty-prints JSON with indentation so
    /// it's actually readable in the Logs tab / log file, falling back to
    /// the raw text for non-JSON bodies. Truncated so one bad response can't
    /// blow up the log file.
    private static func bodySnippet(_ data: Data) -> String {
        guard !data.isEmpty else { return "(empty body)" }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text.count > 4000 ? String(text.prefix(4000)) + "\n…" : text
        }

        let text = String(data: data, encoding: .utf8) ?? "(non-UTF8 body, \(data.count) bytes)"
        return text.count > 2000 ? String(text.prefix(2000)) + "…" : text
    }
}
